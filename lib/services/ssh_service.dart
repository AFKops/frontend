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
          "password": password,
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
}
