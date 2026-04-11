import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main_screen.dart';
import 'onboarding.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController(); // Pro registraci

  bool _isLogin = true; // Přepínač mezi Přihlášením a Registrací
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError('Zadejte prosím e-mail i heslo.');
      return;
    }

    if (!_isLogin && password != _confirmPasswordController.text.trim()) {
      _showError('Zadaná hesla se neshodují.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // --- LOGIKA PŘIHLÁŠENÍ ---
        final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Zkontrolujeme, zda uživatel prošel úvodním nastavením
        final doc = await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(userCredential.user!.uid)
            .get();

        if (mounted) {
          if (doc.exists && doc.data()?['prvni_spusteni_dokonceno'] == true) {
            // Vše má nastaveno, jde rovnou do aplikace
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainScreen()),
            );
          } else {
            // Nemá nastaveno, jde do Průvodce
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SetupWizardScreen()),
            );
          }
        }
      } else {
        // --- LOGIKA REGISTRACE ---
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (mounted) {
          // Nový uživatel jde VŽDY do Průvodce
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SetupWizardScreen()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Došlo k chybě při ověřování.';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Nesprávný e-mail nebo heslo.';
      } else if (e.code == 'email-already-in-use') {
        message = 'Tento e-mail je již zaregistrován.';
      } else if (e.code == 'weak-password') {
        message = 'Heslo je příliš slabé (min. 6 znaků).';
      } else if (e.code == 'invalid-email') {
        message = 'Neplatný formát e-mailu.';
      }
      _showError(message);
    } catch (e) {
      _showError('Neočekávaná chyba: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Pro obnovu hesla zadejte platný e-mail do horního políčka.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('E-mail pro obnovu hesla byl odeslán.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Chyba při odesílání e-mailu pro obnovu.');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LOGO A NÁZEV
                Icon(
                  Icons.car_repair,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 15),
                Text(
                  'VisTo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isLogin ? 'Přihlaste se do svého servisu' : 'Zaregistrujte svůj servis',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),

                // FORMULÁŘ
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildTextField(
                        controller: _emailController,
                        hint: 'E-mailová adresa',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 15),
                      _buildTextField(
                        controller: _passwordController,
                        hint: 'Heslo',
                        icon: Icons.lock_outline,
                        isPassword: true,
                        isDark: isDark,
                      ),
                      if (!_isLogin) ...[
                        const SizedBox(height: 15),
                        _buildTextField(
                          controller: _confirmPasswordController,
                          hint: 'Potvrzení hesla',
                          icon: Icons.lock_reset,
                          isPassword: true,
                          isDark: isDark,
                        ),
                      ],
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _resetPassword,
                            child: const Text('Zapomněli jste heslo?', style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // HLAVNÍ TLAČÍTKO
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                        )
                      : Text(
                          _isLogin ? 'PŘIHLÁSIT SE' : 'VYTVOŘIT ÚČET',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                ),
                const SizedBox(height: 20),

                // PŘEPÍNAČ LOGIN/REGISTRACE
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _emailController.clear();
                      _passwordController.clear();
                      _confirmPasswordController.clear();
                    });
                  },
                  child: RichText(
                    text: TextSpan(
                      text: _isLogin ? 'Nemáte ještě účet? ' : 'Již máte účet? ',
                      style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 15),
                      children: [
                        TextSpan(
                          text: _isLogin ? 'Zaregistrujte se' : 'Přihlaste se',
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    required bool isDark,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && _obscurePassword,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: Colors.blue),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );
  }
}