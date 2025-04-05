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
  bool _savePassword = false;

  /// Starts a general chat (no SSH)
  void _startGeneralChat(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    String message = _chatMessageController.text.trim();
    if (message.isEmpty) return;
    String chatId = await chatProvider.startNewChat(
      chatName: "General Chat - ${DateTime.now().toLocal()}",
      host: "",
      username: "",
      password: "",
      isGeneralChat: true,
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

  /// Connects to a remote server over SSH
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

    String? savedPassword =
        await SecureStorage.getPassword(chatProvider.getCurrentChatId());
    if (savedPassword != null && password.isEmpty) {
      password = savedPassword;
      _passwordController.text = password;
    }

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
            chatProvider.getCurrentChatId(),
            password,
            chatName,
            host,
            username,
          );
        }
      }
    }

    setState(() => _isConnecting = true);
    String chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: username,
      password: password,
      isGeneralChat: false,
      savePassword: _savePassword,
    );
    setState(() => _isConnecting = false);

    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
        );
      }
      if (_savePassword) {
        await SecureStorage.savePassword(
          chatId,
          password,
          chatName,
          host,
          username,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Authentication failed or SSH connection error.")),
      );
    }
  }

  /// Attempts SSH connection and retries if it fails
  Future<String> _attemptConnection(ChatProvider chatProvider, String chatName,
      String host, String username, String password) async {
    String chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: username,
      password: password,
      isGeneralChat: false,
    );
    if (chatId.isEmpty || !chatProvider.isChatActive(chatId)) {
      await Future.delayed(const Duration(seconds: 1));
      String retryChatId = await chatProvider.startNewChat(
        chatName: chatName,
        host: host,
        username: username,
        password: password,
        isGeneralChat: false,
      );
      return chatProvider.isChatActive(retryChatId) ? retryChatId : chatId;
    }
    return chatId;
  }

  /// Builds a single text field widget
  Widget _buildTextField(TextEditingController controller, String hintText,
      bool obscureText, bool isDarkMode,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle:
            TextStyle(color: isDarkMode ? Colors.grey[500] : Colors.grey[700]),
        filled: true,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: isDarkMode ? Colors.white54 : Colors.black26, width: 1),
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
                    color: isDarkMode ? Colors.white : Colors.black),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon:
              Icon(Icons.menu, color: isDarkMode ? Colors.white : Colors.black),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            );
          },
        ),
        title: const Text("AFKOps"),
        backgroundColor: isDarkMode ? const Color(0xFF0D0D0D) : Colors.white,
        iconTheme:
            IconThemeData(color: isDarkMode ? Colors.white : Colors.black),
        actions: [
          IconButton(
            icon: Icon(Icons.settings,
                color: isDarkMode ? Colors.white : Colors.black),
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
                              final chatProvider = Provider.of<ChatProvider>(
                                  context,
                                  listen: false);
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
                              await SecureStorage.savePassword(
                                chatProvider.getCurrentChatId(),
                                _passwordController.text,
                                _chatNameController.text.trim(),
                                host,
                                username,
                              );
                            }
                          },
                          activeColor: isDarkMode ? Colors.white : Colors.black,
                        ),
                        Text("Save Password",
                            style: TextStyle(
                                color:
                                    isDarkMode ? Colors.white : Colors.black)),
                      ],
                    ),
                    _isConnecting
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: () => _connectToServer(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isDarkMode ? Colors.white : Colors.black,
                              foregroundColor:
                                  isDarkMode ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 40, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black,
                                    width: 1),
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

  /// Builds the chat input box for a general chat
  Widget _chatInputBox(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _chatMessageController,
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "Start a chat...",
                hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[700]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                      color: isDarkMode ? Colors.white54 : Colors.black26,
                      width: 1),
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
                fillColor: Colors.transparent,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send,
                color: isDarkMode ? Colors.white : Colors.black),
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
