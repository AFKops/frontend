import 'dart:convert';
import 'package:http/http.dart' as http;

class SSHService {
  final String apiUrl =
<<<<<<< HEAD
      "http://192.168.3.11:5000/ssh"; // Replace with actual API URL
=======
      "http://64.227.5.203:5000/ssh"; // Replace with actual API URL
>>>>>>> ac09413 (Normalize line endings)

  /// ✅ **Fetch SSH Welcome Message from API**
  Future<String> getSSHWelcomeMessage({
    required String host,
    required String username,
    required String password,
  }) async {
    try {
<<<<<<< HEAD
=======
      print("🔵 Sending SSH API request to $apiUrl");
      print("🟡 Request Data: host=$host, user=$username, command=uptime");

>>>>>>> ac09413 (Normalize line endings)
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "username": username,
          "password": password,
<<<<<<< HEAD
          "command":
              "uptime", // ✅ Sends a harmless command to get welcome message
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["output"] ?? "Connected to $host"; // ✅ Default message
=======
          "command": "uptime",
        }),
      );

      print("🟠 Response Status: ${response.statusCode}");
      print("🟢 Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data["output"] ?? "Connected to $host";
>>>>>>> ac09413 (Normalize line endings)
      } else {
        return "❌ SSH API Error: ${response.body}";
      }
    } catch (e) {
<<<<<<< HEAD
=======
      print("🔴 Error: $e");
>>>>>>> ac09413 (Normalize line endings)
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
