import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:encrypt/encrypt.dart';

class EncryptionService {
  static String? _cachedKey;

  static Future<String?> getEncryptionKey() async {
    if (_cachedKey != null) return _cachedKey;

    try {
      final response = await http.get(Uri.parse('https://afkops.com/get-key'));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final key = json['key'];
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

  static Future<String> encryptAESCBC(
      String plainText, String base64Key) async {
    final key = Key.fromBase64(base64Key);
    final random = Random.secure();
    final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final iv = IV(Uint8List.fromList(ivBytes));

    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    final combinedBytes = iv.bytes + encrypted.bytes;
    return base64Encode(combinedBytes);
  }
}
