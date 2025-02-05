import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/secure_auth_provider.dart';
import '../providers/theme_provider.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _triggerAuthentication(); // ✅ Auto-open biometric when screen loads
  }

  void _triggerAuthentication() async {
    setState(() => _isAuthenticating = true);
    final secureAuthProvider =
        Provider.of<SecureAuthProvider>(context, listen: false);

    bool authenticated = await secureAuthProvider.authenticate();

    if (authenticated) {
      _navigateToHome();
    } else {
      setState(() => _isAuthenticating = false);
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: true).isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF0D0D0D)
          : Colors.white, // ✅ Matches new dark mode
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 50,
              color: isDarkMode
                  ? Colors.white
                  : Colors.black, // ✅ Icon adapts to theme
            ),
            const SizedBox(height: 20),
            Text(
              "Authenticate to Access",
              style: TextStyle(
                color: isDarkMode
                    ? Colors.white
                    : Colors.black, // ✅ Text follows theme
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            if (!_isAuthenticating) // ✅ Show only when authentication fails
              ElevatedButton(
                onPressed: _triggerAuthentication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode
                      ? Colors.white
                      : Colors.black, // ✅ Button follows theme
                  foregroundColor: isDarkMode
                      ? Colors.black
                      : Colors.white, // ✅ Text color adapts
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDarkMode
                          ? Colors.white
                          : Colors.black, // ✅ Subtle border for contrast
                      width: 1.5,
                    ),
                  ),
                ),
                child: const Text("Authenticate"),
              ),
          ],
        ),
      ),
    );
  }
}
