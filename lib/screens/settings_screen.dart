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
  bool _obscurePassword = true; // Toggle for password visibility

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secureAuthProvider = Provider.of<SecureAuthProvider>(context);
    final secureNetworkProvider = Provider.of<SecureNetworkProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            /// **Appearance Settings**
            const Text(
              "Appearance",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              children: ["system", "light", "dark"].map((theme) {
                return ListTile(
                  title: Text(
                    theme == "system"
                        ? "System Default"
                        : theme == "light"
                            ? "Light Mode"
                            : "Dark Mode",
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: themeProvider.currentTheme == theme
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    themeProvider.setTheme(theme);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            /// **Security Settings**
            const Text(
              "Security",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),

            SwitchListTile(
              title: const Text(
                "Enable Biometric Authentication",
                style: TextStyle(color: Colors.white),
              ),
              value: secureAuthProvider.isBiometricEnabled,
              onChanged: (value) async {
                await secureAuthProvider.toggleBiometricAccess();
              },
            ),

            /// **Master Password Setting**
            ListTile(
              title: const Text(
                "Set Master Password",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text("Tap to change",
                  style: TextStyle(color: Colors.grey)),
              onTap: () async {
                TextEditingController oldPasswordController =
                    TextEditingController();
                TextEditingController newPasswordController =
                    TextEditingController();
                TextEditingController confirmPasswordController =
                    TextEditingController();

                showDialog(
                  context: context,
                  builder: (context) => StatefulBuilder(
                    builder: (context, setDialogState) => AlertDialog(
                      title: const Text("Change Master Password"),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          /// Old Password Input
                          TextField(
                            controller: oldPasswordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: "Old Password",
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () {
                                  setDialogState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          /// New Password Input
                          TextField(
                            controller: newPasswordController,
                            obscureText: _obscurePassword,
                            decoration: const InputDecoration(
                                labelText: "New Password"),
                          ),
                          const SizedBox(height: 10),

                          /// Confirm Password Input
                          TextField(
                            controller: confirmPasswordController,
                            obscureText: _obscurePassword,
                            decoration: const InputDecoration(
                                labelText: "Confirm New Password"),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () async {
                            bool verified =
                                await secureAuthProvider.verifyMasterPassword(
                                    oldPasswordController.text);
                            if (!verified) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Incorrect old password!")),
                              );
                              return;
                            }

                            if (newPasswordController.text !=
                                confirmPasswordController.text) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text("Passwords do not match!")),
                              );
                              return;
                            }

                            bool success = await secureAuthProvider
                                .setMasterPassword(newPasswordController.text);
                            if (success) {
                              Navigator.pop(context);
                            }
                          },
                          child: const Text("Save"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            /// **Secure Internet Settings**
            const Text(
              "Secure Internet",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),

            /// **Enable Secure Internet Toggle**
            SwitchListTile(
              title: const Text(
                "Enable Secure Internet",
                style: TextStyle(color: Colors.white),
              ),
              value: secureNetworkProvider.isSecureInternetEnabled,
              onChanged: (value) {
                secureNetworkProvider.toggleSecureInternet();
              },
            ),

            /// **Trusted Networks List**
            if (secureNetworkProvider.allNetworks.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                "Trusted Networks",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 10),

              /// **Network List with Better UI**
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: secureNetworkProvider.allNetworks.length,
                itemBuilder: (context, index) {
                  final network = secureNetworkProvider.allNetworks[index];
                  return Card(
                    color: Colors.grey[900],
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text(
                        network,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          /// **Trusted Network Toggle**
                          Switch(
                            value: secureNetworkProvider.trustedNetworks
                                .contains(network),
                            onChanged: (value) {
                              if (value) {
                                secureNetworkProvider
                                    .addTrustedNetwork(network);
                              } else {
                                secureNetworkProvider
                                    .removeTrustedNetwork(network);
                              }
                            },
                          ),

                          /// **Delete Network Button**
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              secureNetworkProvider
                                  .removeFromAllNetworks(network);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],

            const SizedBox(height: 20),

            /// **Clear All Chats Button**
            Center(
              child: ElevatedButton(
                onPressed: () {
                  chatProvider.deleteAllChats();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Chat history cleared!")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
