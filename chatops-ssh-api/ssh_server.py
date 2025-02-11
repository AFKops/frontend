from quart import Quart, websocket
import asyncssh
import logging
import asyncio
import json

# Enable Debug Logging
logging.basicConfig(level=logging.DEBUG)

app = Quart(__name__)

@app.websocket('/ssh-stream')
async def ssh_stream():
    try:
        # Accept WebSocket Connection
        await websocket.accept()
        data = await websocket.receive_json()
        logging.info(f"Received data: {data}")

        # Extract SSH Credentials & Command
        host = data.get("host")
        username = data.get("username")
        password = data.get("password")
        command = data.get("command")

        if not all([host, username, password, command]):
            await websocket.send_json({"error": "Missing parameters"})
            return

        # Establish SSH Connection
        async with asyncssh.connect(
            host=host, username=username, password=password, known_hosts=None
        ) as conn:

            # Open a new SSH Process
            async with conn.create_process(command) as process:
                logging.info(f"Process started for command: {command}")

                # Stream Output to WebSocket
                while not process.stdout.at_eof():
                    output = await process.stdout.read(4096)
                    if output:
                        await websocket.send_json({"output": output})  # No need to decode

                # Stream Errors (if any)
                while not process.stderr.at_eof():
                    error = await process.stderr.read(4096)
                    if error:
                        await websocket.send_json({"error": error})  # No need to decode

    except asyncssh.Error as e:
        logging.error(f"SSH Error: {str(e)}")
        await websocket.send_json({"error": f"SSH Error: {str(e)}"})
    except Exception as e:
        logging.error(f"Unexpected error: {str(e)}")
        await websocket.send_json({"error": f"Server Error: {str(e)}"})
    finally:
        await websocket.close(code=1000, reason="Command execution completed")
        logging.info("WebSocket connection closed")


if __name__ == "__main__":
    from hypercorn.asyncio import serve
    from hypercorn.config import Config

    config = Config()
    config.bind = ["0.0.0.0:5000"]
    asyncio.run(serve(app, config))
