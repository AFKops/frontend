import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  String _currentTheme = "system"; // Default to system theme

  String get currentTheme => _currentTheme;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _currentTheme = prefs.getString('themeMode') ?? "system";
    notifyListeners();
  }

  Future<void> setTheme(String theme) async {
    _currentTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', theme);
    notifyListeners();
  }

  ThemeMode get themeMode {
    switch (_currentTheme) {
      case "light":
        return ThemeMode.light;
      case "dark":
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // Add this getter
  bool get isDarkMode => _currentTheme == "dark";

  ThemeData get themeData {
    return _currentTheme == "dark" ? darkTheme : lightTheme;
  }
}

// Define Dark Theme
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.black,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.black,
    iconTheme: IconThemeData(color: Colors.white),
  ),
  textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
);

// Define Light Theme
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    iconTheme: IconThemeData(color: Colors.black),
  ),
  textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.black)),
);
