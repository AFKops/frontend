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

# We'll store for each session:
# {
#   "conn": <asyncssh connection>,
#   "proc": <interactive bash process>,
#   "read_task": <task reading from that bash>
# }
active_sessions = {}

@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = str(uuid.uuid4())
    session = {"conn": None, "proc": None, "read_task": None}
    active_sessions[session_id] = session

    try:
        await websocket.accept()
        logger.info(f"[{session_id}] WebSocket connected.")

        # Background task to read from the bash process
        async def read_bash(proc):
            try:
                while not proc.stdout.at_eof():
                    line = await proc.stdout.readline()
                    if line:
                        # send each line to the client
                        await websocket.send_json({"output": line.rstrip("\n")})
            except asyncio.CancelledError:
                logger.info(f"[{session_id}] read_bash cancelled.")
            except Exception as e:
                logger.exception(f"[{session_id}] Error reading bash output:")
                await websocket.send_json({"error": f"Bash read error: {str(e)}"})

        while True:
            data = await websocket.receive_json()
            logger.debug(f"[{session_id}] Received data: {json.dumps(data, indent=2)}")

            action = data.get("action", "").upper().strip()
            if not action:
                await websocket.send_json({"error": "No 'action' specified."})
                continue

            # --------------------------------------------------------
            # CONNECT
            # --------------------------------------------------------
            if action == "CONNECT":
                host = data.get("host")
                username = data.get("username")
                password = data.get("password")
                if not all([host, username, password]):
                    await websocket.send_json({"error": "Missing host/username/password"})
                    continue

                if session["conn"] is not None:
                    await websocket.send_json({"info": "Already connected, reusing session"})
                    continue

                # Connect once
                try:
                    logger.info(f"[{session_id}] Connecting to {host} as {username}...")
                    conn = await asyncssh.connect(
                        host=host,
                        username=username,
                        password=password,
                        known_hosts=None
                    )
                    session["conn"] = conn

                    # Start interactive Bash
                    # try removing '-i' or using '/bin/bash' if no output
                    logger.info(f"[{session_id}] Starting interactive bash -i ...")
                    proc = await conn.create_process("bash -i")  
                    session["proc"] = proc

                    # Start reading output in background
                    read_task = asyncio.create_task(read_bash(proc))
                    session["read_task"] = read_task

                    await websocket.send_json({"info": "Interactive Bash session started."})
                    logger.info(f"[{session_id}] Connected + interactive Bash ready.")

                except asyncssh.Error as e:
                    logger.error(f"[{session_id}] SSH Error: {str(e)}")
                    await websocket.send_json({"error": f"SSH Error: {str(e)}"})

            # --------------------------------------------------------
            # RUN_COMMAND
            # --------------------------------------------------------
            elif action == "RUN_COMMAND":
                if session["conn"] is None or session["proc"] is None:
                    await websocket.send_json({"error": "Not connected. Send action=CONNECT first."})
                    continue

                cmd = data.get("command", "")
                if not cmd:
                    await websocket.send_json({"error": "Missing 'command' parameter"})
                    continue

                logger.info(f"[{session_id}] RUN_COMMAND: {cmd}")

                try:
                    # Write the command + newline to the bash shell
                    session["proc"].stdin.write(cmd + "\n")
                except Exception as e:
                    logger.exception(f"[{session_id}] Error writing command:")
                    await websocket.send_json({"error": f"Write error: {str(e)}"})

            # --------------------------------------------------------
            # STOP
            # --------------------------------------------------------
            elif action == "STOP":
                # We can send Ctrl-C if we want to kill the currently running process
                proc = session.get("proc")
                if proc:
                    logger.info(f"[{session_id}] Sending Ctrl-C to bash.")
                    proc.stdin.write("\x03")  # ctrl-c
                    await websocket.send_json({"output": "Sent Ctrl-C."})
                else:
                    await websocket.send_json({"info": "No interactive shell to stop."})

            # --------------------------------------------------------
            # LIST_FILES
            # (Ephemeral or we could just do "ls -p 'dir' | grep '/$'" inside the shell)
            # --------------------------------------------------------
            elif action == "LIST_FILES":
                if session["conn"] is None:
                    await websocket.send_json({"error": "Not connected. Send action=CONNECT first."})
                    continue

                directory = data.get("directory") or "."
                list_cmd = f'ls -p "{directory}" | grep "/$"'
                logger.info(f"[{session_id}] Listing directories: {directory}")
                try:
                    ephemeral = await session["conn"].create_process(list_cmd)
                    results = []
                    async for line in ephemeral.stdout:
                        results.append(line.strip())
                    await websocket.send_json({"directories": results})
                except Exception as e:
                    logger.exception(f"[{session_id}] Error listing files:")
                    await websocket.send_json({"error": f"List files error: {str(e)}"})

            else:
                logger.warning(f"[{session_id}] Unknown action: {action}")
                await websocket.send_json({"error": f"Unknown action: {action}"})

    except asyncio.IncompleteReadError:
        logger.warning(f"[{session_id}] IncompleteReadError.")
    except asyncssh.Error as e:
        logger.error(f"[{session_id}] SSH error: {str(e)}")
        await websocket.send_json({"error": f"SSH error: {str(e)}"})
    except Exception as e:
        logger.exception(f"[{session_id}] Unexpected error in websocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
        # On disconnect, try to exit the shell and close the connection
        proc = session.get("proc")
        if proc:
            logger.info(f"[{session_id}] Exiting interactive bash.")
            try:
                proc.stdin.write("exit\n")
                await asyncio.sleep(0.1)
                proc.stdin.write("\x04")  # ctrl-D
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

