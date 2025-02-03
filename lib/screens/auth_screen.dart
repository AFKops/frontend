import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/secure_auth_provider.dart';
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline,
                size: 50, color: Colors.white), // ✅ Thinner lock icon
            const SizedBox(height: 20),
            const Text(
              "Authenticate to Access",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 20),
            if (!_isAuthenticating) // ✅ Only show button if authentication failed
              ElevatedButton(
                onPressed: _triggerAuthentication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
                child: const Text("Authenticate"),
              ),
          ],
        ),
      ),
    );
  }
}
