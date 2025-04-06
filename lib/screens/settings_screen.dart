import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/secure_auth_provider.dart';
import '../utils/secure_storage.dart';
import 'package:local_auth/local_auth.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSavedPasswords();
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
}

const TextStyle _sectionHeaderStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
);
