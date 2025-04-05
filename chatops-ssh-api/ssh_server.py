import asyncssh
import logging
import asyncio
import json
import uuid
import re
import base64  # ✅ For decoding password
from quart import Quart, websocket
from dotenv import load_dotenv
import os
from cryptography.fernet import Fernet

# Load .env file
load_dotenv("/var/www/chatops/.env")

# Get encryption key from environment
FERNET_KEY = os.getenv("ENCRYPTION_KEY")
fernet = Fernet(FERNET_KEY)

# -----------------------------------------------------------------------------
# Configure logging
# -----------------------------------------------------------------------------
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)

# -----------------------------------------------------------------------------
# Create Quart app and store active sessions
# -----------------------------------------------------------------------------
app = Quart(__name__)
active_sessions = {}  # session_id -> {"conn", "proc", "read_task"}

# -----------------------------------------------------------------------------
# ANSI / Shell prompt cleaning
# -----------------------------------------------------------------------------
ANSI_ESCAPE = re.compile(r"(?:\x1B[@-_][0-?]*[ -/]*[@-~])|(?:\x9B[0-?]*[ -/]*[@-~])")
PROMPT_REGEX = re.compile(r"^[\w@.-]+[:~\s]+\$ ")

# -----------------------------------------------------------------------------
# Decode password (base64)
# -----------------------------------------------------------------------------
def decode_password(encoded_password):
    try:
        return base64.b64decode(encoded_password).decode("utf-8")
    except Exception:
        return encoded_password

# -----------------------------------------------------------------------------
# WebSocket endpoint /ssh-stream
# -----------------------------------------------------------------------------
@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = str(uuid.uuid4())
    session = {"conn": None, "proc": None, "read_task": None}
    active_sessions[session_id] = session

    try:
        await websocket.accept()
        logger.info(f"[{session_id}] WebSocket connected.")

        # ---------------------------------------------------------------------
        # Continuously read from the interactive shell (bash -i)
        # ---------------------------------------------------------------------
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
                host = data.get("host")
                username = data.get("username")
                password = data.get("password")

                if not all([host, username, password]):
                    await websocket.send_json({"error": "Missing host/username/password"})
                    continue

                decoded_password = decode_password(password)

                if session["conn"] is not None:
                    await websocket.send_json({"info": "Already connected, reusing session"})
                    continue

                try:
                    logger.info(f"[{session_id}] Connecting to host: {host}")
                    conn = await asyncssh.connect(
                        host=host,
                        username=username,
                        password=decoded_password,
                        known_hosts=None
                    )
                    session["conn"] = conn

                    logger.info(f"[{session_id}] Starting interactive bash -i with PTY ...")
                    proc = await conn.create_process(
                        "bash -i",
                        term_type="xterm",
                        term_size=(120, 40)
                    )
                    session["proc"] = proc

                    read_task = asyncio.create_task(read_bash(proc))
                    session["read_task"] = read_task

                    await websocket.send_json({"info": "Interactive Bash session started."})
                    logger.info(f"[{session_id}] Connected + interactive Bash ready with PTY.")

                except asyncssh.AuthenticationError:
                    logger.error(f"[{session_id}] Authentication failed.")
                    await websocket.send_json({"error": "❌ Authentication failed: Incorrect username or password."})
                except asyncssh.Error as e:
                    logger.error(f"[{session_id}] SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"❌ SSH Error: {str(e)}"})

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
                    result = await session["conn"].run(
                        f'ls -1 "{directory}"',
                        check=False
                    )
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

    except asyncio.IncompleteReadError:
        logger.warning(f"[{session_id}] IncompleteReadError.")
    except asyncssh.Error as e:
        logger.error(f"[{session_id}] SSH Error: {str(e)}")
        await websocket.send_json({"error": f"❌ SSH Error: {str(e)}"})
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

# -----------------------------------------------------------------------------
# Run server with Hypercorn
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["0.0.0.0:5000"]

    logging.getLogger("hypercorn.error").propagate = False
    logging.getLogger("asyncio").setLevel(logging.WARNING)

    logger = logging.getLogger("main")
    logger.info("🚀 Starting server on 0.0.0.0:5000")

    try:
        asyncio.run(serve(app, config))
    except KeyboardInterrupt:
        logger.info("🔻 Server shutdown requested")
    except Exception as e:
        logger.critical(f"🔥 Server crashed: {str(e)}")