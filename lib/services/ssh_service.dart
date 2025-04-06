import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/encryption_service.dart';
import 'dart:io';

class SSHService {
  final String wsUrl = "ws://afkops.com/ssh-stream";
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? onMessageReceived;
  Function(String)? onError;
  Function()? onDisconnected;

  Timer? _heartbeatTimer;

  Future<void> connectToWebSocket({
    required String host,
    required String username,
    String password = "",
    String privateKey = "",
    String mode = "PASSWORD", // "PASSWORD" or "KEY"
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

    final encryptedHost =
        await EncryptionService.encryptAESCBC(host, encryptionKey);
    final encryptedUser =
        await EncryptionService.encryptAESCBC(username, encryptionKey);

    String? encryptedPassword;
    String? encryptedKey;

    if (mode == "PASSWORD") {
      encryptedPassword =
          await EncryptionService.encryptAESCBC(password, encryptionKey);
    } else if (mode == "KEY") {
      final pemContent = await File(privateKey).readAsString(); // read the file
      final privateKeyBase64 = base64Encode(utf8.encode(pemContent));

      print("🔐 Original PEM key:\n$pemContent");
      print("📦 Base64-encoded PEM:\n$privateKeyBase64");

      encryptedKey = await EncryptionService.encryptAESCBC(
          privateKeyBase64, encryptionKey);

      print("🧪 Encrypted PEM key (base64+AES-CBC):\n$encryptedKey");
    } else {
      onError("Unknown mode: $mode");
      return;
    }

    final connectMsg = {
      "action": "CONNECT",
      "mode": mode,
      "host": encryptedHost,
      "username": encryptedUser,
    };

    if (mode == "PASSWORD") {
      if (encryptedPassword == null) {
        onError("Encryption failed for password");
        return;
      }
      connectMsg["password"] = encryptedPassword;
    } else {
      if (encryptedKey == null) {
        onError("Encryption failed for private key");
        return;
      }
      connectMsg["key"] = encryptedKey;
    }

    print("Sending CONNECT action (mode=$mode)");
    _channel?.sink.add(jsonEncode(connectMsg));

    _startHeartbeat();

    _channel?.stream.listen(
      (rawMessage) {
        try {
          final data = jsonDecode(rawMessage);
          if (data['output'] != null) {
            onMessageReceived?.call(data['output'].toString());
          } else if (data['error'] != null) {
            onError?.call(data['error'].toString());
          } else if (data['info'] != null) {
            onMessageReceived?.call(data['info'].toString());
          } else if (data['directories'] != null) {
            final dirs = data['directories'] as List;
            onMessageReceived?.call(jsonEncode({"directories": dirs}));
          }
        } catch (e) {
          print("Error parsing or handling WebSocket message: $e");
        }
      },
      onError: (error) {
        print("WebSocket Error: $error");
        _handleDisconnect();
        try {
          onError?.call('WebSocket error: $error');
        } catch (_) {}
      },
      onDone: () {
        print("WebSocket connection closed.");
        _handleDisconnect();
        try {
          onError?.call('WebSocket connection closed');
        } catch (_) {}
      },
    );
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;
    _stopHeartbeat();
    if (onDisconnected != null) {
      onDisconnected!();
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
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "RUN_COMMAND", "command": command};
    print("Sending RUN_COMMAND: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  void listFiles(String directory) {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "LIST_FILES", "directory": directory};
    print("Sending LIST_FILES: $msg");
    _channel?.sink.add(jsonEncode(msg));
  }

  void stopCurrentProcess() {
    if (_channel == null || !_isConnected) {
      print("Not connected. Please connect first.");
      return;
    }
    final msg = {"action": "STOP"};
    print("Sending STOP action");
    _channel?.sink.add(jsonEncode(msg));
  }

  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("WebSocket Closed.");
      _channel = null;
      _isConnected = false;
      _stopHeartbeat();
    }
  }

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
