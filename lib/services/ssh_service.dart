import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// Manages a single persistent WebSocket connection to your Python /ssh-stream.
/// All commands (CONNECT, RUN_COMMAND, LIST_FILES, STOP) go through this.
class SSHService {
  final String wsUrl = "ws://137.184.69.130:5000/ssh-stream";

  WebSocketChannel? _channel;
  bool _isConnected = false;

  /// We store callbacks so the caller can receive line-by-line output or errors.
  Function(String)? onMessageReceived;
  Function(String)? onError;

  /// Connect to the WebSocket with action=CONNECT.
  /// If already connected, we reuse the connection.
  void connectToWebSocket({
    required String host,
    required String username,
    required String password,
    required Function(String) onMessageReceived,
    required Function(String) onError,
  }) {
    // If we already have a channel & are connected, do nothing
    if (_channel != null && _isConnected) {
      print("🔄 WebSocket is already connected. Reusing connection...");
      return;
    }

    print("🌐 Connecting to WebSocket: $wsUrl");
    this.onMessageReceived = onMessageReceived;
    this.onError = onError;

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _isConnected = true;

    // 1) Send the CONNECT action
    final connectMsg = {
      "action": "CONNECT",
      "host": host,
      "username": username,
      "password": password,
    };
    print("📤 Sending CONNECT action: $connectMsg");
    _channel?.sink.add(jsonEncode(connectMsg));

    // 2) Listen for server messages
    _channel?.stream.listen(
      (rawMessage) {
        final data = jsonDecode(rawMessage);

        // Output lines from commands
        if (data['output'] != null) {
          onMessageReceived(data['output'].toString());
        }
        // SSH/Server error
        else if (data['error'] != null) {
          onError(data['error'].toString());
        }
        // Info messages
        else if (data['info'] != null) {
          onMessageReceived(data['info'].toString());
        }
        // Directory listing
        else if (data['directories'] != null) {
          // We can pass them back as JSON or parse them further
          final dirs = data['directories'] as List;
          // For convenience, send them as a JSON string.
          // ChatProvider can parse if needed.
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

  /// Send a normal command (RUN_COMMAND).
  /// The server will respond with line-by-line output in onMessageReceived.
  void sendWebSocketCommand(String command) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {
      "action": "RUN_COMMAND",
      "command": command,
    };
    print("📤 Sending RUN_COMMAND: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Request a directory listing from the server (LIST_FILES).
  /// The server responds with {"directories": [...]} in onMessageReceived.
  void listFiles(String directory) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {
      "action": "LIST_FILES",
      "directory": directory,
    };
    print("📤 Sending LIST_FILES: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Stop any currently running/streaming process without closing the SSH session.
  void stopCurrentProcess() {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "STOP"};
    print("📤 Sending STOP action");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Close the SSH WebSocket entirely.
  /// Next time you want to run a command, call connectToWebSocket() again.
  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("🔻 WebSocket Closed.");
      _channel = null;
      _isConnected = false;
    }
  }
}
