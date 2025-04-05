import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';

class SecureNetworkProvider extends ChangeNotifier {
  bool _isSecureInternetEnabled = false;
  List<String> _trustedNetworks = [];
  List<String> _allNetworks = [];

  bool get isSecureInternetEnabled => _isSecureInternetEnabled;
  List<String> get trustedNetworks => _trustedNetworks;
  List<String> get allNetworks => _allNetworks;

  SecureNetworkProvider() {
    _loadSecureSettings();
  }

  /// Loads settings from storage
  Future<void> _loadSecureSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isSecureInternetEnabled = prefs.getBool('secure_internet') ?? false;
    _trustedNetworks = prefs.getStringList('trusted_networks') ?? [];
    _allNetworks = prefs.getStringList('all_networks') ?? [];
    notifyListeners();
  }

  /// Checks the current network and shows an alert if untrusted
  Future<void> triggerNetworkCheck(BuildContext context) async {
    if (!_isSecureInternetEnabled) return;
    String? currentWifi = await getCurrentWifi();
    if (currentWifi == null) return;
    addToAllNetworks(currentWifi);
    bool isTrusted = await isCurrentNetworkTrusted();
    if (!isTrusted) {
      _showUntrustedNetworkAlert(context, currentWifi);
    }
  }

  /// Toggles Secure Internet
  Future<void> toggleSecureInternet(BuildContext context) async {
    _isSecureInternetEnabled = !_isSecureInternetEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('secure_internet', _isSecureInternetEnabled);
    notifyListeners();
    if (_isSecureInternetEnabled) {
      await triggerNetworkCheck(context);
    }
  }

  /// Checks if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Permission.location.serviceStatus.isEnabled;
  }

  /// Gets the currently connected Wi-Fi network
  Future<String?> getCurrentWifi() async {
    if (!await isLocationServiceEnabled()) {
      debugPrint("Location services are disabled.");
      return "Location Disabled";
    }
    if (await Permission.location.request().isGranted) {
      try {
        String? wifiName = await WiFiForIoTPlugin.getSSID();
        if (wifiName != null && wifiName.isNotEmpty) {
          addToAllNetworks(wifiName);
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

  /// Checks if the current network is trusted
  Future<bool> isCurrentNetworkTrusted() async {
    String? currentWifi = await getCurrentWifi();
    return currentWifi != null && _trustedNetworks.contains(currentWifi);
  }

  /// Checks if a specific network is trusted
  bool isNetworkTrusted(String networkName) {
    return _trustedNetworks.contains(networkName);
  }

  /// Adds a Wi-Fi network to the trusted list
  Future<void> addTrustedNetwork(String networkName) async {
    if (!_trustedNetworks.contains(networkName)) {
      _trustedNetworks.add(networkName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('trusted_networks', _trustedNetworks);
      notifyListeners();
    }
  }

  /// Removes a Wi-Fi network from the trusted list
  Future<void> removeTrustedNetwork(String networkName) async {
    _trustedNetworks.remove(networkName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('trusted_networks', _trustedNetworks);
    notifyListeners();
  }

  /// Adds a network to the all-networks list
  Future<void> addToAllNetworks(String networkName) async {
    if (!_allNetworks.contains(networkName)) {
      _allNetworks.add(networkName);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('all_networks', _allNetworks);
      notifyListeners();
    }
  }

  /// Removes a network from both all-networks and trusted lists
  Future<void> removeFromAllNetworks(String networkName) async {
    _allNetworks.remove(networkName);
    _trustedNetworks.remove(networkName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('all_networks', _allNetworks);
    await prefs.setStringList('trusted_networks', _trustedNetworks);
    notifyListeners();
  }

  /// Checks the network security and shows a warning if needed
  Future<void> checkNetworkSecurity(BuildContext context) async {
    if (!_isSecureInternetEnabled) return;
    String? currentWifi = await getCurrentWifi();
    bool isTrusted = await isCurrentNetworkTrusted();
    if (currentWifi != null) {
      addToAllNetworks(currentWifi);
      if (!isTrusted) {
        _showUntrustedNetworkAlert(context, currentWifi);
      }
    }
  }

  /// Shows an alert for untrusted networks
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
