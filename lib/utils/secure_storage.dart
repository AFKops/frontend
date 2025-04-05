import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:math';

/// Provides secure storage and retrieval of passwords with encryption
class SecureStorage {
  static const String _keyPrefix = "enc_password_";
  static const String _ivPrefix = "iv_";
  static const String _metadataKey = "saved_passwords_metadata";
  static const String _secureKeyAlias = "secure_aes_key";
  static final _secureStorage = FlutterSecureStorage();

  /// Retrieves or generates an AES key
  static Future<encrypt.Key> _getAESKey() async {
    String? storedKey = await _secureStorage.read(key: _secureKeyAlias);
    if (storedKey == null) {
      String newKey = _generateSecureKey(32);
      await _secureStorage.write(key: _secureKeyAlias, value: newKey);
      storedKey = newKey;
    }
    return encrypt.Key.fromUtf8(storedKey);
  }

  /// Generates a secure random AES key
  static String _generateSecureKey(int length) {
    const chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    final random = Random.secure();
    return List.generate(length, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Encrypts a password with a unique IV
  static Future<Map<String, String>> _encryptPassword(String password) async {
    final key = await _getAESKey();
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(password, iv: iv);
    return {
      "password": encrypted.base64,
      "iv": iv.base64,
    };
  }

  /// Decrypts a password using the stored IV
  static Future<String> _decryptPassword(
      String encrypted, String ivBase64) async {
    final key = await _getAESKey();
    final iv = encrypt.IV.fromBase64(ivBase64);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    return encrypter.decrypt(encrypt.Encrypted.fromBase64(encrypted), iv: iv);
  }

  /// Saves an encrypted password and metadata
  static Future<void> savePassword(String chatId, String password,
      String chatName, String host, String username) async {
    print(
        "Saving password for Chat ID: $chatId | Host: $host | Username: $username");
    final prefs = await SharedPreferences.getInstance();
    final encryptedData = await _encryptPassword(password);

    await prefs.setString(_keyPrefix + chatId, encryptedData["password"]!);
    await prefs.setString(_ivPrefix + chatId, encryptedData["iv"]!);

    List<Map<String, String>> metadataList = await _getMetadataList();
    metadataList.removeWhere((entry) => entry["chatId"] == chatId);
    metadataList.add({
      "chatId": chatId,
      "chatName": chatName,
      "host": host,
      "username": username
    });

    await prefs.setString(_metadataKey, jsonEncode(metadataList));
    print("Password saved successfully!");
  }

  /// Retrieves a decrypted password
  static Future<String?> getPassword(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final encryptedPassword = prefs.getString(_keyPrefix + chatId);
    final ivBase64 = prefs.getString(_ivPrefix + chatId);
    if (encryptedPassword == null || ivBase64 == null) {
      print("No saved password found for Chat ID: $chatId");
      return null;
    }
    print("Found saved password for Chat ID: $chatId");
    return await _decryptPassword(encryptedPassword, ivBase64);
  }

  /// Deletes a stored password and metadata
  static Future<void> deletePassword(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPrefix + chatId);
    await prefs.remove(_ivPrefix + chatId);

    List<Map<String, String>> metadataList = await _getMetadataList();
    metadataList.removeWhere((entry) => entry["chatId"] == chatId);
    await prefs.setString(_metadataKey, jsonEncode(metadataList));
  }

  /// Returns all saved passwords metadata without actual passwords
  static Future<List<Map<String, String>>> getAllSavedPasswords() async {
    return await _getMetadataList();
  }

  /// Internal method to get metadata list
  static Future<List<Map<String, String>>> _getMetadataList() async {
    final prefs = await SharedPreferences.getInstance();
    final storedData = prefs.getString(_metadataKey);
    if (storedData == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(storedData);
      return decoded.map((entry) {
        return Map<String, String>.from(entry as Map);
      }).toList();
    } catch (e) {
      print("Error parsing saved metadata: $e");
      return [];
    }
  }
}
