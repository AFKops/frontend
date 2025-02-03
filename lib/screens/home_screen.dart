import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _messageController = TextEditingController();

  /// ✅ Open SSH Connection Dialog with username, host, and password
  void _connectToServer(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    TextEditingController sshCommandController = TextEditingController();
    String? password;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Connect to SSH Server"),
        content: TextField(
          controller: sshCommandController,
          decoration: const InputDecoration(
            labelText: "SSH Command (e.g., ssh root@192.168.1.1)",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              String sshCommand = sshCommandController.text.trim();

              if (!sshCommand.startsWith("ssh ")) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid SSH command format.")),
                );
                return;
              }

              // ✅ Extract username and host
              sshCommand = sshCommand.replaceFirst("ssh ", "").trim();
              List<String> parts = sshCommand.split("@");

              if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("Invalid SSH format. Use: ssh user@host")),
                );
                return;
              }

              String username = parts[0].trim();
              String host = parts[1].trim();

              // ✅ Ask for Password
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Enter SSH Password"),
                  content: TextField(
                    onChanged: (value) => password = value,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password"),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                  ],
                ),
              );

              // ✅ Start new SSH Chat and ensure navigation to the correct chat
              String chatId = await chatProvider.startNewChat(
                chatName: "SSH: $username@$host",
                host: host,
                username: username,
                password: password ?? "",
              );

              if (chatId.isNotEmpty) {
                chatProvider.setCurrentChat(chatId); // ✅ Set the current chat
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(chatId: chatId),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text("❌ Failed to connect to SSH server.")),
                );
              }
            },
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            );
          },
        ),
        title: const Text("ChatOps"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const Spacer(),
          const Center(
            child: Column(
              children: [
                Text(
                  "What can I help with?",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _connectToServer(context),
            child: const Text("Connect to a Server"),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
