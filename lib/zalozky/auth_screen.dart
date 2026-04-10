import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nazevServisuController = TextEditingController();
  final _icoServisuController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    if (!_isLogin) {
      if (_nazevServisuController.text.trim().isEmpty ||
          _icoServisuController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vyplňte prosím Název servisu i IČO.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(userCredential.user!.uid)
            .set({
              'nazev_servisu': _nazevServisuController.text.trim(),
              'ico_servisu': _icoServisuController.text.trim(),
              'hodinova_sazba': 0.0,
              'email_servisu': email,
            });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Chyba: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                const Icon(
                  Icons.car_repair,
                  color: Color(0xFF0061FF),
                  size: 80,
                ),
                const Text(
                  'VisTo',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 40),

                if (!_isLogin) ...[
                  _buildAuthField(
                    controller: _nazevServisuController,
                    labelText: 'Název servisu',
                    icon: Icons.business,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 15),
                  _buildAuthField(
                    controller: _icoServisuController,
                    labelText: 'IČO servisu',
                    icon: Icons.numbers,
                    isDark: isDark,
                    isNumber: true,
                  ),
                  const SizedBox(height: 15),
                ],

                _buildAuthField(
                  controller: _emailController,
                  labelText: 'E-mail',
                  icon: Icons.email,
                  isDark: isDark,
                ),
                const SizedBox(height: 15),
                _buildAuthField(
                  controller: _passwordController,
                  labelText: 'Heslo',
                  icon: Icons.lock,
                  isDark: isDark,
                  isPassword: true,
                ),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0061FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            _isLogin ? 'PŘIHLÁSIT SE' : 'ZAREGISTROVAT SERVIS',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? 'Nový servis? Vytvořit účet'
                        : 'Už máte účet? Přihlásit se',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    required bool isDark,
    bool isPassword = false,
    bool isNumber = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
        borderRadius: BorderRadius.circular(15),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon, color: Colors.blue),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}
