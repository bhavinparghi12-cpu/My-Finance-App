import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'security_service.dart';
import 'main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final TextEditingController _pinController = TextEditingController();
  bool _isFirstTime = false;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final hasPin = await SecurityService.isPinSet();
    setState(() {
      _isFirstTime = !hasPin;
      _isLoading = false;
    });
  }

  Future<void> _unlockApp() async {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _errorMessage = 'ઓછામાં ઓછો 4 આંકડાનો પિન દાખલ કરો');
      return;
    }

    if (_isFirstTime) {
      await SecurityService.setupPin(pin);
      await _openEncryptedDatabaseAndNavigate();
    } else {
      final isValid = await SecurityService.verifyPin(pin);
      if (isValid) {
        await _openEncryptedDatabaseAndNavigate();
      } else {
        setState(() {
          _errorMessage = 'ખોટો પાસવર્ડ! ફરી પ્રયાસ કરો.';
          _pinController.clear();
        });
      }
    }
  }

  Future<void> _openEncryptedDatabaseAndNavigate() async {
    final encKey = await SecurityService.getDatabaseKey();
    final cipher = HiveAesCipher(encKey);

    // ડેટાબેઝ AES-256 એન્ક્રિપ્શન સાથે ઓપન થશે
    await Hive.openBox('categoriesBox', encryptionCipher: cipher);
    await Hive.openBox('transactionsBox', encryptionCipher: cipher);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 80, color: Colors.teal),
              const SizedBox(height: 16),
              Text(
                _isFirstTime ? 'સુરક્ષિત માસ્ટર પિન બનાવો' : 'નાણાકીય વૉલ્ટ અનલૉક કરો',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isFirstTime
                    ? 'તમારો ડેટા AES-256 થી સુરક્ષિત થશે'
                    : 'એપ ખોલવા માટે તમારો ગુપ્ત પિન દાખલ કરો',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  errorText: _errorMessage.isEmpty ? null : _errorMessage,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _unlockApp(),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _unlockApp,
                icon: const Icon(Icons.lock_open),
                label: Text(_isFirstTime ? 'પિન સેવ કરી પ્રવેશ કરો' : 'અનલૉક કરો'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
