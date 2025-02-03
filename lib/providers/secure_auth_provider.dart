import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class SecureAuthProvider extends ChangeNotifier {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _isBiometricEnabled = false;
  String? _masterPassword;

  bool get isBiometricEnabled => _isBiometricEnabled;
  String? get masterPassword => _masterPassword;

  SecureAuthProvider() {
    _loadAuthSettings();
  }

  Future<void> _loadAuthSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isBiometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    _masterPassword = prefs.getString('master_password');
    notifyListeners();
  }

  /// **Check if the device supports biometrics**
  Future<bool> _canCheckBiometrics() async {
    try {
      bool canAuthenticate = await _auth.canCheckBiometrics;
      bool isDeviceSecure = await _auth.isDeviceSupported();
      return canAuthenticate && isDeviceSecure;
    } catch (e) {
      debugPrint("Biometric check failed: $e");
      return false;
    }
  }

  /// **Authenticate using Biometrics or PIN**
  Future<bool> authenticate() async {
    try {
      bool canUseBiometric = await _canCheckBiometrics();
      debugPrint("Can use biometric: $canUseBiometric");

      bool authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to access secure settings',
        options: const AuthenticationOptions(
          biometricOnly: false, // Allow PIN fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!authenticated) {
        debugPrint("Authentication failed.");
      }

      return authenticated;
    } catch (e) {
      debugPrint("Error during authentication: $e");
      return false;
    }
  }

  /// **Toggle biometric access**
  Future<void> toggleBiometricAccess() async {
    debugPrint("Attempting to toggle biometric...");
    bool authenticated = await authenticate();

    if (authenticated) {
      _isBiometricEnabled = !_isBiometricEnabled;
      final prefs = await SharedPreferences.getInstance();
      prefs.setBool('biometric_enabled', _isBiometricEnabled);
      notifyListeners();
      debugPrint("Biometric status updated: $_isBiometricEnabled");
    } else {
      debugPrint("Biometric toggle failed due to authentication failure.");
    }
  }

  /// **Set master password (requires authentication)**
  Future<bool> setMasterPassword(String password) async {
    bool authenticated = await authenticate();
    if (authenticated) {
      _masterPassword = password;
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('master_password', password);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// **Verify master password**
  Future<bool> verifyMasterPassword(String password) async {
    return _masterPassword != null && _masterPassword == password;
  }
}
