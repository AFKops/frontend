from quart import Quart, websocket
import asyncssh
import logging
import asyncio
import json
import uuid
import re

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
ANSI_ESCAPE = re.compile(
    r"(?:\x1B[@-_][0-?]*[ -/]*[@-~])"
    r"|(?:\x9B[0-?]*[ -/]*[@-~])"
)
PROMPT_REGEX = re.compile(r"^[\w@.-]+[:~\s]+\$ ")


###############################################################################
# WebSocket endpoint /ssh-stream
###############################################################################
@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = str(uuid.uuid4())
    session = {"conn": None, "proc": None, "read_task": None}
    active_sessions[session_id] = session

    try:
        # Accept the WebSocket connection
        await websocket.accept()
        logger.info(f"[{session_id}] WebSocket connected.")

        # ----------------------------------------------------------------------
        # Background task: read from the interactive bash process line by line
        # ----------------------------------------------------------------------
        async def read_bash(proc):
            try:
                output_buffer = []
                while not proc.stdout.at_eof():
                    line = await proc.stdout.readline()
                    if line:
                        # Remove ANSI escapes and shell prompt
                        clean_line = ANSI_ESCAPE.sub('', line).strip()
                        clean_line = PROMPT_REGEX.sub('', clean_line).strip()

                        # If it looks like a typed command, wrap in <small> tags
                        if re.search(r"\$\s(cd|ls|pwd|mkdir|rm|touch|echo|cat|nano)", clean_line):
                            clean_line = f"<small>{clean_line}</small>"

                        if clean_line:
                            output_buffer.append(clean_line)

                    # Send batched output lines in one JSON message
                    if output_buffer:
                        await websocket.send_json({"output": "\n".join(output_buffer)})
                        output_buffer.clear()
            except asyncio.CancelledError:
                logger.info(f"[{session_id}] read_bash cancelled.")
            except Exception as e:
                logger.exception(f"[{session_id}] Error reading bash output:")
                await websocket.send_json({"error": f"Bash read error: {str(e)}"})

        # ----------------------------------------------------------------------
        # Main WebSocket loop: handle JSON messages from the Flutter client
        # ----------------------------------------------------------------------
        while True:
            data = await websocket.receive_json()
            logger.debug(f"[{session_id}] Received data: {json.dumps(data, indent=2)}")

            action = data.get("action", "").upper().strip()
            if not action:
                await websocket.send_json({"error": "No 'action' specified."})
                continue

            # ------------------------------------------------------------------
            # 1) CONNECT
            # ------------------------------------------------------------------
            if action == "CONNECT":
                host = data.get("host")
                username = data.get("username")
                password = data.get("password")
                if not all([host, username, password]):
                    await websocket.send_json({"error": "Missing host/username/password"})
                    continue

                # If already connected, reuse session
                if session["conn"] is not None:
                    await websocket.send_json({"info": "Already connected, reusing session"})
                    continue

                try:
                    logger.info(f"[{session_id}] Connecting to {host} as {username}...")
                    conn = await asyncssh.connect(
                        host=host,
                        username=username,
                        password=password,
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

                    # Start reading from the bash process in the background
                    read_task = asyncio.create_task(read_bash(proc))
                    session["read_task"] = read_task

                    await websocket.send_json({"info": "Interactive Bash session started."})
                    logger.info(f"[{session_id}] Connected + interactive Bash ready with PTY.")

                except asyncssh.Error as e:
                    logger.error(f"[{session_id}] SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})

            # ------------------------------------------------------------------
            # 2) RUN_COMMAND
            # ------------------------------------------------------------------
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

            # ------------------------------------------------------------------
            # 3) STOP
            # ------------------------------------------------------------------
            elif action == "STOP":
                proc = session.get("proc")
                if proc:
                    logger.info(f"[{session_id}] Sending Ctrl-C to bash.")
                    proc.stdin.write("\x03")  # Ctrl-C
                    await websocket.send_json({"output": "Sent Ctrl-C."})
                else:
                    await websocket.send_json({"info": "No interactive shell to stop."})

            # ------------------------------------------------------------------
            # 4) LIST_FILES
            #
            # *** FIX: We REMOVED any $(pwd)/ logic to trust the absolute path
            #          the Flutter app already sends us. ***
            # ------------------------------------------------------------------
            elif action == "LIST_FILES":
                if session["conn"] is None:
                    await websocket.send_json({"error": "Not connected. Send action=CONNECT first."})
                    continue

                directory = data.get("directory", ".").strip()

                # We do NOT prepend $(pwd)/ or do any "cd" here. This ephemeral
                # process won't share the interactive shell's state, so we
                # assume the client is sending an absolute path if needed.
                #
                # => e.g. "ls -d -- '/var/www'/*/"
                #
                list_cmd = (
                    f'ls -d -- "{directory}"/*/ 2>/dev/null | xargs -I {{}} basename {{}}'
                )
                logger.info(f"[{session_id}] Fetching directories for: {directory}")

                try:
                    # Create ephemeral process just for listing
                    ephemeral = await session["conn"].create_process(list_cmd)
                    results = []
                    async for line in ephemeral.stdout:
                        results.append(line.strip())

                    logger.info(f"[{session_id}] Found directories: {results}")
                    await websocket.send_json({"directories": results})

                except Exception as e:
                    logger.exception(f"[{session_id}] Error listing directories:")
                    await websocket.send_json({"error": f"List files error: {str(e)}"})

            # ------------------------------------------------------------------
            # UNKNOWN ACTION
            # ------------------------------------------------------------------
            else:
                logger.warning(f"[{session_id}] Unknown action: {action}")
                await websocket.send_json({"error": f"Unknown action: {action}"})

    # --------------------------------------------------------------------------
    # Handle any exceptions from the main loop
    # --------------------------------------------------------------------------
    except asyncio.IncompleteReadError:
        logger.warning(f"[{session_id}] IncompleteReadError.")
    except asyncssh.Error as e:
        logger.error(f"[{session_id}] SSH error: {str(e)}")
        await websocket.send_json({"error": f"SSH error: {str(e)}"})
    except Exception as e:
        logger.exception(f"[{session_id}] Unexpected error in websocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
        # ----------------------------------------------------------------------
        # Cleanup session on disconnect
        # ----------------------------------------------------------------------
        proc = session.get("proc")
        if proc:
            logger.info(f"[{session_id}] Exiting interactive bash.")
            try:
                proc.stdin.write("exit\n")
                await asyncio.sleep(0.1)
                proc.stdin.write("\x04")  # Ctrl-D
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


###############################################################################
# Main entry: run Hypercorn
###############################################################################
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
