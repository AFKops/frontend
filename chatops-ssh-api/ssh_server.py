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
    try:
        await websocket.accept()
        logger.info("WebSocket connection established")
        
        data = await websocket.receive_json()
        logger.debug(f"Received JSON data: {json.dumps(data, indent=2)}")
        
        host = data.get("host")
        username = data.get("username")
        command = data.get("command")
        
        logger.info(f"Connection request to {username}@{host} for command: {command}")

        if not all([host, username, data.get("password"), command]):
            logger.error("Missing parameters in request")
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
                logger.info(f"Process started for command: {safe_command}")  # Changed here
                
                async def read_stdout():
                    logger.debug("Starting stdout reader")
                    while True:
                        try:
                            line = await process.stdout.readline()
                            if not line:
                                break
                            clean_line = line.strip()
                            logger.debug(f"STDOUT: {clean_line}")
                            await websocket.send_json({"output": clean_line})
                        except asyncio.IncompleteReadError:
                            break

                async def read_stderr():
                    logger.debug("Starting stderr reader")
                    while True:
                        try:
                            error_line = await process.stderr.readline()
                            if not error_line:
                                break
                            clean_error = error_line.strip()
                            logger.warning(f"STDERR: {clean_error}")
                            await websocket.send_json({"error": clean_error})
                        except asyncio.IncompleteReadError:
                            break

                await asyncio.gather(read_stdout(), read_stderr())
                logger.info("Command execution completed")

    except asyncio.IncompleteReadError:
        logger.debug("Process terminated with incomplete read")
    except asyncssh.Error as e:
        logger.error(f"SSH Connection Failed: {str(e)}")
        await websocket.send_json({"error": f"SSH Error: {str(e)}"})
    except Exception as e:
        logger.exception("Unexpected error in WebSocket handler:")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
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