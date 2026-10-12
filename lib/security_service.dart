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
  static const _recoveryEmailKey = 'recovery_email_v1'; // ઈમેઇલ માટે કી

  static Future<bool> isPinSet() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  // નવો પિન અને રિકવરી ઈમેઇલ એકસાથે સેટ કરો
  static Future<void> setupPin(String pin, String email) async {
    final bytes = utf8.encode('SECURE_SALT_FINANCE_$pin');
    final digest = sha256.convert(bytes).toString();
    await _storage.write(key: _pinHashKey, value: digest);
    await _storage.write(key: _recoveryEmailKey, value: email.trim().toLowerCase());

    final existingKey = await _storage.read(key: _hiveKeyTag);
    if (existingKey == null) {
      final encryptionKey = Hive.generateSecureKey();
      await _storage.write(
        key: _hiveKeyTag,
        value: base64UrlEncode(encryptionKey),
      );
    }
  }

  // રિકવરી ઈમેઇલ મેળવો
  static Future<String?> getRecoveryEmail() async {
    return await _storage.read(key: _recoveryEmailKey);
  }

  // ભવિષ્યમાં ઈમેઇલ અપડેટ કરવા માટે
  static Future<void> updateRecoveryEmail(String newEmail) async {
    await _storage.write(key: _recoveryEmailKey, value: newEmail.trim().toLowerCase());
  }

  // પિન રીસેટ કરો
  static Future<void> resetPin(String newPin) async {
    final bytes = utf8.encode('SECURE_SALT_FINANCE_$newPin');
    final digest = sha256.convert(bytes).toString();
    await _storage.write(key: _pinHashKey, value: digest);
  }

  static Future<bool> verifyPin(String enteredPin) async {
    final storedHash = await _storage.read(key: _pinHashKey);
    if (storedHash == null) return false;

    final bytes = utf8.encode('SECURE_SALT_FINANCE_$enteredPin');
    final computedHash = sha256.convert(bytes).toString();
    return storedHash == computedHash;
  }

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
