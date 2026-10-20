import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.contains('@') && cleanEmail.contains('.')) {
      final hasPwd = await SecurityService.isPasswordSetForEmail(cleanEmail);
      setState(() {
        _isFirstTime = !hasPwd;
        _errorMessage = '';
      });
    }
  }

  // --- ઓથેન્ટિકેશન ફંક્શન ---
  Future<void> _authenticate() async {
    final email = _emailController.text.trim().toLowerCase();
    final pwd = _passwordController.text.trim();

    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'માન્ય ઈમેઈલ એડ્રેસ દાખલ કરો');
      return;
    }

    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'પાસવર્ડ ખાલી હોઈ શકે નહીં');
      return;
    }

    setState(() => _errorMessage = '');

    try {
      if (_isFirstTime) {
        // ૧. નવું એકાઉન્ટ બનાવવાનો પ્રયત્ન
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: pwd,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // જો એકાઉન્ટ પહેલેથી હાજર હોય તો સાઇન-ઇન કરો
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email,
              password: pwd,
            );
          } else {
            rethrow;
          }
        }

        await SecurityService.setupUserAccount(email, pwd);
        await _openUserDatabaseAndNavigate(email);
      } else {
        // ૨. સીધું સાઇન-ઇન કરો
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pwd,
        );

        await SecurityService.resetPassword(email, pwd);
        await SecurityService.setLastActiveEmail(email);
        await _openUserDatabaseAndNavigate(email);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          _errorMessage = 'ખોટો પાસવર્ડ! કૃપા કરીને સાચો પાસવર્ડ નાખો અથવા નીચેથી રીસેટ કરો.';
        } else if (e.code == 'user-not-found') {
          _errorMessage = 'આ ઈમેઈલ વાળું એકાઉન્ટ મળ્યું નથી. નવું એકાઉન્ટ બનાવો.';
        } else if (e.code == 'network-request-failed') {
          _errorMessage = 'ઇન્ટરનેટ કનેક્શન તપાસો.';
        } else {
          _errorMessage = e.message ?? 'ઓથેન્ટિકેશન નિષ્ફળ.';
        }
      });
    } catch (e) {
      // ઑફલાઇન બેકઅપ તપાસ
      final isValid = await SecurityService.verifyPassword(email, pwd);
      if (isValid) {
        await SecurityService.setLastActiveEmail(email);
        await _openUserDatabaseAndNavigate(email);
      } else {
        setState(() {
          _errorMessage = 'ખોટો પાસવર્ડ અથવા કનેક્શન એરર.';
        });
      }
    }
  }

  // --- પાસવર્ડ રીસેટ લિંક મોકલવી ---
  Future<void> _sendResetPasswordLink() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('કૃપા કરીને પહેલાં માન્ય ઈમેઈલ એડ્રેસ દાખલ કરો.'),
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mark_email_read, color: Colors.teal),
              SizedBox(width: 8),
              Text('રીસેટ લિંક મોકલાઈ ગઈ', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Text(
            '$email પર પાસવર્ડ રીસેટ કરવાની લિંક મોકલી દેવાઈ છે.\n\nકૃપા કરીને તમારું Gmail/ઇનબોક્સ (અથવા Spam ફોલ્ડર) તપાસો અને ત્યાં આપેલી લિંક પર ક્લિક કરીને નવો પાસવર્ડ સેટ કરો.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('સમજાઈ ગયું'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'લિંક મોકલવામાં ભૂલ આવી.';
      if (e.code == 'user-not-found') {
        msg = 'આ ઈમેઈલ ધરાવતું કોઈ એકાઉન્ટ મળ્યું નથી.';
      } else if (e.code == 'invalid-email') {
        msg = 'ઈમેઈલ એડ્રેસ અમાન્ય છે.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('એરર: $e')),
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
                  labelText: 'માસ્ટર પાસવર્ડ',
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
              const SizedBox(height: 12),

              // 👈 અહીંથી શરત હટાવી દીધી છે, જેથી પ્રથમથી જ રીસેટ લિંકનું બટન હંમેશાં દેખાશે
              TextButton.icon(
                onPressed: _sendResetPasswordLink,
                icon: const Icon(Icons.lock_reset, size: 22, color: Colors.teal),
                label: const Text(
                  'પાસવર્ડ ભૂલી ગયા છો? (લિંક વડે રીસેટ કરો)',
                  style: TextStyle(
                    color: Colors.teal,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),

              // મોડ બદલવા માટેનો વિકલ્પ (નવું એકાઉન્ટ / સાઇન ઇન)
              TextButton(
                onPressed: () {
                  setState(() {
                    _isFirstTime = !_isFirstTime;
                    _errorMessage = '';
                  });
                },
                child: Text(
                  _isFirstTime
                      ? 'પહેલેથી એકાઉન્ટ છે? લૉગિન કરો'
                      : 'નવું એકાઉન્ટ બનાવવું છે? અહીં ક્લિક કરો',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
