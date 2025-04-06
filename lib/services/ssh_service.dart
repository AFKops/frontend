import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../utils/encryption_service.dart';

class SSHService {
  final String wsUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  Function(String)? onMessageReceived;
  Function(String)? onError;
  Function()? onDisconnected;

  SSHService({required this.wsUrl});

  Timer? _heartbeatTimer;

  Future<void> connectToWebSocket({
    required String host,
    required String username,
    String password = "",
    String privateKey = "",
    String mode = "PASSWORD", // PASSWORD, KEY, ADVANCED
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

    String finalHost = host;
    String finalUsername = username;
    String finalPrivateKey = privateKey;

    // ADVANCED mode auto-parsing
    if (mode == "ADVANCED") {
      try {
        final parts = host.split(RegExp(r'\s+'));
        if (parts.length < 4) {
          onError("Invalid SSH command format. Use: ssh -i key.pem user@host");
          return;
        }

        final keyPath = parts[2];
        final userAtHost = parts[3];

        finalUsername = userAtHost.split('@')[0];
        finalHost = userAtHost.split('@')[1];
        finalPrivateKey = keyPath;

        print("🔍 ADVANCED parsed host: $finalHost");
        print("🔍 ADVANCED parsed username: $finalUsername");
        print("🔍 ADVANCED parsed key path: $finalPrivateKey");
      } catch (e) {
        onError("Failed to parse SSH command: $e");
        return;
      }
    }

    final encryptedHost =
        await EncryptionService.encryptAESCBC(finalHost, encryptionKey);
    final encryptedUser =
        await EncryptionService.encryptAESCBC(finalUsername, encryptionKey);

    String? encryptedPassword;
    String? encryptedKey;

    if (mode == "PASSWORD") {
      encryptedPassword =
          await EncryptionService.encryptAESCBC(password, encryptionKey);
    } else if (mode == "KEY" || mode == "ADVANCED") {
      try {
        String pemContent;

        if (finalPrivateKey.contains("PRIVATE KEY")) {
          // This is likely a pasted PEM string
          pemContent = finalPrivateKey;
          print("📋 Detected pasted PEM key");
        } else {
          // This is a path to a key file
          pemContent = await File(finalPrivateKey).readAsString();
          print("📁 Loaded PEM key from file path: $finalPrivateKey");
        }

        final privateKeyBase64 = base64Encode(utf8.encode(pemContent));
        encryptedKey = await EncryptionService.encryptAESCBC(
            privateKeyBase64, encryptionKey);
        print("🧪 Encrypted PEM key (base64+AES-CBC):\n$encryptedKey");
      } catch (e) {
        onError("Failed to handle private key: $e");
        return;
      }
    }

    final connectMsg = {
      "action": "CONNECT",
      "mode": mode == "ADVANCED" ? "KEY" : mode, // treat ADVANCED as KEY
      "host": encryptedHost,
      "username": encryptedUser,
    };

    if (mode == "PASSWORD") {
      connectMsg["password"] = encryptedPassword!;
    } else {
      connectMsg["key"] = encryptedKey!;
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
          print("Error parsing WebSocket message: $e");
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
    onDisconnected?.call();
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
