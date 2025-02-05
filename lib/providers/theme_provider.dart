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

  bool get isDarkMode => _currentTheme == "dark";

  ThemeData get themeData {
    return isDarkMode ? darkTheme : lightTheme;
  }
}

// Define Dark Theme (with Soft Black & Outlines)
final ThemeData darkTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0D0D0D), // ✅ Soft Black
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0D0D0D),
    iconTheme: IconThemeData(color: Colors.white),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.white),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.transparent,
    border: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white24), // ✅ Subtle White Border
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white38),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white),
    ),
  ),
  buttonTheme: const ButtonThemeData(
    buttonColor: Colors.white,
    textTheme: ButtonTextTheme.primary,
  ),
);

// Define Light Theme (with Better Contrast)
final ThemeData lightTheme = ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: const Color(0xFFF7F7F7), // ✅ Softer White
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    iconTheme: IconThemeData(color: Colors.black),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.black),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black12),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black26),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black),
    ),
  ),
  buttonTheme: const ButtonThemeData(
    buttonColor: Colors.black,
    textTheme: ButtonTextTheme.primary,
  ),
);
