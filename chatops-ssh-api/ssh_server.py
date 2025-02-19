from quart import Quart, websocket, request, jsonify
import asyncssh
import logging
import asyncio
import json

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)

app = Quart(__name__)

# Store WebSocket connections and their corresponding SSH connections
active_connections = {}

active_sessions = {}  # Format: {session_id: {"conn": asyncssh.Connection, "process": asyncssh.Process}}

@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    session_id = None  # Unique ID for this WebSocket session

    try:
        await websocket.accept()
        logger.info("WebSocket connection established")

        while True:
            data = await websocket.receive_json()
            logger.debug(f"Received data: {json.dumps(data, indent=2)}")

            # Phase 1: Authentication
            if not session_id:
                if "host" not in data or "username" not in data or "password" not in data:
                    await websocket.send_json({"error": "Auth required first"})
                    continue

                # Create new SSH connection
                session_id = str(uuid.uuid4())
                conn = await asyncssh.connect(
                    host=data["host"],
                    username=data["username"],
                    password=data["password"],
                    known_hosts=None
                )
                active_sessions[session_id] = {"conn": conn}
                await websocket.send_json({"status": "AUTH_SUCCESS", "session_id": session_id})
                logger.info(f"New session: {session_id}")
                continue

            # Phase 2: Command Execution (reuse existing connection)
            session = active_sessions.get(session_id)
            if not session:
                await websocket.send_json({"error": "Invalid session"})
                return

            command = data.get("command")
            if command == "STOP":
                if "process" in session:
                    session["process"].terminate()
                    del session["process"]
                await websocket.send_json({"output": "Process stopped"})
                continue

            # Execute command on existing connection
            safe_command = f"stdbuf -oL {command}"
            process = await session["conn"].create_process(safe_command, term_type="xterm")
            session["process"] = process  # Track active process

            async def read_stream(stream, is_error=False):
                while not stream.at_eof():
                    line = await stream.readline()
                    if line:
                        await websocket.send_json({"output": line.strip(), "error": is_error})

            await asyncio.gather(
                read_stream(process.stdout),
                read_stream(process.stderr, is_error=True)
            )

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        await websocket.send_json({"error": str(e)})
    finally:
        # Cleanup on disconnect
        if session_id and session_id in active_sessions:
            session = active_sessions[session_id]
            if "process" in session:
                session["process"].terminate()
            await session["conn"].close()
            del active_sessions[session_id]
        await websocket.close()

@app.route('/ssh', methods=['POST'])
async def ssh_command():
    logger = logging.getLogger('http')
    try:
        data = await request.get_json()
        logger.debug(f"Received POST data: {json.dumps(data, indent=2)}")
        
        host = data.get("host")
        username = data.get("username")
        command = data.get("command")
        
        logger.info(f"HTTP SSH request to {username}@{host} for command: {command}")

        if not all([host, username, data.get("password"), command]):
            logger.error("Missing parameters in POST request")
            return jsonify({"error": "Missing required parameters"}), 400

        async with asyncssh.connect(
            host=host, 
            username=username, 
            password=data.get("password"), 
            known_hosts=None
        ) as conn:
            logger.info(f"SSH connection established to {host}")
            
            result = await conn.run(command, check=True)
            logger.debug(f"Command executed successfully\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}")
            
            output = result.stdout.strip() if result.stdout else result.stderr.strip()
            return jsonify({"output": output})

    except asyncssh.Error as e:
        logger.error(f"SSH Operation Failed: {str(e)}")
        return jsonify({"error": f"SSH Error: {str(e)}"}), 500
    except Exception as e:
        logger.exception("Unexpected error in HTTP handler:")
        return jsonify({"error": f"Server Error: {str(e)}"}), 500


if __name__ == "__main__":
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["0.0.0.0:5000"]
    
    # Configure Hypercorn logging
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