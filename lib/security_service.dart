import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _pinHashKey = 'user_pin_hash_v1';
  static const _hiveKeyTag = 'hive_encryption_key_v1';

  // પિન અગાઉથી સેટ કરેલો છે કે નહીં તે તપાસો
  static Future<bool> isPinSet() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  // નવો પિન સેટ કરો અને ડેટાબેઝ માટે AES કી બનાવો
  static Future<void> setupPin(String pin) async {
    final bytes = utf8.encode('SECURE_SALT_FINANCE_$pin');
    final digest = sha256.convert(bytes).toString();
    await _storage.write(key: _pinHashKey, value: digest);

    final encryptionKey = Hive.generateSecureKey();
    await _storage.write(
      key: _hiveKeyTag,
      value: base64UrlEncode(encryptionKey),
    );
  }

  // દાખલ કરેલ પિન ચકાસો
  static Future<bool> verifyPin(String enteredPin) async {
    final storedHash = await _storage.read(key: _pinHashKey);
    if (storedHash == null) return false;

    final bytes = utf8.encode('SECURE_SALT_FINANCE_$enteredPin');
    final computedHash = sha256.convert(bytes).toString();
    return storedHash == computedHash;
  }

  // AES-256 એન્ક્રિપ્શન કી મેળવો
  static Future<List<int>> getDatabaseKey() async {
    final keyString = await _storage.read(key: _hiveKeyTag);
    if (keyString != null) {
      return base64Url.decode(keyString);
    }
    final newKey = Hive.generateSecureKey();
    await _storage.write(
      key: _hiveKeyTag,
      value: base64UrlEncode(newKey),
    );
    return newKey;
  }
}
