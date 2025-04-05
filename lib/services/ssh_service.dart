import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/encryption_service.dart';

/// Manages a single persistent WebSocket connection to the Python /ssh-stream
class SSHService {
  final String wsUrl = "ws://afkops.com/ssh-stream";
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? onMessageReceived;
  Function(String)? onError;
  Function()? onDisconnected;

  Timer? _heartbeatTimer;

  /// Connects to the WebSocket with action=CONNECT
  void connectToWebSocket({
    required String host,
    required String username,
    required String password,
    required Function(String) onMessageReceived,
    required Function(String) onError,
    Function()? onDisconnected,
  }) async {
    if (_channel != null && _isConnected) {
      print("WebSocket is already connected. Reusing connection...");
      return;
    }

    print("Connecting to WebSocket: $wsUrl");
    this.onMessageReceived = onMessageReceived;
    this.onError = onError;
    this.onDisconnected = onDisconnected;

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _isConnected = true;

    final encryptionKey = await EncryptionService.getEncryptionKey();
    if (encryptionKey == null) {
      onError("Failed to fetch encryption key");
      return;
    }

    final encryptedHost = encryptFernet(host, encryptionKey);
    final encryptedUsername = encryptFernet(username, encryptionKey);
    final encryptedPassword = encryptFernet(password, encryptionKey);

    final connectMsg = {
      "action": "CONNECT",
      "host": encryptedHost,
      "username": encryptedUsername,
      "password": encryptedPassword,
    };

    print("Sending encrypted CONNECT action");
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
        print("WebSocket Error: $error");
        _handleDisconnect();
        onError('WebSocket error: $error');
      },
      onDone: () {
        print("WebSocket connection closed.");
        _handleDisconnect();
        onError('WebSocket connection closed');
      },
    );
  }

  /// Handles a WebSocket disconnection
  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;
    _stopHeartbeat();
    if (onDisconnected != null) {
      onDisconnected!();
    }
  }

  /// Sends periodic heartbeat messages
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({"action": "PING"}));
      }
    });
  }

  /// Stops sending heartbeat messages
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Sends a command to the remote shell
  void sendWebSocketCommand(String command) {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "RUN_COMMAND", "command": command};
    print("Sending RUN_COMMAND: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Lists files in a given directory
  void listFiles(String directory) {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "LIST_FILES", "directory": directory};
    print("Sending LIST_FILES: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Stops the current remote process
  void stopCurrentProcess() {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "STOP"};
    print("Sending STOP action");
    _channel?.sink.add(jsonEncode(msg));
  }

  /// Closes the WebSocket connection
  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("WebSocket Closed.");
      _channel = null;
      _isConnected = false;
      _stopHeartbeat();
    }
  }

  /// Sends a Ctrl+C signal
  void sendCtrlC() {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "CTRL_C"};
    print("Sending CTRL_C");
    _channel?.sink.add(jsonEncode(msg));
  }
}
