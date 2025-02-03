import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/secure_auth_provider.dart';
import 'providers/secure_network_provider.dart';
import 'screens/auth_screen.dart'; // ✅ Import the new AuthScreen
import 'screens/home_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ChatProvider()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => SecureAuthProvider()),
        ChangeNotifierProvider(create: (context) => SecureNetworkProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final secureNetworkProvider =
        Provider.of<SecureNetworkProvider>(context, listen: false);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: Builder(
        builder: (context) {
          secureNetworkProvider.checkNetworkSecurity(context);
          return const AuthScreen(); // ✅ Start with AuthScreen instead of HomeScreen
        },
      ),
    );
  }
}
