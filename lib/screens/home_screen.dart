import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import '../providers/theme_provider.dart';
import '../utils/secure_storage.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _chatNameController = TextEditingController();
  final TextEditingController _sshCommandController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _chatMessageController = TextEditingController();
  bool _obscurePassword = true;
  bool _isConnecting = false;
  bool _savePassword = false; // ✅ Checkbox for saving passwords

  /// ✅ **General Chat (No SSH)**
  void _startGeneralChat(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    String message = _chatMessageController.text.trim();

    if (message.isEmpty) return;

    String chatId = await chatProvider.startNewChat(
      chatName: "General Chat - ${DateTime.now().toLocal()}",
      host: "", // ✅ No SSH details
      username: "",
      password: "",
      isGeneralChat: true, // ✅ Mark it as a general chat
    );

    _chatMessageController.clear();

    if (mounted) {
      chatProvider.setCurrentChat(chatId);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
      );
    }
  }

  /// ✅ **Connect to SSH and retry if it fails**
  void _connectToServer(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    String chatName = _chatNameController.text.trim();
    String sshCommand = _sshCommandController.text.trim();
    String password = _passwordController.text.trim();

    if (chatName.isEmpty || sshCommand.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Chat Name and SSH Command are required.")),
      );
      return;
    }

    if (!sshCommand.startsWith("ssh ")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Invalid SSH command format.")),
      );
      return;
    }

    // ✅ Extract username and host
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

    // ✅ Check if password is saved and use it if available
    String? savedPassword =
        await SecureStorage.getPassword(chatProvider.getCurrentChatId());
    if (savedPassword != null && password.isEmpty) {
      password = savedPassword;
      _passwordController.text = password; // Autofill password field
    }

    // ✅ If no password is provided or saved, prompt the user
    if (password.isEmpty) {
      TextEditingController passwordController = TextEditingController();
      bool shouldSave = false;

      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text("Enter SSH Password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: shouldSave,
                      onChanged: (value) {
                        shouldSave = value ?? false;
                      },
                    ),
                    const Text("Save Password"),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Connect"),
              ),
            ],
          );
        },
      );

      if (passwordController.text.isNotEmpty) {
        password = passwordController.text;
        if (shouldSave) {
          await SecureStorage.savePassword(
            chatProvider.getCurrentChatId(), // ✅ Fix: Correctly get chatId
            password,
            chatName,
            host,
            username,
          );
        }
      }
    }

    setState(() => _isConnecting = true); // ✅ Show loading indicator

    // ✅ Attempt SSH connection & validate authentication
    String chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: username,
      password: password,
      isGeneralChat: false,
    );

    setState(() => _isConnecting = false); // ✅ Hide loading indicator

    // ✅ Authentication Validation: Proceed only if authentication succeeds
    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
        );
      }

      // ✅ Save password if checkbox is checked
      if (_savePassword) {
        print("⚡ Attempting to save password...");
        await SecureStorage.savePassword(
          chatId,
          password,
          chatName,
          host,
          username,
        );
        print("⚡ Password save function executed.");
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Authentication failed or SSH connection error.")),
      );
    }
  }

  /// ✅ **Attempts SSH Connection & Only Retries If It Fails**
  Future<String> _attemptConnection(ChatProvider chatProvider, String chatName,
      String host, String username, String password) async {
    String chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: username,
      password: password,
      isGeneralChat: false, // ✅ Mark as SSH chat
    );

    // ✅ **Only Retry If Chat Is Not Active**
    if (chatId.isEmpty || !chatProvider.isChatActive(chatId)) {
      await Future.delayed(
          const Duration(seconds: 1)); // ✅ Short delay before retrying
      String retryChatId = await chatProvider.startNewChat(
        chatName: chatName,
        host: host,
        username: username,
        password: password,
        isGeneralChat: false, // ✅ Mark as SSH chat
      );

      // ✅ **Only return retryChatId if it actually succeeded**
      return chatProvider.isChatActive(retryChatId) ? retryChatId : chatId;
    }

    return chatId; // ✅ First attempt worked, no retry needed
  }

  /// ✅ **Reusable TextField Widget**
  Widget _buildTextField(TextEditingController controller, String hintText,
      bool obscureText, bool isDarkMode,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(
          color:
              isDarkMode ? Colors.white : Colors.black), // ✅ Dynamic Text Color
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
            color: isDarkMode
                ? Colors.grey[500]
                : Colors.grey[700]), // ✅ Dynamic Hint Color
        filled: true,
        fillColor: Colors.transparent, // ✅ Transparent Background
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.white54 : Colors.black26,
              width: 1), // ✅ Dynamic Border
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.white38 : Colors.black26, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.white : Colors.black, width: 1),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    obscureText ? Icons.visibility : Icons.visibility_off,
                    color: isDarkMode
                        ? Colors.white
                        : Colors.black), // ✅ Dynamic Icon Color
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
    final themeProvider = Provider.of<ThemeProvider>(context); // ✅ Get theme
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor:
          isDarkMode ? const Color(0xFF0D0D0D) : Colors.white, // ✅ Dynamic
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.menu,
              color: isDarkMode
                  ? Colors.white
                  : Colors.black), // ✅ Chat History Icon
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      const HistoryScreen()), // ✅ Open Chat History
            );
          },
        ),
        title: const Text("AFKOps"),
        backgroundColor:
            isDarkMode ? const Color(0xFF0D0D0D) : Colors.white, // ✅ Dynamic
        iconTheme:
            IconThemeData(color: isDarkMode ? Colors.white : Colors.black),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: isDarkMode
                    ? Colors.white
                    : Colors.black), // ✅ Settings Icon
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        const SettingsScreen()), // ✅ Open Settings
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
                _buildTextField(
                    _chatNameController, "Chat Name", false, isDarkMode),
                const SizedBox(height: 10),
                _buildTextField(_sshCommandController,
                    "SSH Command (e.g., ssh root@IP)", false, isDarkMode),
                const SizedBox(height: 10),
                _buildTextField(_passwordController, "Password",
                    _obscurePassword, isDarkMode,
                    isPassword: true),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _savePassword,
                          onChanged: (value) async {
                            setState(() {
                              _savePassword = value ?? false;
                            });

                            if (_savePassword &&
                                _passwordController.text.isNotEmpty) {
                              // ✅ Initialize `chatProvider`
                              final chatProvider = Provider.of<ChatProvider>(
                                  context,
                                  listen: false);

                              // ✅ Extract SSH details from the command input
                              String sshCommand =
                                  _sshCommandController.text.trim();
                              if (!sshCommand.startsWith("ssh ")) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "❌ Invalid SSH command format.")),
                                );
                                return;
                              }

                              sshCommand =
                                  sshCommand.replaceFirst("ssh ", "").trim();
                              List<String> parts = sshCommand.split("@");

                              if (parts.length != 2 ||
                                  parts[0].isEmpty ||
                                  parts[1].isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          "❌ Invalid SSH format. Use: ssh user@host")),
                                );
                                return;
                              }

                              String username = parts[0].trim();
                              String host = parts[1].trim();

                              // ✅ Save the password with the correct parameters
                              await SecureStorage.savePassword(
                                chatProvider.getCurrentChatId(), // ✅ Chat ID
                                _passwordController.text, // ✅ Password
                                _chatNameController.text.trim(), // ✅ Chat Name
                                host, // ✅ Host (Extracted from SSH Command)
                                username, // ✅ Username (Extracted from SSH Command)
                              );
                            }
                          },
                          activeColor: isDarkMode ? Colors.white : Colors.black,
                        ),
                        Text("Save Password",
                            style: TextStyle(
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black)), // ✅ Dynamic
                      ],
                    ),
                    _isConnecting
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: () => _connectToServer(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDarkMode
                                  ? Colors.white
                                  : Colors.black, // ✅ Dynamic Button Color
                              foregroundColor: isDarkMode
                                  ? Colors.black
                                  : Colors.white, // ✅ Dynamic Text Color
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 40, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                    width: 1), // ✅ Border
                              ),
                            ),
                            child: const Text("Connect"),
                          ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          _chatInputBox(isDarkMode),
        ],
      ),
    );
  }

  /// ✅ **Chat Box Now Creates General Chat**
  Widget _chatInputBox(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatMessageController,
              style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black), // ✅ Dynamic
              decoration: InputDecoration(
                hintText: "Start a chat...",
                hintStyle: TextStyle(
                    color: isDarkMode
                        ? Colors.grey[500]
                        : Colors.grey[700]), // ✅ Dynamic
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white54 : Colors.black26,
                      width: 1), // ✅ Dynamic Border
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white38 : Colors.black26,
                      width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white : Colors.black,
                      width: 1),
                ),
                filled: true,
                fillColor: Colors.transparent, // ✅ Transparent Background
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send,
                color: isDarkMode
                    ? Colors.white
                    : Colors.black), // ✅ Dynamic Button Color
            onPressed: () async {
              String message = _chatMessageController.text.trim();
              if (message.isEmpty) return;

              _chatMessageController.clear();

              final chatProvider =
                  Provider.of<ChatProvider>(context, listen: false);

              String chatId = await chatProvider.startNewChat(
                chatName: "General Chat",
                isGeneralChat: true,
              );

              chatProvider.setCurrentChat(chatId);
              chatProvider.addMessage(chatId, message, isUser: true);

              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ChatScreen(chatId: chatId)),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
