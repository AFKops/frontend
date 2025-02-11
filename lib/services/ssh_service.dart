import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class SSHService {
  final String apiUrl =
      "http://137.184.69.130:5000/ssh"; // HTTP for short commands
  final String wsUrl =
      "ws://137.184.69.130:5000/ssh-stream"; // WebSocket for streaming

  WebSocketChannel? _channel;

  /// ✅ **Fetch SSH Welcome Message via HTTP (Short Command)**
  Future<String> getSSHWelcomeMessage({
    required String host,
    required String username,
    required String password,
  }) async {
    try {
      print("🔵 Sending SSH API request to $apiUrl");
      print("🟡 Request Data: host=$host, user=$username, command=uptime");

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

      print("🟠 Response Status: ${response.statusCode}");
      print("🟢 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["output"] ?? "Connected to $host";
      } else {
        return "❌ SSH API Error: ${response.body}";
      }
    } catch (e) {
      print("🔴 Error: $e");
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

        print("📂 Found directories: $directories");

        return directories;
      } else {
        print("❌ SSH API Error: ${response.body}");
        return [];
      }
    } catch (e) {
      print("🔴 Error fetching directories: $e");
      return [];
    }
  }

  /// ✅ **Connect to WebSocket for Continuous Command Streaming**
  void connectToWebSocket({
    required String host,
    required String username,
    required String password,
    required String command,
    required Function(String) onMessageReceived,
    required Function(String) onError,
  }) {
    print("🌐 Connecting to WebSocket: $wsUrl");

    // Open WebSocket Connection
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Send SSH credentials and command
    final message = jsonEncode({
      "host": host,
      "username": username,
      "password": password,
      "command": command,
    });

    print("📤 Sending SSH Data: $message");
    _channel?.sink.add(message);

    // Listen for real-time responses
    _channel?.stream.listen(
      (message) {
        final data = jsonDecode(message);
        if (data['output'] != null) {
          print("🟢 Received Output: ${data['output']}");
          onMessageReceived(data['output']);
        } else if (data['error'] != null) {
          print("🔴 Received Error: ${data['error']}");
          onError(data['error']);
        }
      },
      onError: (error) {
        print("⚠️ WebSocket Error: $error");
        onError('WebSocket error: $error');
      },
      onDone: () {
        print("🔻 WebSocket connection closed.");
        onError('WebSocket connection closed');
      },
    );
  }

  /// ✅ **Close WebSocket Connection (To Stop Streaming)**
  void closeWebSocket() {
    _channel?.sink.close();
    print("🔻 WebSocket Closed.");
  }
}
