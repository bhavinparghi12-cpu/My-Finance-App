import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'security_service.dart';
import 'main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isFirstTime = false;
  bool _isLoading = true;
  bool _obscurePassword = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialState() async {
    final lastEmail = await SecurityService.getLastActiveEmail();
    if (lastEmail != null && lastEmail.isNotEmpty) {
      _emailController.text = lastEmail;
      final hasPwd = await SecurityService.isPasswordSetForEmail(lastEmail);
      setState(() {
        _isFirstTime = !hasPwd;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isFirstTime = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _onEmailChanged(String email) async {
    if (email.contains('@') && email.contains('.')) {
      final hasPwd = await SecurityService.isPasswordSetForEmail(email.trim());
      setState(() {
        _isFirstTime = !hasPwd;
        _errorMessage = '';
      });
    }
  }

  Future<void> _authenticate() async {
    final email = _emailController.text.trim().toLowerCase();
    final pwd = _passwordController.text;

    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'માન્ય ઈમેઈલ એડ્રેસ દાખલ કરો');
      return;
    }

    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'પાસવર્ડ ખાલી હોઈ શકે નહીં');
      return;
    }

    if (_isFirstTime) {
      await SecurityService.setupUserAccount(email, pwd);
      await _openUserDatabaseAndNavigate(email);
    } else {
      final isValid = await SecurityService.verifyPassword(email, pwd);
      if (isValid) {
        await SecurityService.setLastActiveEmail(email);
        await _openUserDatabaseAndNavigate(email);
      } else {
        setState(() {
          _errorMessage = 'ખોટો પાસવર્ડ! કૃપા કરીને ફરી પ્રયાસ કરો.';
          _passwordController.clear();
        });
      }
    }
  }

  Future<void> _resetPasswordWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: '821548105506-na4qjteh6kk0c87jb9n71qk65fl9gs45.apps.googleusercontent.com',
        scopes: ['email'],
      );
      final account = await googleSignIn.signIn();
      if (account == null) return;

      final currentEmail = _emailController.text.trim().toLowerCase();

      if (currentEmail.isNotEmpty && account.email.trim().toLowerCase() != currentEmail) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('અનધિકૃત એકાઉન્ટ! ફક્ત $currentEmail વડે જ પાસવર્ડ રીસેટ થઈ શકે.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      final newPwdController = TextEditingController();
      bool obscureNew = true;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDlgState) => AlertDialog(
            title: const Text('નવો માસ્ટર પાસવર્ડ સેટ કરો'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ચકાસાયેલ એકાઉન્ટ: ${account.email}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: newPwdController,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'નવો સુરક્ષિત પાસવર્ડ (કોઈપણ લંબાઈ)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDlgState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('રદ કરો')),
              ElevatedButton(
                onPressed: () async {
                  final newPwd = newPwdController.text;
                  if (newPwd.isNotEmpty) {
                    await SecurityService.resetPassword(account.email, newPwd);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('પાસવર્ડ સફળતાપૂર્વક બદલાઈ ગયો છે!')),
                      );
                    }
                  }
                },
                child: const Text('સેવ કરો'),
              ),
            ],
          ),
        ),
      );
      newPwdController.dispose();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google સાઈન-ઇન નિષ્ફળ: $e')),
        );
      }
    }
  }

  Future<void> _openUserDatabaseAndNavigate(String email) async {
    final encKey = await SecurityService.getDatabaseKeyForEmail(email);
    final cipher = HiveAesCipher(encKey);

    final prefix = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    final catBoxName = 'catBox_$prefix';
    final accBoxName = 'accBox_$prefix';
    final txBoxName = 'txBox_$prefix';

    if (!Hive.isBoxOpen(catBoxName)) {
      await Hive.openBox(catBoxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(accBoxName)) {
      await Hive.openBox(accBoxName, encryptionCipher: cipher);
    }
    if (!Hive.isBoxOpen(txBoxName)) {
      await Hive.openBox(txBoxName, encryptionCipher: cipher);
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            userEmail: email,
            catBoxName: catBoxName,
            accBoxName: accBoxName,
            txBoxName: txBoxName,
          ),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 26.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_outlined, size: 75, color: Colors.teal),
              const SizedBox(height: 12),
              Text(
                _isFirstTime ? 'નવું સુરક્ષિત એકાઉન્ટ બનાવો' : 'નાણાકીય વૉલ્ટ અનલૉક કરો',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _isFirstTime
                    ? 'તમારો ડેટા તમારા ચોક્કસ ઈમેઈલ અને AES-256 થી લોક રહેશે'
                    : 'પ્રવેશવા માટે તમારો માસ્ટર પાસવર્ડ દાખલ કરો',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                onChanged: _onEmailChanged,
                decoration: InputDecoration(
                  labelText: 'ગૂગલ / રિકવરી ઈમેઈલ એડ્રેસ',
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'માસ્ટર પાસવર્ડ (કોઈપણ કેરેક્ટર/લંબાઈ)',
                  hintText: 'દા.ત. P@ss#2026!xyz',
                  errorText: _errorMessage.isEmpty ? null : _errorMessage,
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _authenticate(),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _authenticate,
                icon: const Icon(Icons.lock_open),
                label: Text(_isFirstTime ? 'એકાઉન્ટ બનાવી પ્રવેશ કરો' : 'અનલૉક કરો'),
              ),
              if (!_isFirstTime) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _resetPasswordWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Google એકાઉન્ટ વડે પાસવર્ડ રીસેટ કરો'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
