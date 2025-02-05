import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';

class SecureNetworkProvider extends ChangeNotifier {
  bool _isSecureInternetEnabled = false;
  List<String> _trustedNetworks = [];
  List<String> _allNetworks = []; // Stores all networks ever connected

  bool get isSecureInternetEnabled => _isSecureInternetEnabled;
  List<String> get trustedNetworks => _trustedNetworks;
  List<String> get allNetworks => _allNetworks;

  SecureNetworkProvider() {
    _loadSecureSettings();
  }

  /// Load settings from storage
  /// **Load settings from storage** (DO NOT call `getCurrentWifi()` here)
  Future<void> _loadSecureSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isSecureInternetEnabled = prefs.getBool('secure_internet') ?? false;
    _trustedNetworks = prefs.getStringList('trusted_networks') ?? [];
    _allNetworks = prefs.getStringList('all_networks') ?? [];
    notifyListeners();
  }

  /// **NEW: Trigger Network Security Check (Only when user reaches HomeScreen)**
  Future<void> triggerNetworkCheck(BuildContext context) async {
    if (!_isSecureInternetEnabled) return;

    String? currentWifi = await getCurrentWifi();
    if (currentWifi == null) return;

    addToAllNetworks(currentWifi); // Ensure it's stored
    bool isTrusted = await isCurrentNetworkTrusted();

    if (!isTrusted) {
      _showUntrustedNetworkAlert(context, currentWifi);
    }
  }

  /// Toggle Secure Internet option
  Future<void> toggleSecureInternet(BuildContext context) async {
    _isSecureInternetEnabled = !_isSecureInternetEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('secure_internet', _isSecureInternetEnabled);
    notifyListeners();

    // 🔥 **NEW: Immediately check current network**
    if (_isSecureInternetEnabled) {
      await triggerNetworkCheck(context);
    }
  }

  /// **Check if Location Services are Enabled**
  Future<bool> isLocationServiceEnabled() async {
    return await Permission.location.serviceStatus.isEnabled;
  }

  /// Detect the currently connected network (Wi-Fi only)
  Future<String?> getCurrentWifi() async {
    // Check if location services are enabled
    if (!await isLocationServiceEnabled()) {
      debugPrint("Location services are disabled.");
      return "Location Disabled";
    }

    // Request location permission
    if (await Permission.location.request().isGranted) {
      try {
        String? wifiName = await WiFiForIoTPlugin.getSSID();
        if (wifiName != null && wifiName.isNotEmpty) {
          addToAllNetworks(wifiName); // Ensure the network is stored
        }
        return wifiName ?? "Unknown Network";
      } catch (e) {
        debugPrint("Error fetching SSID: $e");
        return "Unknown Network";
      }
    } else {
      debugPrint("Location permission denied.");
      return "Permission Required";
    }
  }

  /// Check if the current network is trusted
  Future<bool> isCurrentNetworkTrusted() async {
    String? currentWifi = await getCurrentWifi();
    return currentWifi != null && _trustedNetworks.contains(currentWifi);
  }

  /// ✅ **Fix: Add this method to check if a specific network is trusted**
  bool isNetworkTrusted(String networkName) {
    return _trustedNetworks.contains(networkName);
  }

  /// Add a Wi-Fi network to trusted list
  Future<void> addTrustedNetwork(String networkName) async {
    if (!_trustedNetworks.contains(networkName)) {
      _trustedNetworks.add(networkName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('trusted_networks', _trustedNetworks);
      notifyListeners();
    }
  }

  /// Remove a Wi-Fi network from trusted list
  Future<void> removeTrustedNetwork(String networkName) async {
    _trustedNetworks.remove(networkName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trusted_networks', _trustedNetworks);
    notifyListeners();
  }

  /// Add to all networks list (stores any network the app connects to)
  Future<void> addToAllNetworks(String networkName) async {
    if (!_allNetworks.contains(networkName)) {
      _allNetworks.add(networkName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('all_networks', _allNetworks);
      notifyListeners();
    }
  }

  /// Remove a Wi-Fi network from **all** networks list
  Future<void> removeFromAllNetworks(String networkName) async {
    _allNetworks.remove(networkName);
    _trustedNetworks
        .remove(networkName); // Ensure it's also removed from trusted list
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('all_networks', _allNetworks);
    await prefs.setStringList('trusted_networks', _trustedNetworks);
    notifyListeners();
  }

  /// Check network security and show a warning if needed
  Future<void> checkNetworkSecurity(BuildContext context) async {
    if (!_isSecureInternetEnabled) return;

    String? currentWifi = await getCurrentWifi();
    bool isTrusted = await isCurrentNetworkTrusted();

    if (currentWifi != null) {
      addToAllNetworks(currentWifi); // Ensure current network is stored
      if (!isTrusted) {
        _showUntrustedNetworkAlert(context, currentWifi);
      }
    }
  }

  /// Show warning for untrusted network
  void _showUntrustedNetworkAlert(BuildContext context, String networkName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Untrusted Network Detected"),
        content: Text(
            "You are connected to '$networkName', which is not in your trusted networks."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Dismiss"),
          ),
          TextButton(
            onPressed: () {
              addTrustedNetwork(networkName);
              Navigator.pop(context);
            },
            child: const Text("Trust This Network"),
          ),
        ],
      ),
    );
  }
}
