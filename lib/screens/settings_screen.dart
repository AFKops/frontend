import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/secure_auth_provider.dart';
import '../utils/secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, String?> savedPasswords = {};
  Map<String, bool> isPasswordVisible = {};
  Map<String, String> chatNames = {};
  bool hasAuthenticated = false;

  // For WebSocket URL input
  TextEditingController _wsUrlController = TextEditingController();
  String _savedWsUrl = "ws://afkops.com/ssh-stream"; // Default WebSocket URL
  bool _isEditing = false; // Keep track of whether the field is editable

  @override
  void initState() {
    super.initState();
    _loadSavedPasswords();
    _loadWebSocketUrl(); // Load saved WebSocket URL
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secureAuthProvider = Provider.of<SecureAuthProvider>(context);

    final isDarkMode = themeProvider.currentTheme == "dark";
    final backgroundColor = isDarkMode ? const Color(0xFF0D0D0D) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[700];
    final toggleColor = isDarkMode ? Colors.white : Colors.black;
    final toggleInactiveColor =
        isDarkMode ? Colors.grey[600] : Colors.grey[400];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text("Settings", style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text("Appearance",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            Column(
              children: ["system", "light", "dark"].map((themeMode) {
                return ListTile(
                  title: Text(
                    themeMode == "system"
                        ? "System Default"
                        : themeMode == "light"
                            ? "Light Mode"
                            : "Dark Mode",
                    style: TextStyle(color: textColor),
                  ),
                  trailing: themeProvider.currentTheme == themeMode
                      ? Icon(Icons.check, color: toggleColor)
                      : null,
                  onTap: () {
                    themeProvider.setTheme(themeMode);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text("Security",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ListTile(
                      leading:
                          Icon(Icons.fingerprint, color: textColor, size: 20),
                      title: Text("Enable Biometric Authentication",
                          style: TextStyle(color: textColor)),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: secureAuthProvider.isBiometricEnabled,
                      onChanged: (value) async {
                        await secureAuthProvider.toggleBiometricAccess();
                      },
                      activeColor: toggleColor,
                      inactiveTrackColor: toggleInactiveColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("Passwords & Keys",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            savedPasswords.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text("No saved passwords & keys",
                        style: TextStyle(color: subTextColor)),
                  )
                : Column(
                    children: savedPasswords.entries.map((entry) {
                      final chatId = entry.key;
                      final password = entry.value ?? "No password";
                      final isVisible = isPasswordVisible[chatId] ?? false;
                      final displayName = chatNames[chatId]?.isNotEmpty == true
                          ? chatNames[chatId]!
                          : chatId;
                      return ListTile(
                        title: Text(displayName,
                            style: TextStyle(color: textColor)),
                        subtitle: Text(
                          isVisible ? password : "••••••••••",
                          style: TextStyle(color: subTextColor),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: textColor,
                              ),
                              onPressed: () async {
                                if (!hasAuthenticated) {
                                  bool authenticated = await _authenticate();
                                  if (authenticated) {
                                    setState(() {
                                      isPasswordVisible[chatId] = !isVisible;
                                      hasAuthenticated = true;
                                    });
                                  }
                                } else {
                                  setState(() {
                                    isPasswordVisible[chatId] = !isVisible;
                                  });
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSavedPassword(chatId),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 20),

            // WebSocket URL section
            Text("WebSocket URL",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment
                    .spaceBetween, // Align the content with space between
                children: [
                  Expanded(
                    child: Text(
                      _savedWsUrl, // Display the current WebSocket URL
                      style: TextStyle(color: textColor),
                      overflow:
                          TextOverflow.ellipsis, // Ensure it doesn't overflow
                    ),
                  ),
                  // Pencil Icon (Edit)
                  IconButton(
                    icon: Icon(
                      Icons.edit,
                      color: textColor,
                    ),
                    onPressed:
                        _showWebSocketPopup, // Open the popup to edit URL
                  ),
                  // Reload Icon (Reset to default)
                  IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: textColor,
                    ),
                    onPressed: _resetWebSocketUrl, // Reset to default URL
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            Center(
              child: ElevatedButton(
                onPressed: () {
                  chatProvider.deleteAllChats();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Chat history cleared!")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: toggleColor,
                  foregroundColor: backgroundColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5)),
                ),
                child: const Text("Delete All Chats",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  /// Loads saved passwords and chat names
  Future<void> _loadSavedPasswords() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    for (var chatId in chatProvider.getChatIds()) {
      final chatObject = chatProvider.getChatById(chatId);
      final name = chatObject?['name'] ?? '';
      final password = await SecureStorage.getPassword(chatId);
      if (password != null) {
        savedPasswords[chatId] = password;
        chatNames[chatId] = name.isNotEmpty ? name : chatId;
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  /// Loads the saved WebSocket URL from SharedPreferences
  Future<void> _loadWebSocketUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedUrl = prefs.getString("wsUrl");
    if (savedUrl != null) {
      setState(() {
        _savedWsUrl = savedUrl;
        _wsUrlController.text = savedUrl;
      });
    }
  }

  /// Saves the WebSocket URL to SharedPreferences
  void _saveWebSocketUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String newWsUrl = _wsUrlController.text.trim();

    if (newWsUrl != _savedWsUrl) {
      // Save the new URL
      await prefs.setString("wsUrl", newWsUrl);

      // Update state
      setState(() {
        _savedWsUrl = newWsUrl;
      });

      // Disconnect all active chats
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      for (var chatId in chatProvider.getChatIds()) {
        chatProvider.disconnectChat(chatId); // Gracefully closes WebSocket
      }

      // Optionally show a toast/snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("WebSocket updated. All chats disconnected.")),
      );
    }

    Navigator.of(context).pop(); // Close popup
  }

  /// Authenticates with biometrics to show a password
  Future<bool> _authenticate() async {
    final LocalAuthentication auth = LocalAuthentication();
    return await auth.authenticate(
      localizedReason: "Authenticate to view saved passwords",
      options: const AuthenticationOptions(biometricOnly: true),
    );
  }

  /// Deletes a saved password and clears it from memory
  Future<void> _deleteSavedPassword(String chatId) async {
    await SecureStorage.deletePassword(chatId);
    setState(() {
      savedPasswords.remove(chatId);
      isPasswordVisible.remove(chatId);
      chatNames.remove(chatId);
    });
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final chatData = chatProvider.getChatById(chatId);
    if (chatData != null) {
      chatData['password'] = "";
      chatData['passwordSaved'] = false;
      chatData['connected'] = false;
      chatProvider.notifyListeners();
      await chatProvider.saveChatHistory();
    }
  }

  // Show the WebSocket edit popup
  void _showWebSocketPopup() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[800];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _wsUrlController,
                style: TextStyle(color: textColor), // Input text color
                decoration: InputDecoration(
                  labelText: "WebSocket URL",
                  labelStyle: TextStyle(color: subTextColor),
                  hintText: "Enter your WebSocket URL",
                  hintStyle: TextStyle(color: subTextColor),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "This is a sensitive link responsible for connecting to your remote server. Make sure this matches your backend exactly. Changing the link will disconnect all remote connections.",
                style: TextStyle(fontSize: 14, color: subTextColor),
              ),
              const SizedBox(height: 10),
              Text(
                "Examples:\n"
                "- ws://123.456.789.0:8000/ssh-stream\n"
                "- wss://yourdomain.com/ssh-stream",
                style: TextStyle(fontSize: 13, color: subTextColor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Cancel
              },
              child: const Text("Cancel", style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: _saveWebSocketUrl, // Save
              child: Text("Save", style: TextStyle(color: Colors.blue[300])),
            ),
          ],
        );
      },
    );
  }

  // Reset the WebSocket URL to default
  void _resetWebSocketUrl() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    setState(() {
      _wsUrlController.text = "ws://afkops.com/ssh-stream"; // Reset to default
      _savedWsUrl = _wsUrlController.text;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("wsUrl", _savedWsUrl);

    // Disconnect all chats
    for (var chatId in chatProvider.getChatIds()) {
      chatProvider.disconnectChat(chatId);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Reset to default. All chats disconnected.")),
    );
  }
}

const TextStyle _sectionHeaderStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
);
