import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class SSHService {
  final String apiUrl =
      "http://137.184.69.130:5000/ssh"; // HTTP for short commands
  final String wsUrl =
      "ws://137.184.69.130:5000/ssh-stream"; // WebSocket for streaming

  WebSocketChannel? _channel;
  bool _isConnected = false;

  /// ✅ **Fetch SSH Welcome Message via HTTP (Short Command)**
  Future<String> getSSHWelcomeMessage({
    required String host,
    required String username,
    required String password,
  }) async {
    try {
      print("🔵 Sending SSH API request to $apiUrl");
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password,
          "command": "uptime",
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["output"] ?? "Connected to $host";
      } else {
        return "❌ SSH API Error: ${response.body}";
      }
    } catch (e) {
      return "❌ SSH API Connection Failed: $e";
    }
  }

  /// ✅ **Execute SSH Command via HTTP (For Quick Commands)**
  Future<String> executeCommand({
    required String host,
    required String username,
    required String password,
    required String command,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password.isNotEmpty ? password : "default_placeholder",
          "command": command,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["output"] ?? "No output received";
      } else {
        return "❌ SSH API Error: ${response.body}";
      }
    } catch (e) {
      return "❌ SSH API Connection Failed: $e";
    }
  }

  /// ✅ **List Only Directories via HTTP (For cd Autocomplete)**
  Future<List<String>> listFiles({
    required String host,
    required String username,
    required String password,
    String directory = ".",
  }) async {
    try {
      print("📂 Fetching directory list from: $directory");

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password,
          "command": 'ls -p "$directory" | grep "/\$"',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String output = data["output"] ?? "";
        List<String> directories = output.trim().split("\n");

        return directories;
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// ✅ **Persistent WebSocket Connection for Continuous SSH Streaming**
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

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _isConnected = true;

    // Send authentication details first
    final authMessage = jsonEncode({
      "host": host,
      "username": username,
      "password": password,
    });

    print("📤 Sending SSH Authentication: $authMessage");
    _channel?.sink.add(authMessage);

    // Listen for real-time responses
    _channel?.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['output'] != null) {
          onMessageReceived(data['output']);
        } else if (data['error'] != null) {
          onError(data['error']);
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

  /// ✅ **Send Commands Over WebSocket (Instead of Opening New Connections)**
  void sendWebSocketCommand(String command) {
    if (_channel == null || !_isConnected) {
      print("❌ WebSocket is not connected. Please connect first.");
      return;
    }

    final commandMessage = jsonEncode({"command": command});
    print("📤 Sending SSH Command: $commandMessage");
    _channel?.sink.add(commandMessage);
  }

  /// ✅ **Close WebSocket Connection (To Stop Streaming)**
  void closeWebSocket() {
    if (_channel != null) {
      _channel?.sink.close(status.goingAway);
      print("🔻 WebSocket Closed.");
      _channel = null;
      _isConnected = false;
    }
  }
}
