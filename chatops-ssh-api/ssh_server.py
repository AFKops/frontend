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

@app.websocket('/ssh-stream')
async def ssh_stream():
    logger = logging.getLogger('websocket')
    active_process = None  # ✅ Store process reference to stop it later

    try:
        await websocket.accept()
        logger.info("WebSocket connection established")

        while True:
            data = await websocket.receive_json()
            logger.debug(f"Received JSON data: {json.dumps(data, indent=2)}")

            host = data.get("host")
            username = data.get("username")
            command = data.get("command")

            if command == "STOP":  # ✅ Handle Stop Signal
                if active_process:
                    logger.info("Stopping streaming process...")
                    active_process.terminate()
                    active_process = None  # Reset process reference
                await websocket.send_json({"output": "❌ Streaming stopped."})
                continue  # Wait for more messages

            if not all([host, username, data.get("password"), command]):
                await websocket.send_json({"error": "Missing parameters"})
                return

            safe_command = f"stdbuf -oL {command}"
            logger.debug(f"Sanitized command: {safe_command}")

            async with asyncssh.connect(
                host=host, 
                username=username, 
                password=data.get("password"), 
                known_hosts=None
            ) as conn:
                logger.info(f"SSH connection established to {host}")

                async with conn.create_process(safe_command, term_type="xterm") as process:
                    active_process = process  # ✅ Store process reference

                    async def read_stdout():
                        while not process.stdout.at_eof():
                            line = await process.stdout.readline()
                            if line:
                                await websocket.send_json({"output": line.strip()})
                            else:
                                break

                    async def read_stderr():
                        while not process.stderr.at_eof():
                            error_line = await process.stderr.readline()
                            if error_line:
                                await websocket.send_json({"error": error_line.strip()})
                            else:
                                break

                    await asyncio.gather(read_stdout(), read_stderr())

    except asyncio.IncompleteReadError:
        logger.debug("Process terminated with incomplete read")
    except asyncssh.Error as e:
        logger.error(f"SSH Connection Failed: {str(e)}")
        await websocket.send_json({"error": f"SSH Error: {str(e)}"})
    except Exception as e:
        logger.exception("Unexpected error in WebSocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
        if active_process:
            active_process.terminate()  # ✅ Ensure cleanup
        await websocket.close(code=1000, reason="Command execution completed")
        logger.info("WebSocket connection closed")



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