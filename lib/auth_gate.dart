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
      if (!mounted) return;
      setState(() {
        _isFirstTime = !hasPwd;
        _isLoading = false;
      });
    } else {
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _isFirstTime = !hasPwd;
        _errorMessage = '';
      });
    }
  }

  Future<void> _authenticate() async {
    final email = _emailController.text.trim().toLowerCase();
    final pwd = _passwordController.text.trim();

    // સુધારેલ ઈમેઈલ અને પાસવર્ડ વેલિડેશન
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'માન્ય ઈમેઈલ એડ્રેસ દાખલ કરો.');
      return;
    }

    if (pwd.isEmpty) {
      setState(() => _errorMessage = 'પાસવર્ડ ખાલી હોઈ શકે નહીં.');
      return;
    }

    setState(() => _errorMessage = '');

    try {
      if (_isFirstTime) {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: pwd,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
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
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pwd,
        );

        await SecurityService.resetPassword(email, pwd);
        await SecurityService.setLastActiveEmail(email);
        await _openUserDatabaseAndNavigate(email);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
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
      final isValid = await SecurityService.verifyPassword(email, pwd);
      if (isValid) {
        await SecurityService.setLastActiveEmail(email);
        await _openUserDatabaseAndNavigate(email);
      } else {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'ખોટો પાસવર્ડ અથવા નેટવર્ક એરર.';
        });
      }
    }
  }

  Future<void> _sendResetPasswordLink() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('કૃપા કરીને પહેલાં માન્ય ઈમેઈલ એડ્રેસ દાખલ કરો.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.mark_email_read, color: Colors.teal),
              SizedBox(width: 8),
              Text('રીસેટ લિંક મોકલાઈ ગઈ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          content: Text(
            '$email પર પાસવર્ડ રીસેટ કરવાની લિંક મોકલી દેવાઈ છે.\nકૃપા કરીને તમારું Gmail/ઈમેઈલ (અથવા Spam ફોલ્ડર) તપાસો અને ત્યાં આપેલી લિંક પરથી નવો પાસવર્ડ બનાવો.',
            style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('સમજાઈ ગયું', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'લિંક મોકલવામાં ભૂલ આવી.';
      if (e.code == 'user-not-found') {
        msg = 'આ ઈમેઈલ પરનું એકાઉન્ટ મળ્યું નથી.';
      } else if (e.code == 'invalid-email') {
        msg = 'ઈમેઈલ એડ્રેસ અમાન્ય છે.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('એરર: $e', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      );
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

    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.teal)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100, // આછું બેકગ્રાઉન્ડ
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person_outlined, size: 75, color: Colors.teal),
              const SizedBox(height: 14),

              // ૧. મુખ્ય શીર્ષક - હંમેશા ઘાટું અને સ્પષ્ટ
              Text(
                _isFirstTime ? 'નવું સુરક્ષિત એકાઉન્ટ બનાવો' : 'નાણાકીય વૉલ્ટ અનલૉક કરો',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87, // કાળો રંગ જેથી ૧૦૦% સ્પષ્ટ દેખાય
                ),
              ),
              const SizedBox(height: 8),

              // ૨. સબટાઇટલ - ડાર્ક ગ્રે કલર
              Text(
                _isFirstTime
                    ? 'તમારો ડેટા તમારા મોબાઇલ ડિવાઇસ અને AES-256 થી લોક રહેશે'
                    : 'પ્રવેશવા માટે તમારો માસ્ટર પાસવર્ડ દાખલ કરો',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade800, // ઘાટો ગ્રે જેથી બેકગ્રાઉન્ડ સાથે ભળી ન જાય
                ),
              ),
              const SizedBox(height: 26),

              // ૩. ઈમેઈલ ઇનપુટ ફિલ્ડ
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
                onChanged: _onEmailChanged,
                decoration: InputDecoration(
                  labelText: 'ગૂગલ / રિકવરી ઈમેઈલ એડ્રેસ',
                  labelStyle: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                  prefixIcon: const Icon(Icons.email_outlined, color: Colors.teal),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade400, width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.teal, width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ૪. પાસવર્ડ ઇનપુટ ફિલ્ડ
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.visiblePassword,
                style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'માસ્ટર પાસવર્ડ',
                  labelStyle: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                  prefixIcon: const Icon(Icons.password, color: Colors.teal),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey.shade700,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  errorText: _errorMessage.isEmpty ? null : _errorMessage,
                  errorMaxLines: 2,
                  errorStyle: TextStyle(
                    color: Colors.red.shade800, // ડાર્ક લાલ કલર
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade400, width: 1.2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.teal, width: 1.8),
                  ),
                ),
                onSubmitted: (_) => _authenticate(),
              ),
              const SizedBox(height: 22),

              // ૫. અનલૉક / સેવ બટન
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _authenticate,
                  icon: const Icon(Icons.lock_open, color: Colors.white),
                  label: Text(
                    _isFirstTime ? 'એકાઉન્ટ બનાવો અને પ્રવેશ કરો' : 'અનલૉક કરો',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ૬. પાસવર્ડ ભૂલી ગયા છો લિંક
              if (!_isFirstTime)
                TextButton.icon(
                  onPressed: _sendResetPasswordLink,
                  icon: const Icon(Icons.lock_reset, size: 20, color: Colors.teal),
                  label: const Text(
                    'પાસવર્ડ ભૂલી ગયા છો? (લિંક વડે રીસેટ કરો)',
                    style: TextStyle(
                      color: Colors.teal,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),

              // ૭. મોડ સ્વિચ બટન
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
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade900, // સંપૂર્ણ ડાર્ક કલર
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
