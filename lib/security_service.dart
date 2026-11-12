import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final LocalAuthentication _auth = LocalAuthentication();

  static String _getUserPrefix(String email) {
    final bytes = utf8.encode(email.trim().toLowerCase());
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  static String _generateSalt() {
    final random = Random.secure();
    final values = List<int>.generate(24, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }

  // નોંધાયેલ છેલ્લો ઈમેઇલ
  static Future<String?> getLastActiveEmail() async {
    return await _storage.read(key: 'last_active_email');
  }

  static Future<void> setLastActiveEmail(String email) async {
    await _storage.write(key: 'last_active_email', value: email.trim().toLowerCase());
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
  // નવા ઉમેરેલા બાયોમેટ્રિક (ફિંગરપ્રિન્ટ / PIN) અને ઓટો-લૉક સુરક્ષા ફંક્શન્સ
  // =========================================================================

  // ૧. મોબાઇલમાં ફિંગરપ્રિન્ટ / બાયોમેટ્રિક હાર્ડવેર ઉપલબ્ધ છે કે નહીં તે તપાસવું
  static Future<bool> isBiometricAvailable() async {
    try {
      final bool canCheck = await _auth.canCheckBiometrics;
      final bool isSupported = await _auth.isDeviceSupported();
      final List<BiometricType> availableBiometrics = await _auth.getAvailableBiometrics();
      
      return (canCheck || isSupported) && availableBiometrics.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ૨. સેટિંગ્સમાંથી બાયોમેટ્રિક સુરક્ષા ચાલુ (Enable) છે કે બંધ (Disable) તે વાંચવું
  static bool isBiometricEnabledInSettings() {
    if (!Hive.isBoxOpen('settingsBox')) return false;
    final settingsBox = Hive.box('settingsBox');
    return settingsBox.get('biometricEnabled', defaultValue: true);
  }

  // ૩. સેટિંગ્સમાં બાયોમેટ્રિક સુરક્ષા ચાલુ કે બંધ સેવ કરવી
  static Future<void> setBiometricEnabled(bool isEnabled) async {
    final settingsBox = Hive.box('settingsBox');
    await settingsBox.put('biometricEnabled', isEnabled);
  }

  // ૪. ઓટો-લૉક સમયગાળો (સેકન્ડ્સમાં) મેળવવો (ડિફોલ્ટ 30 સેકન્ડ)
  static int getAutoLockTimeoutSeconds() {
    if (!Hive.isBoxOpen('settingsBox')) return 30;
    final settingsBox = Hive.box('settingsBox');
    return settingsBox.get('autoLockSeconds', defaultValue: 30);
  }

  // ૫. ઓટો-લૉક સમયગાળો સેટિંગ્સમાં સેવ કરવો
  static Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    final settingsBox = Hive.box('settingsBox');
    await settingsBox.put('autoLockSeconds', seconds);
  }

  // ૬. બાયોમેટ્રિક / ફોન સ્ક્રીન લૉક વડે યુઝરને પ્રમાણિત કરવા (Authenticate)
  static Future<bool> authenticateWithBiometrics({bool forceCheck = false}) async {
    // જો સેટિંગ્સમાં બંધ હોય અને ફરજિયાત ચેક (જેમ કે ચાલુ કરતી વખતે વેરિફિકેશન) ન હોય તો સીધો પ્રવેશ આપવો
    if (!forceCheck && !isBiometricEnabledInSettings()) {
      return true;
    }

    try {
      final bool hasHardware = await isBiometricAvailable();
      if (!hasHardware) return true; // જો ફોનમાં ફિંગરપ્રિન્ટ હાર્ડવેર ન હોય તો અટકાવવું નહીં

      return await _auth.authenticate(
        localizedReason: 'નાણાકીય હિસાબો સુરક્ષિત રાખવા માટે ફિંગરપ્રિન્ટ અથવા સ્ક્રીન લૉક દાખલ કરો',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // ફિંગરપ્રિન્ટ ઉપરાંત ફોનનો PIN/Pattern પણ સ્વીકારશે
        ),
      );
    } catch (e) {
      return false;
    }
  }
}
