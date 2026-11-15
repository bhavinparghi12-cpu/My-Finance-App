import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final LocalAuthentication _auth = LocalAuthentication();

  // ફિંગરપ્રિન્ટ ડાયલોગ ચાલુ હોય ત્યારે ડુપ્લિકેટ કોલ અને લૂપ રોકવા માટેના ગાર્ડ્સ
  static bool _isBusy = false;
  static DateTime? _lastSuccessTime;

  static bool get isAuthenticatingNow => _isBusy;

  static bool isWithinGracePeriod({int seconds = 5}) {
    if (_lastSuccessTime == null) return false;
    return DateTime.now().difference(_lastSuccessTime!).inSeconds < seconds;
  }

  static String _getUserPrefix(String email) {
    final bytes = utf8.encode(email.trim().toLowerCase());
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  static String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(24, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  static Future<String?> getLastActiveEmail() async {
    return await _storage.read(key: 'last_active_email');
  }

  static Future<void> setLastActiveEmail(String email) async {
    await _storage.write(
      key: 'last_active_email',
      value: email.trim().toLowerCase(),
    );
  }

  static Future<bool> isPasswordSetForEmail(String email) async {
    final prefix = _getUserPrefix(email);
    final hash = await _storage.read(key: '${prefix}_pwd_hash');
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> setupUserAccount(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefix = _getUserPrefix(cleanEmail);
    final salt = _generateSalt();

    await _storage.write(key: '${prefix}_salt', value: salt);

    final bytes = utf8.encode('$salt$password');
    final digest = sha256.convert(bytes).toString();

    await _storage.write(key: '${prefix}_pwd_hash', value: digest);
    await _storage.write(key: '${prefix}_email', value: cleanEmail);
    await setLastActiveEmail(cleanEmail);

    final existingKey = await _storage.read(key: '${prefix}_hive_key');
    if (existingKey == null) {
      final encryptionKey = Hive.generateSecureKey();
      await _storage.write(
        key: '${prefix}_hive_key',
        value: base64UrlEncode(encryptionKey),
      );
    }
  }

  static Future<bool> verifyPassword(String email, String enteredPassword) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefix = _getUserPrefix(cleanEmail);

    final storedHash = await _storage.read(key: '${prefix}_pwd_hash');
    final salt = await _storage.read(key: '${prefix}_salt');

    if (storedHash == null || salt == null) return false;

    final bytes = utf8.encode('$salt$enteredPassword');
    final computedHash = sha256.convert(bytes).toString();

    return storedHash == computedHash;
  }

  static Future<void> resetPassword(String email, String newPassword) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefix = _getUserPrefix(cleanEmail);
    final salt = _generateSalt();

    await _storage.write(key: '${prefix}_salt', value: salt);

    final bytes = utf8.encode('$salt$newPassword');
    final digest = sha256.convert(bytes).toString();
    await _storage.write(key: '${prefix}_pwd_hash', value: digest);
  }

  static Future<List<int>> getDatabaseKeyForEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final prefix = _getUserPrefix(cleanEmail);

    final keyString = await _storage.read(key: '${prefix}_hive_key');
    if (keyString != null) {
      return base64Url.decode(keyString);
    }
    final newKey = Hive.generateSecureKey();
    await _storage.write(
      key: '${prefix}_hive_key',
      value: base64UrlEncode(newKey),
    );
    return newKey;
  }

  // =========================================================================
  // સુધારેલા બાયોમેટ્રિક (ફિંગરપ્રિન્ટ / PIN) અને ઓટો-લૉક સુરક્ષા ફંક્શન્સ
  // =========================================================================

  static Future<Box> _getSettingsBox() async {
    if (!Hive.isBoxOpen('settingsBox')) {
      return await Hive.openBox('settingsBox');
    }
    return Hive.box('settingsBox');
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      if (!canCheck && !isSupported) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty || isSupported;
    } catch (_) {
      return false;
    }
  }

  static bool isBiometricEnabledInSettings() {
    if (!Hive.isBoxOpen('settingsBox')) return true;
    final settingsBox = Hive.box('settingsBox');
    return settingsBox.get('biometricEnabled', defaultValue: true) == true;
  }

  static Future<void> setBiometricEnabled(bool isEnabled) async {
    final settingsBox = await _getSettingsBox();
    await settingsBox.put('biometricEnabled', isEnabled);
  }

  static int getAutoLockTimeoutSeconds() {
    if (!Hive.isBoxOpen('settingsBox')) return 30;
    final settingsBox = Hive.box('settingsBox');
    final dynamic val = settingsBox.get(
      'autoLockSeconds',
      defaultValue: settingsBox.get('autoLockTimeout', defaultValue: 30),
    );
    return (val as num?)?.toInt() ?? 30;
  }

  static Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    final settingsBox = await _getSettingsBox();
    await settingsBox.put('autoLockSeconds', seconds);
    await settingsBox.put('autoLockTimeout', seconds);
  }

  static Future<bool> authenticateWithBiometrics({bool forceCheck = false}) async {
    if (!forceCheck && !isBiometricEnabledInSettings()) {
      return true;
    }

    // forceCheck હોવા છતાં જો છેલ્લી 2 સેકન્ડમાં અનલોક થયું હોય તો ડબલ કોલ રોકો
    if (_lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!).inSeconds < 2) {
      return true;
    }

    if (_isBusy) return false;
    _isBusy = true;

    try {
      final bool hasHardware = await isBiometricAvailable();
      if (!hasHardware) {
        return false;
      }

      // અગાઉનો કોઈ અધૂરો ડાયલોગ હોય તો બંધ કરો
      try {
        await _auth.stopAuthentication();
      } catch (_) {}

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason:
            'નાણાકીય હિસાબો સુરક્ષિત રાખવા માટે ફિંગરપ્રિન્ટ અથવા સ્ક્રીન લૉક દાખલ કરો',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );

      if (didAuthenticate) {
        _lastSuccessTime = DateTime.now();
      }
      return didAuthenticate;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    } finally {
      _isBusy = false;
    }
  }
}
