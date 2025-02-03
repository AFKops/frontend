from flask import Flask, request, jsonify
import paramiko

app = Flask(__name__)

def execute_ssh_command(host, username, password, command):
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        # Connect to SSH server
        client.connect(hostname=host, username=username, password=password)

        # Execute the command
        stdin, stdout, stderr = client.exec_command(command)
        output = stdout.read().decode()
        error = stderr.read().decode()

        client.close()

        return output if output else error

    except Exception as e:
        return str(e)

@app.route('/ssh', methods=['POST'])
def ssh_api():
    data = request.json
    host = data.get("host")
    username = data.get("username")
    password = data.get("password")
    command = data.get("command")

    if not all([host, username, password, command]):
        return jsonify({"error": "Missing required parameters"}), 400

    result = execute_ssh_command(host, username, password, command)
    return jsonify({"output": result})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
