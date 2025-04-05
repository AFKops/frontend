import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Manages a single persistent WebSocket connection to the Python /ssh-stream
class SSHService {
  final String wsUrl = "ws://137.184.69.130:5000/ssh-stream";
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? onMessageReceived;
  Function(String)? onError;

  /// Connects to the WebSocket with action=CONNECT
  void connectToWebSocket({
    required String host,
    required String username,
    required String password,
    required Function(String) onMessageReceived,
    required Function(String) onError,
  }) {
    if (_channel != null && _isConnected) {
      print("🔄 WebSocket is already connected. Reusing connection...");
      return;
    }
    print("🌐 Connecting to WebSocket: $wsUrl");
    this.onMessageReceived = onMessageReceived;
    this.onError = onError;
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _isConnected = true;

    final connectMsg = {
      "action": "CONNECT",
      "host": host,
      "username": username,
      "password": password,
    };
    print("📤 Sending CONNECT: $connectMsg");
    _channel?.sink.add(jsonEncode(connectMsg));

    _channel?.stream.listen(
      (rawMessage) {
        final data = jsonDecode(rawMessage);
        if (data['output'] != null) {
          onMessageReceived(data['output'].toString());
        } else if (data['error'] != null) {
          onError(data['error'].toString());
        } else if (data['info'] != null) {
          onMessageReceived(data['info'].toString());
        } else if (data['directories'] != null) {
          final dirs = data['directories'] as List;
          onMessageReceived(jsonEncode({"directories": dirs}));
        }
      },
      onError: (error) {
        print("⚠️ WebSocket Error: $error");
        _isConnected = false;
        onError('WebSocket error: $error');
      },
      onDone: () {
        print("🔻 WebSocket connection closed.");
        _isConnected = false;
        onError('WebSocket connection closed');
      },
    );
  }

  /// Sends a normal RUN_COMMAND
  void sendWebSocketCommand(String command) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "RUN_COMMAND", "command": command};
    print("📤 Sending RUN_COMMAND: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Requests a directory listing via LIST_FILES
  void listFiles(String directory) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "LIST_FILES", "directory": directory};
    print("📤 Sending LIST_FILES: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Stops any currently running process without closing the SSH session
  void stopCurrentProcess() {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "STOP"};
    print("📤 Sending STOP action");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Closes the SSH WebSocket entirely
  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("🔻 WebSocket Closed.");
      _channel = null;
      _isConnected = false;
    }
  }

  /// Sends Ctrl+C (SIGINT) to the remote process
  void sendCtrlC() {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }

    final msg = {"action": "CTRL_C"};
    print("📤 Sending CTRL_C");
    _channel?.sink.add(jsonEncode(msg));
  }
}
