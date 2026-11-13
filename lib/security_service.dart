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

  // ફિંગરપ્રિન્ટ ડાયલોગ એકસાથે બે વાર ટ્રિગર થતો અટકાવવા માટેના ગાર્ડ્સ
  static bool _isBusy = false;
  static DateTime? _lastSuccessTime;

  static String _getUserPrefix(String email) {
    final bytes = utf8.encode(email.trim().toLowerCase());
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  static String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(24, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  // નોંધાયેલ છેલ્લો ઈમેઇલ મેળવવો
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

  // કોઈપણ લંબાઈ અને કેરેક્ટરવાળો પાસવર્ડ સેટ કરવો
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

    // આ યુઝરના ઈમેઈલ માટે અલગ એન્ક્રિપ્શન કી
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

  // દરેક ઈમેઈલ માટે વ્યક્તિગત ડેટાબેઝ કી
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

  // ૧. મોબાઇલમાં ફિંગરપ્રિન્ટ અથવા ડિવાઇસ સ્ક્રીન લૉક ઉપલબ્ધ છે કે નહીં તે તપાસવું
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  // ૨. સેટિંગ્સમાંથી બાયોમેટ્રિક સુરક્ષા ચાલુ છે કે બંધ તે વાંચવું
  static bool isBiometricEnabledInSettings() {
    if (!Hive.isBoxOpen('settingsBox')) return false;
    final settingsBox = Hive.box('settingsBox');
    return settingsBox.get('biometricEnabled', defaultValue: true) == true;
  }

  // ૩. સેટિંગ્સમાં બાયોમેટ્રિક સુરક્ષા ચાલુ કે બંધ સેવ કરવી
  static Future<void> setBiometricEnabled(bool isEnabled) async {
    final settingsBox = await _getSettingsBox();
    await settingsBox.put('biometricEnabled', isEnabled);
  }

  // ૪. ઓટો-લૉક સમયગાળો (સેકન્ડ્સમાં) મેળવવો (ડિફોલ્ટ 30 સેકન્ડ)
  static int getAutoLockTimeoutSeconds() {
    if (!Hive.isBoxOpen('settingsBox')) return 30;
    final settingsBox = Hive.box('settingsBox');
    final dynamic val = settingsBox.get(
      'autoLockSeconds',
      defaultValue: settingsBox.get('autoLockTimeout', defaultValue: 30),
    );
    return (val as num?)?.toInt() ?? 30;
  }

  // ૫. ઓટો-લૉક સમયગાળો સેટિંગ્સમાં સેવ કરવો
  static Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    final settingsBox = await _getSettingsBox();
    await settingsBox.put('autoLockSeconds', seconds);
    await settingsBox.put('autoLockTimeout', seconds);
  }

  // ૬. બાયોમેટ્રિક / ફોન સ્ક્રીન લૉક વડે યુઝરને પ્રમાણિત કરવા (Authenticate)
  static Future<bool> authenticateWithBiometrics({bool forceCheck = false}) async {
    if (!forceCheck && !isBiometricEnabledInSettings()) {
      return true;
    }

    // જો છેલ્લા 3 સેકન્ડમાં જ સફળતાપૂર્વક અનલોક થયું હોય તો ફરીથી ડાયલોગ ન બતાવવો
    if (!forceCheck &&
        _lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!).inSeconds < 3) {
      return true;
    }

    // જો પહેલેથી જ ફિંગરપ્રિન્ટ ડાયલોગ ચાલુ હોય તો ડુપ્લિકેટ કોલ અટકાવવો
    if (_isBusy) return false;

    _isBusy = true;
    try {
      final bool hasHardware = await isBiometricAvailable();
      if (!hasHardware) {
        return true;
      }

      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: 'નાણાકીય હિસાબો સુરક્ષિત રાખવા માટે ફિંગરપ્રિન્ટ અથવા સ્ક્રીન લૉક દાખલ કરો',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // ફિંગરપ્રિન્ટ ઉપરાંત ફોનનો PIN/Pattern પણ સ્વીકારશે
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
