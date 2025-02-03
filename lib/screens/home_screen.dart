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
  final TextEditingController _sshCommandController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _chatMessageController = TextEditingController();
  bool _obscurePassword = true;
  bool _isConnecting = false;

  /// ✅ **Connect to SSH and retry once if it fails**
  void _connectToServer(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    String sshCommand = _sshCommandController.text.trim();
    String password = _passwordController.text.trim();

    if (sshCommand.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Please fill all fields.")),
      );
      return;
    }

    if (!sshCommand.startsWith("ssh ")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Invalid SSH command format.")),
      );
      return;
    }

    // ✅ Extract username and host from SSH command
    sshCommand = sshCommand.replaceFirst("ssh ", "").trim();
    List<String> parts = sshCommand.split("@");

    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Invalid SSH format. Use: ssh user@host")),
      );
      return;
    }

    String username = parts[0].trim();
    String host = parts[1].trim();

    setState(() => _isConnecting = true); // ✅ Show loading indicator

    String chatId =
        await _attemptConnection(chatProvider, host, username, password);

    setState(() => _isConnecting = false); // ✅ Hide loading indicator

    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Failed to connect to SSH server.")),
      );
    }
  }

  /// ✅ **Attempts SSH Connection & Only Retries If It Fails**
  Future<String> _attemptConnection(ChatProvider chatProvider, String host,
      String username, String password) async {
    String chatId = await chatProvider.startNewChat(
      chatName: "SSH: $username@$host",
      host: host,
      username: username,
      password: password,
    );

    // ✅ **Only Retry If Chat Is Not Active**
    if (chatId.isEmpty || !chatProvider.isChatActive(chatId)) {
      await Future.delayed(
          const Duration(seconds: 1)); // ✅ Short delay before retrying
      String retryChatId = await chatProvider.startNewChat(
        chatName: "SSH: $username@$host",
        host: host,
        username: username,
        password: password,
      );

      // ✅ **Only return retryChatId if it actually succeeded**
      return chatProvider.isChatActive(retryChatId) ? retryChatId : chatId;
    }

    return chatId; // ✅ First attempt worked, no retry needed
  }

  /// ✅ **Reusable TextField Widget**
  Widget _buildTextField(
      TextEditingController controller, String hintText, bool obscureText,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[200],
        suffixIcon: isPassword
            ? IconButton(
                icon:
                    Icon(obscureText ? Icons.visibility : Icons.visibility_off),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              "What can I help with?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15.0),
            child: Column(
              children: [
                _buildTextField(_sshCommandController,
                    "SSH Command (e.g., ssh root@IP)", false),
                const SizedBox(height: 10),
                _buildTextField(
                    _passwordController, "Password", _obscurePassword,
                    isPassword: true),
                const SizedBox(height: 10),
                _isConnecting
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: () => _connectToServer(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, // ✅ Black button
                          foregroundColor: Colors.white, // ✅ White text
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Connect"),
                      ),
              ],
            ),
          ),
          const Spacer(),
          _chatInputBox(), // ✅ Chat box restored at bottom
        ],
      ),
    );
  }

  /// ✅ **Chat Input Box (Same as ChatScreen)**
  Widget _chatInputBox() {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatMessageController,
              decoration: const InputDecoration(
                hintText: "Message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25.0)),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.black),
            onPressed: () {
              // Placeholder action for chat input
            },
          ),
        ],
      ),
    );
  }
}
