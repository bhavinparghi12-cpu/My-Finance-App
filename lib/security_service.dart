static Future<bool> verifyPin(String enteredPin) async {
  final storedHash = await _storage.read(key: _pinHashKey);
  if (storedHash == null) return false;

  final salt = await _storage.read(key: _saltKey);

  if (salt != null) {
    // નવો સુરક્ષિત રસ્તો (Dynamic Salt)
    final bytes = utf8.encode('$salt$enteredPin');
    final computedHash = sha256.convert(bytes).toString();
    return storedHash == computedHash;
  } else {
    // જૂનો રસ્તો (Legacy Support) - જૂના યુઝર માટે
    final bytes = utf8.encode('SECURE_SALT_FINANCE_$enteredPin');
    final computedHash = sha256.convert(bytes).toString();

    if (storedHash == computedHash) {
      // સફળ વેરિફિકેશન પછી આપોઆપ નવા ફોર્મેટમાં માઇગ્રેટ કરી દો
      await resetPin(enteredPin);
      return true;
    }
    return false;
  }
}
