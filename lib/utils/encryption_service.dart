import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart';

String encryptFernet(String plainText, String base64Key) {
  final key = Key.fromBase64(base64Key);
  final iv = IV.fromSecureRandom(16);
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final encrypted = encrypter.encrypt(plainText, iv: iv);
  return base64.encode(iv.bytes + encrypted.bytes); // Send IV + data
}

class EncryptionService {
  static String? _cachedKey;

  /// Fetches the Fernet key from your backend (only once)
  static Future<String?> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey;

    try {
      final response = await http.get(Uri.parse('https://afkops.com/get-key'));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final key = json['key']; // assuming backend returns: { "key": "..." }
        _cachedKey = key;
        return key;
      } else {
        print('❌ Failed to fetch key: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching encryption key: $e');
    }

    return null;
  }
}
