import 'dart:async';
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
  Function()? onDisconnected; // NEW

  Timer? _heartbeatTimer;

  /// Connects to the WebSocket with action=CONNECT
  void connectToWebSocket({
    required String host,
    required String username,
    required String password,
    required Function(String) onMessageReceived,
    required Function(String) onError,
    Function()? onDisconnected, // NEW
  }) {
    if (_channel != null && _isConnected) {
      print("🔄 WebSocket is already connected. Reusing connection...");
      return;
    }

    print("🌐 Connecting to WebSocket: $wsUrl");
    this.onMessageReceived = onMessageReceived;
    this.onError = onError;
    this.onDisconnected = onDisconnected;

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

    _startHeartbeat();

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
        _handleDisconnect();
        onError('WebSocket error: $error');
      },
      onDone: () {
        print("🔻 WebSocket connection closed.");
        _handleDisconnect();
        onError('WebSocket connection closed');
      },
    );
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;
    _stopHeartbeat();

    if (onDisconnected != null) {
      onDisconnected!(); // This will notify the ChatProvider
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({"action": "PING"}));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void sendWebSocketCommand(String command) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "RUN_COMMAND", "command": command};
    print("📤 Sending RUN_COMMAND: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  void listFiles(String directory) {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "LIST_FILES", "directory": directory};
    print("📤 Sending LIST_FILES: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  void stopCurrentProcess() {
    if (_channel == null || !_isConnected) {
      print("❌ Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "STOP"};
    print("📤 Sending STOP action");
    _channel?.sink.add(jsonEncode(msg));
  }

  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("🔻 WebSocket Closed.");
      _channel = null;
      _isConnected = false;
      _stopHeartbeat();
    }
  }

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
