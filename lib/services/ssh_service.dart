import 'dart:convert';
import 'package:http/http.dart' as http;

class SSHService {
  final String apiUrl =
      "http://64.227.5.203:5000/ssh"; // Replace with actual API URL

  /// ✅ **Fetch SSH Welcome Message from API**
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

  /// ✅ **Execute SSH Command**
  Future<String> executeCommand({
    required String host,
    required String username,
    required String password, // ✅ Ensure password is always sent
    required String command,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password.isNotEmpty
              ? password
              : "default_placeholder", // ✅ Always send a password
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

  /// ✅ **NEW: List Files in a Directory**
  Future<List<String>> listFiles({
    required String host,
    required String username,
    required String password,
    String directory = ".",
  }) async {
    try {
      print("📂 Fetching file list from directory: $directory");
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password,
          "command": "ls -p $directory", // ✅ "-p" appends "/" to directories
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String output = data["output"] ?? "";
        List<String> files = output.trim().split("\n");

        print("📂 Found files: $files");
        return files;
      } else {
        print("❌ SSH API Error: ${response.body}");
        return [];
      }
    } catch (e) {
      print("🔴 Error fetching files: $e");
      return [];
    }
  }
}
