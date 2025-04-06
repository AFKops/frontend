import asyncssh
import logging
import asyncio
import json
import uuid
import re
import base64
from quart import Quart, websocket
from dotenv import load_dotenv
import os
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

load_dotenv("/var/www/chatops/.env")
AES_KEY_B64 = os.getenv("ENCRYPTION_KEY")

def decrypt_aes_cbc(encrypted_b64: str, key_b64: str) -> str:
    encrypted_data = base64.b64decode(encrypted_b64)
    key = base64.b64decode(key_b64)
    iv = encrypted_data[:16]
    ciphertext = encrypted_data[16:]
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    decrypted_padded = decryptor.update(ciphertext) + decryptor.finalize()
    pad_len = decrypted_padded[-1]
    return decrypted_padded[:-pad_len].decode('utf-8')

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)

app = Quart(__name__)
active_sessions = {}

ANSI_ESCAPE = re.compile(r"(?:\x1B[@-_][0-?]*[ -/]*[@-~])|(?:\x9B[0-?]*[ -/]*[@-~])")
PROMPT_REGEX = re.compile(r"^[\w@.-]+[:~\s]+\$ ")

@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = str(uuid.uuid4())
    session = {"conn": None, "proc": None, "read_task": None}
    active_sessions[session_id] = session

    try:
        await websocket.accept()
        logger.info(f"[{session_id}] WebSocket connected.")

        async def read_bash(proc):
            try:
                output_buffer = []
                while not proc.stdout.at_eof():
                    line = await proc.stdout.readline()
                    if line:
                        clean_line = ANSI_ESCAPE.sub('', line).strip()
                        clean_line = PROMPT_REGEX.sub('', clean_line).strip()
                        if re.search(r"\$\s(cd|ls|pwd|mkdir|rm|touch|echo|cat|nano)", clean_line):
                            clean_line = f"<small>{clean_line}</small>"
                        if clean_line:
                            output_buffer.append(clean_line)
                    if output_buffer:
                        await websocket.send_json({"output": "\n".join(output_buffer)})
                        output_buffer.clear()
            except asyncio.CancelledError:
                logger.info(f"[{session_id}] read_bash cancelled.")
            except Exception as e:
                logger.exception(f"[{session_id}] Error reading bash output:")
                await websocket.send_json({"error": f"Bash read error: {str(e)}"})

        while True:
            data = await websocket.receive_json()
            logger.debug(f"[{session_id}] Received action: {data.get('action')}")

            action = data.get("action", "").upper().strip()
            if not action:
                await websocket.send_json({"error": "No 'action' specified."})
                continue

            if action == "CONNECT":
                encrypted_host = data.get("host")
                encrypted_username = data.get("username")
                mode = data.get("mode", "PASSWORD")

                if not all([encrypted_host, encrypted_username, mode]):
                    await websocket.send_json({"error": "Missing encrypted credentials"})
                    continue

                try:
                    host = decrypt_aes_cbc(encrypted_host, AES_KEY_B64)
                    username = decrypt_aes_cbc(encrypted_username, AES_KEY_B64)

                    if mode == "PASSWORD":
                        encrypted_password = data.get("password")
                        if not encrypted_password:
                            await websocket.send_json({"error": "Missing encrypted password"})
                            continue
                        password = decrypt_aes_cbc(encrypted_password, AES_KEY_B64)

                    elif mode == "KEY":
                        encrypted_key = data.get("key")
                        if not encrypted_key:
                            await websocket.send_json({"error": "Missing encrypted private key"})
                            continue
                        private_key_b64 = decrypt_aes_cbc(encrypted_key, AES_KEY_B64)
                        try:
                            # This works for both pasted PEM and file contents
                            private_key_decoded = base64.b64decode(private_key_b64).decode()
                            logger.debug(f"[{session_id}] Decoded key preview: {private_key_decoded[:40]}...")
                            imported_key = asyncssh.import_private_key(private_key_decoded)
                        except Exception as e:
                            logger.error(f"[{session_id}] Invalid private key format: {e}")
                            await websocket.send_json({"error": f"Invalid private key format: {str(e)}"})
                            continue
                    else:
                        await websocket.send_json({"error": f"Unknown auth mode: {mode}"})
                        continue

                    logger.debug(f"[{session_id}] Decrypted Host: {host}")
                    logger.debug(f"[{session_id}] Decrypted User: {username}")

                except Exception as e:
                    logger.exception(f"[{session_id}] AES decryption failed")
                    await websocket.send_json({"error": f"Failed to decrypt credentials: {str(e)}"})
                    continue

                if session["conn"] is not None:
                    await websocket.send_json({"info": "Already connected, reusing session"})
                    continue

                try:
                    logger.info(f"[{session_id}] Connecting to host: {host}")
                    if mode == "PASSWORD":
                        conn = await asyncssh.connect(
                            host=host,
                            username=username,
                            password=password,
                            known_hosts=None
                        )
                    else:
                        conn = await asyncssh.connect(
                            host=host,
                            username=username,
                            client_keys=[imported_key],
                            known_hosts=None
                        )
                    session["conn"] = conn
                    proc = await conn.create_process("bash -i", term_type="xterm", term_size=(120, 40))
                    session["proc"] = proc
                    session["read_task"] = asyncio.create_task(read_bash(proc))

                    await websocket.send_json({"info": "Interactive Bash session started."})
                    logger.info(f"[{session_id}] Connected + interactive Bash ready with PTY.")

                except asyncssh.PermissionDenied:
                    logger.error(f"[{session_id}] Authentication failed.")
                    await websocket.send_json({"error": "Authentication failed: Incorrect credentials."})
                except asyncssh.Error as e:
                    logger.error(f"[{session_id}] SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})

            elif action == "RUN_COMMAND":
                if session["conn"] is None or session["proc"] is None:
                    await websocket.send_json({"error": "Not connected. Send action=CONNECT first."})
                    continue
                cmd = data.get("command", "").strip()
                if not cmd:
                    await websocket.send_json({"error": "Missing 'command' parameter"})
                    continue
                logger.info(f"[{session_id}] RUN_COMMAND: {cmd}")
                try:
                    session["proc"].stdin.write(cmd + "\n")
                except Exception as e:
                    logger.exception(f"[{session_id}] Error writing command:")
                    await websocket.send_json({"error": f"Write error: {str(e)}"})

            elif action == "CTRL_C":
                if session["proc"] and session["proc"].stdin:
                    try:
                        logger.info(f"[{session_id}] Sending Ctrl+C (SIGINT)")
                        session["proc"].stdin.write("\x03")
                    except Exception as e:
                        logger.exception(f"[{session_id}] Error sending Ctrl+C:")
                        await websocket.send_json({"error": f"Failed to send Ctrl+C: {str(e)}"})
                else:
                    await websocket.send_json({"error": "Process not active. Cannot send Ctrl+C."})

            elif action == "LIST_FILES":
                if session["conn"] is None:
                    await websocket.send_json({"error": "Not connected. Send action=CONNECT first."})
                    continue
                directory = data.get("directory", "").strip()
                if not directory:
                    await websocket.send_json({"error": "No directory provided."})
                    continue
                logger.info(f"[{session_id}] LIST_FILES in: {directory}")
                try:
                    result = await session["conn"].run(f'ls -1 "{directory}"', check=False)
                    if result.exit_status == 0:
                        lines = result.stdout.splitlines()
                        await websocket.send_json({"directories": lines})
                    else:
                        await websocket.send_json({"error": f"'ls' returned exit code {result.exit_status}"})
                except Exception as e:
                    logger.exception(f"[{session_id}] Error listing files:")
                    await websocket.send_json({"error": f"LIST_FILES error: {str(e)}"})

            else:
                logger.warning(f"[{session_id}] Unknown action: {action}")
                await websocket.send_json({"error": f"Unknown action: {action}"})

    except Exception as e:
        logger.exception(f"[{session_id}] Unexpected error in websocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
        proc = session.get("proc")
        if proc:
            logger.info(f"[{session_id}] Exiting interactive bash.")
            try:
                proc.stdin.write("exit\n")
                await asyncio.sleep(0.1)
                proc.stdin.write("\x04")
            except:
                pass
        conn = session.get("conn")
        if conn:
            logger.info(f"[{session_id}] Closing SSH connection.")
            await conn.close()
        read_task = session.get("read_task")
        if read_task:
            read_task.cancel()
        if session_id in active_sessions:
            del active_sessions[session_id]
        try:
            await websocket.close()
        except:
            pass
        logger.info(f"[{session_id}] WebSocket disconnected.")

@app.route('/get-key')
async def get_key():
    return {"key": AES_KEY_B64}

if __name__ == "__main__":
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["0.0.0.0:5000"]
    logging.getLogger("hypercorn.error").propagate = False
    logging.getLogger("asyncio").setLevel(logging.WARNING)

    logger = logging.getLogger("main")
    logger.info("Starting server on 0.0.0.0:5000")

    try:
        asyncio.run(serve(app, config))
    except KeyboardInterrupt:
        logger.info("Server shutdown requested")
    except Exception as e:
        logger.critical(f"Server crashed: {str(e)}")
