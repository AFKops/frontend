import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import '../providers/theme_provider.dart';
import '../utils/secure_storage.dart';

/// Three possible modes
enum LoginMode {
  passwordMode, // Original password-based
  keyManualMode, // Host + user + key
  keyParsedMode, // Parse "ssh -i key user@host"
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Original controllers
  final TextEditingController _chatNameController = TextEditingController();
  final TextEditingController _sshCommandController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _manualKeyController = TextEditingController();

  bool _obscurePassword = true;
  bool _isConnecting = false;
  bool _savePassword = false;
  bool _isTypingKey = false;

  // Current mode
  LoginMode _loginMode = LoginMode.passwordMode;

  // For manual key mode
  final TextEditingController _manualHostController = TextEditingController();
  final TextEditingController _manualUserController = TextEditingController();
  String? _keyFilePath;

  // For advanced parse
  final TextEditingController _advancedSSHController = TextEditingController();

  /// Attempts to pick an SSH key file
  Future<void> _pickSSHKey() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() {
        _keyFilePath = result.files.single.path!;
      });
    }
  }

  /// Connect based on selected mode
  void _connectToServer(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final chatName = _chatNameController.text.trim();

    if (chatName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Chat Name is required.")),
      );
      return;
    }

    setState(() => _isConnecting = true);

    if (_loginMode == LoginMode.passwordMode) {
      await _doPasswordLogin(chatProvider, chatName);
    } else if (_loginMode == LoginMode.keyManualMode) {
      await _doKeyManualLogin(chatProvider, chatName);
    } else {
      await _doKeyParseLogin(chatProvider, chatName);
    }

    setState(() => _isConnecting = false);
  }

  /// Password-based (original logic)
  Future<void> _doPasswordLogin(
      ChatProvider chatProvider, String chatName) async {
    String sshCommand = _sshCommandController.text.trim();
    String password = _passwordController.text.trim();

    if (sshCommand.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ SSH Command is required.")),
      );
      return;
    }
    if (!sshCommand.startsWith("ssh ")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Invalid SSH command format.")),
      );
      return;
    }

    // Parse "ssh user@host"
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

    // Possibly retrieve saved password
    String? savedPassword =
        await SecureStorage.getPassword(chatProvider.getCurrentChatId());
    if (savedPassword != null && password.isEmpty) {
      password = savedPassword;
      _passwordController.text = password;
    }

    // If we still have no password, ask user
    if (password.isEmpty) {
      bool shouldSave = false;
      TextEditingController pwdCtrl = TextEditingController();

      await showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text("Enter SSH Password"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pwdCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password"),
                ),
                Row(
                  children: [
                    Checkbox(
                      value: shouldSave,
                      onChanged: (val) => shouldSave = val ?? false,
                    ),
                    const Text("Save Password"),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Connect"),
              ),
            ],
          );
        },
      );

      if (pwdCtrl.text.isNotEmpty) {
        password = pwdCtrl.text;
        // Save if needed
        if (shouldSave) {
          await SecureStorage.savePassword(chatProvider.getCurrentChatId(),
              password, chatName, host, username);
        }
      }
    }

    final chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: username,
      password: password,
      isGeneralChat: false,
      savePassword: _savePassword,
    );

    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
      );
      if (_savePassword && password.isNotEmpty) {
        await SecureStorage.savePassword(
            chatId, password, chatName, host, username);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Authentication failed or SSH connection error.")),
      );
    }
  }

  /// SSH Key: user + host + file path
  Future<void> _doKeyManualLogin(
      ChatProvider chatProvider, String chatName) async {
    String host = _manualHostController.text.trim();
    String user = _manualUserController.text.trim();
    final isTypingKey = _manualKeyController.text.trim().isNotEmpty;

    String? keyValue;
    if (isTypingKey) {
      keyValue = _manualKeyController.text.trim();
    } else if (_keyFilePath != null) {
      keyValue = _keyFilePath;
    }

    if (host.isEmpty || user.isEmpty || keyValue == null || keyValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❌ Host, username, and key are required.")),
      );
      return;
    }

    final chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: user,
      password: keyValue,
      isGeneralChat: false,
      savePassword: _savePassword,
      mode: "KEY",
    );

    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
      );
      if (_savePassword) {
        await SecureStorage.savePassword(
          chatId,
          keyValue,
          chatName,
          host,
          user,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ SSH Key login failed.")),
      );
    }
  }

  /// SSH Key advanced parse: "ssh -i key.pem user@host"
  Future<void> _doKeyParseLogin(
      ChatProvider chatProvider, String chatName) async {
    final raw = _advancedSSHController.text.trim();

    if (!raw.startsWith("ssh -i ")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Must start with ssh -i <key> user@host"),
        ),
      );
      return;
    }

    // Make sure the key file was uploaded
    if (_keyFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❌ Please upload a key file using 'Select Directory'."),
        ),
      );
      return;
    }

    // Parse command like: ssh -i key.pem user@host
    final regex = RegExp(r'^ssh\s+-i\s+(\S+)\s+([^@]+)@(.+)$');
    final match = regex.firstMatch(raw);

    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Invalid SSH command format.")),
      );
      return;
    }

    final user = match.group(2)!;
    final host = match.group(3)!;
    final keyPath = _keyFilePath!;

    final chatId = await chatProvider.startNewChat(
      chatName: chatName,
      host: host,
      username: user,
      password: keyPath,
      isGeneralChat: false,
      savePassword: _savePassword,
      mode: "KEY",
    );

    if (chatId.isNotEmpty && chatProvider.isChatActive(chatId)) {
      chatProvider.setCurrentChat(chatId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(chatId: chatId)),
      );

      if (_savePassword) {
        await SecureStorage.savePassword(chatId, keyPath, chatName, host, user);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Key-based login failed.")),
      );
    }
  }

  // For building normal text fields
  Widget _buildTextField(
    TextEditingController controller,
    String hintText,
    bool obscureText,
    bool isDarkMode, {
    bool isPassword = false,
  }) {
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
            color: isDarkMode ? Colors.white54 : Colors.black26,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white38 : Colors.black26,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white : Colors.black,
            width: 1,
          ),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility : Icons.visibility_off,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              )
            : null,
      ),
    );
  }

  /// The row of 3 icon buttons for mode switching
  Widget _buildModeButtons(bool isDarkMode) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildIconMode(
          iconData: Icons.lock,
          mode: LoginMode.passwordMode,
          tooltip: "Password Login",
          isDarkMode: isDarkMode,
        ),
        const SizedBox(width: 12),
        _buildIconMode(
          iconData: Icons.vpn_key,
          mode: LoginMode.keyManualMode,
          tooltip: "Manual Key Login",
          isDarkMode: isDarkMode,
        ),
        const SizedBox(width: 12),
        _buildIconMode(
          iconData: Icons.smart_toy,
          mode: LoginMode.keyParsedMode,
          tooltip: "Advanced SSH Parsing",
          isDarkMode: isDarkMode,
        ),
      ],
    );
  }

  /// A single icon-based mode button
  Widget _buildIconMode({
    required IconData iconData,
    required LoginMode mode,
    required String tooltip,
    required bool isDarkMode,
  }) {
    bool selected = (_loginMode == mode);

    // 10% bigger: normal icons ~24, so let's do ~26 or 28
    const double iconSize = 28;
    // 8px corner radius
    const double cornerRadius = 8.0;

    // Colors
    Color bgColor, iconColor, borderColor;
    if (isDarkMode) {
      if (selected) {
        bgColor = Colors.black;
        iconColor = Colors.white;
        borderColor = Colors.white;
      } else {
        bgColor = Colors.transparent;
        iconColor = Colors.white54;
        borderColor = Colors.white54;
      }
    } else {
      if (selected) {
        bgColor = Colors.white;
        iconColor = Colors.black;
        borderColor = Colors.black;
      } else {
        bgColor = Colors.transparent;
        iconColor = Colors.black54;
        borderColor = Colors.black54;
      }
    }

    return GestureDetector(
      onTap: () => setState(() => _loginMode = mode),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(cornerRadius),
          border: Border.all(color: borderColor),
        ),
        child: Icon(iconData, color: iconColor, size: iconSize),
      ),
    );
  }

  /// Builds the card for whichever mode is selected
  Widget _buildModeCard(bool isDarkMode) {
    switch (_loginMode) {
      case LoginMode.passwordMode:
        return Column(
          children: [
            const SizedBox(height: 10),
            _buildTextField(_sshCommandController,
                "SSH Command (e.g., ssh user@host)", false, isDarkMode),
            const SizedBox(height: 10),
            _buildTextField(
                _passwordController, "Password", _obscurePassword, isDarkMode,
                isPassword: true),
            const SizedBox(height: 10),
          ],
        );

      case LoginMode.keyManualMode:
        return Column(
          children: [
            const SizedBox(height: 10),
            _buildTextField(_manualHostController, "Host (e.g. 1.2.3.4)", false,
                isDarkMode),
            const SizedBox(height: 10),
            _buildTextField(_manualUserController, "Username (e.g. ubuntu)",
                false, isDarkMode),
            const SizedBox(height: 10),

            // File picker or key textarea
            _isTypingKey
                ? TextField(
                    controller: _manualKeyController,
                    maxLines: 6,
                    style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black),
                    decoration: InputDecoration(
                      hintText: "Paste SSH Private Key here...",
                      hintStyle: TextStyle(
                          color:
                              isDarkMode ? Colors.white54 : Colors.grey[700]),
                      filled: true,
                      fillColor:
                          isDarkMode ? Colors.grey[900] : Colors.grey[200],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _isTypingKey = false),
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _pickSSHKey,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDarkMode ? Colors.white38 : Colors.black26,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.upload_file,
                              color: isDarkMode ? Colors.white : Colors.black),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _keyFilePath == null
                                  ? "Pick SSH Key File"
                                  : _keyFilePath!.split('/').last,
                              style: TextStyle(
                                  color:
                                      isDarkMode ? Colors.white : Colors.black),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit,
                                color: isDarkMode
                                    ? Colors.white54
                                    : Colors.black54),
                            onPressed: () =>
                                setState(() => _isTypingKey = true),
                          ),
                        ],
                      ),
                    ),
                  ),

            const SizedBox(height: 10),
          ],
        );

      case LoginMode.keyParsedMode:
        return Column(
          children: [
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickSSHKey,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDarkMode ? Colors.white38 : Colors.black26),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_open,
                        color: isDarkMode ? Colors.white : Colors.black),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _keyFilePath ?? "Open directory",
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        overflow: TextOverflow
                            .ellipsis, // Optional: Truncates long paths
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildTextField(_advancedSSHController, "ssh -i key.pem user@host",
                false, isDarkMode),
            const SizedBox(height: 10),
          ],
        );
    }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              "What can I help with?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Chat Name always
            _buildTextField(
                _chatNameController, "Chat Name", false, isDarkMode),
            const SizedBox(height: 10),

            // 3 Icons row
            _buildModeButtons(isDarkMode),

            // The dynamic card for whichever mode is selected
            _buildModeCard(isDarkMode),

            // Save cred & Connect
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: _savePassword,
                      onChanged: (val) =>
                          setState(() => _savePassword = val ?? false),
                      activeColor: isDarkMode ? Colors.white : Colors.black,
                    ),
                    Text(
                      _loginMode == LoginMode.passwordMode
                          ? "Save Password"
                          : "Save Key",
                      style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black),
                    ),
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
                                color: isDarkMode ? Colors.white : Colors.black,
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
    );
  }

  @override
  void dispose() {
    _chatNameController.dispose();
    _sshCommandController.dispose();
    _passwordController.dispose();
    _manualHostController.dispose();
    _manualUserController.dispose();
    _advancedSSHController.dispose();
    _manualKeyController.dispose(); // 👈 add this line here
    super.dispose();
  }
}
