from quart import Quart, websocket
import asyncssh
import logging
import asyncio
import json
import uuid

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()]
)

app = Quart(__name__)

# Store active SSH sessions (Persistent Connection)
# Format: {session_id: {"conn": asyncssh.Connection, "process": asyncssh.Process}}
active_sessions = {}

@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = str(uuid.uuid4())
    session = {"conn": None, "process": None}
    active_sessions[session_id] = session

    try:
        await websocket.accept()
        logger.info(f"✅ WebSocket connected (Session: {session_id})")

        while True:
            data = await websocket.receive_json()
            logger.debug(f"📥 Received data: {json.dumps(data, indent=2)}")

            action = data.get("action", "").upper().strip()
            if not action:
                await websocket.send_json({"error": "❌ Missing 'action' field"})
                continue

            # --------------------------------------------------------
            # 1) CONNECT - Set up the SSH session once
            # --------------------------------------------------------
            if action == "CONNECT":
                host = data.get("host")
                username = data.get("username")
                password = data.get("password")
                if not all([host, username, password]):
                    await websocket.send_json({"error": "❌ Missing host/username/password"})
                    continue

                if session["conn"] is not None:
                    # Already connected: you could either close the old connection
                    # or simply notify the client. Here we just reuse it.
                    await websocket.send_json({"info": "🔄 Already connected, reusing session"})
                    continue

                # Establish SSH connection once
                try:
                    logger.info(f"🔐 Establishing persistent SSH connection to {host}...")
                    conn = await asyncssh.connect(
                        host=host,
                        username=username,
                        password=password,
                        known_hosts=None
                    )
                    session["conn"] = conn
                    logger.info(f"✅ SSH connection established (Session: {session_id})")
                    await websocket.send_json({"info": "✅ SSH connected successfully"})
                except asyncssh.Error as e:
                    logger.error(f"❌ SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})

            # --------------------------------------------------------
            # 2) RUN_COMMAND - Execute a normal command (short or long)
            # --------------------------------------------------------
            elif action == "RUN_COMMAND":
                # Make sure we have a connected session
                if session["conn"] is None:
                    await websocket.send_json({"error": "❌ Not connected. Send action=CONNECT first."})
                    continue

                command = data.get("command")
                if not command:
                    await websocket.send_json({"error": "❌ Missing 'command' parameter"})
                    continue

                # If there was a previous streaming process, you might want
                # to terminate it or let it run concurrently. We'll assume
                # we stop it here:
                if session["process"]:
                    session["process"].terminate()
                    session["process"] = None

                safe_command = f"stdbuf -oL {command}"
                logger.info(f"⚡ Executing: {safe_command}")
                try:
                    process = await session["conn"].create_process(safe_command, term_type="xterm")
                    session["process"] = process

                    async def read_stream(stream, is_error=False):
                        while not stream.at_eof():
                            line = await stream.readline()
                            if line:
                                await websocket.send_json({
                                    "output": line.rstrip("\n"),
                                    "error": is_error
                                })

                    # Gather stdout & stderr
                    await asyncio.gather(
                        read_stream(process.stdout),
                        read_stream(process.stderr, is_error=True)
                    )

                except asyncssh.Error as e:
                    logger.error(f"❌ SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})
                except Exception as e:
                    logger.exception("❌ Unexpected error during RUN_COMMAND")
                    await websocket.send_json({"error": f"Server Error: {str(e)}"})

            # --------------------------------------------------------
            # 3) STOP - Terminates the currently running process (stream)
            # --------------------------------------------------------
            elif action == "STOP":
                if session["process"]:
                    logger.info("🛑 Stopping active process")
                    session["process"].terminate()
                    session["process"] = None
                    await websocket.send_json({"output": "❌ Streaming/process stopped."})
                else:
                    await websocket.send_json({"info": "No active process to stop."})

            # --------------------------------------------------------
            # 4) LIST_FILES - Example: directory listing
            # --------------------------------------------------------
            elif action == "LIST_FILES":
                if session["conn"] is None:
                    await websocket.send_json({"error": "❌ Not connected. Send action=CONNECT first."})
                    continue

                directory = data.get("directory") or "."
                list_cmd = f'ls -p "{directory}" | grep "/$"'

                logger.info(f"📂 Listing directories in: {directory}")
                try:
                    # Reuse the existing connection
                    proc = await session["conn"].create_process(list_cmd)
                    stdout_data = []
                    async for line in proc.stdout:
                        stdout_data.append(line.strip())

                    await websocket.send_json({"directories": stdout_data})

                except asyncssh.Error as e:
                    logger.error(f"❌ SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})
                except Exception as e:
                    logger.exception("❌ Unexpected error during LIST_FILES")
                    await websocket.send_json({"error": f"Server Error: {str(e)}"})

            # --------------------------------------------------------
            # ELSE - Unrecognized action
            # --------------------------------------------------------
            else:
                logger.warning(f"⚠️ Unrecognized action: {action}")
                await websocket.send_json({"error": f"❌ Unknown action '{action}'."})

    except asyncio.IncompleteReadError:
        logger.warning("⚠️ Process terminated unexpectedly")
    except asyncssh.Error as e:
        logger.error(f"❌ SSH Error: {str(e)}")
        await websocket.send_json({"error": f"SSH Error: {str(e)}"})
    except Exception as e:
        logger.exception("❌ Unexpected error in WebSocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})

    finally:
    # Cleanup on WebSocket disconnect
    # 1) If there's still a valid connection, terminate process & close
        if session["conn"] is not None:
            if session["process"]:
                session["process"].terminate()
        try:
            await session["conn"].close()
        except Exception as e:
            logger.debug(f"Ignored error closing SSH conn: {e}")

    # 2) Remove from active_sessions
    if session_id in active_sessions:
        del active_sessions[session_id]

    # 3) Attempt to close the websocket if still open
    try:
        await websocket.close()
    except:
        pass

    logger.info(f"🔻 WebSocket disconnected (Session: {session_id})")


# -----------------------------------------------------------------------------------
# OPTIONAL: Remove or comment out the old /ssh route to avoid confusion:
# @app.route('/ssh', methods=['POST'])
# async def ssh_command():
#     ...
# -----------------------------------------------------------------------------------


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
{"action":"CONNECT","host":"104.248.120.153","username":"root","password":"9KA-1Jr4[M0p*9b*!,)]T[XKf*4gk"}

{ "host": "104.248.120.153", "username": "root", "password": "9KA-1Jr4[M0p*9b*!,)]T[XKf*4gk", "command": "journalctl --follow -u depospot-backend" }
{"action":"RUN_COMMAND","command":"echo Hello from ws!"}
