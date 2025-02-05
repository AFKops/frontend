import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/secure_auth_provider.dart';
import '../providers/secure_network_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secureAuthProvider = Provider.of<SecureAuthProvider>(context);
    final secureNetworkProvider = Provider.of<SecureNetworkProvider>(context);

    final isDarkMode = themeProvider.currentTheme == "dark";
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final subTextColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];
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
            /// **Appearance Settings**
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

            /// **Security Settings**
            const SizedBox(height: 20),
            Text("Security",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            Padding(
              padding: const EdgeInsets.only(left: 10), // Ensures alignment
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
                    scale: 0.75, // Smaller toggle
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

            /// **Secure Internet Settings**
            const SizedBox(height: 20),
            Text("Secure Internet",
                style: _sectionHeaderStyle.copyWith(color: subTextColor)),
            Padding(
              padding: const EdgeInsets.only(left: 10), // Align properly
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ListTile(
                      leading: Icon(Icons.security, color: textColor, size: 20),
                      title: Text("Enable Secure Internet",
                          style: TextStyle(color: textColor)),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.75, // Smaller toggle
                    child: Switch(
                      value: secureNetworkProvider.isSecureInternetEnabled,
                      onChanged: (value) {
                        secureNetworkProvider.toggleSecureInternet(context);
                      },
                      activeColor: toggleColor,
                      inactiveTrackColor: toggleInactiveColor,
                    ),
                  ),
                ],
              ),
            ),

            /// **Show Trusted Networks List (Only if Secure Internet is Enabled)**
            if (secureNetworkProvider.isSecureInternetEnabled &&
                secureNetworkProvider.allNetworks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text("Trusted Networks",
                  style: TextStyle(color: subTextColor, fontSize: 14)),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: secureNetworkProvider.trustedNetworks.length,
                itemBuilder: (context, index) {
                  final network = secureNetworkProvider.trustedNetworks[index];
                  return ListTile(
                    title: Text(network, style: TextStyle(color: textColor)),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: Colors.red, size: 20),
                      onPressed: () {
                        secureNetworkProvider.removeTrustedNetwork(network);
                      },
                    ),
                  );
                },
              ),
            ],

            /// **Clear All Chats Button**
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
}

/// **Reusable Styles**
const TextStyle _sectionHeaderStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.bold,
);
