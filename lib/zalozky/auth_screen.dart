import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // --- Krok 1: Přihlášení / Základní údaje ---
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _icoServisuController = TextEditingController();
  final _nazevServisuController = TextEditingController();
  final _mestoController = TextEditingController();
  final _adresaController = TextEditingController();
  final _telefonController = TextEditingController();

  // --- Krok 2: Průvodce nastavením ---
  final _sazbaController = TextEditingController();
  final _prefixController = TextEditingController(text: 'ZAK');

  bool _isLogin = true;
  bool _isLoading = false;
  bool _isLoadingAres = false;

  int _registerStep = 1; // Řídí kroky průvodce (1 = firma, 2 = nastavení)

  // --- Stažení dat z ARES ---
  Future<void> _fetchAresData() async {
    final ico = _icoServisuController.text.trim();
    if (ico.isEmpty || ico.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zadejte platné 8místné IČO.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoadingAres = true);

    try {
      final response = await http.get(
        Uri.parse(
          'https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/$ico',
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _nazevServisuController.text = data['obchodniJmeno'] ?? '';
          final sidlo = data['sidlo'] ?? {};
          _mestoController.text = sidlo['nazevObce'] ?? '';
          _adresaController.text = sidlo['textovaAdresa'] ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Údaje z ARES byly úspěšně načteny.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zadané IČO nebylo v registru ARES nalezeno.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při komunikaci s ARES: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoadingAres = false);
    }
  }

  // --- Přechod na druhý krok průvodce s kontrolami ---
  void _nextStep() {
    // 1. Kontrola, zda je vše vyplněno
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _confirmPasswordController.text.trim().isEmpty ||
        _icoServisuController.text.trim().isEmpty ||
        _nazevServisuController.text.trim().isEmpty ||
        _mestoController.text.trim().isEmpty ||
        _adresaController.text.trim().isEmpty ||
        _telefonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prosím vyplňte všechny povinné údaje o firmě.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. Kontrola, zda se hesla shodují
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zadaná hesla se neshodují. Zkuste to znovu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _registerStep = 2);
  }

  // --- Návrat na první krok průvodce ---
  void _prevStep() {
    setState(() => _registerStep = 1);
  }

  // --- NOVÉ: Obnova zapomenutého hesla ---
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zadejte prosím svůj e-mail nahoru do políčka a klikněte znovu.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Odkaz pro obnovu hesla byl odeslán na Váš e-mail.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při odesílání: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- Finální odeslání (Login nebo Krok 2 registrace) ---
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        // Obyčejné přihlášení
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // Registrace nového uživatele
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // Uložení VŠECH dat do Firestore
        await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(userCredential.user!.uid)
            .set({
              'email_servisu': email,
              'ico_servisu': _icoServisuController.text.trim(),
              'nazev_servisu': _nazevServisuController.text.trim(),
              'mesto_servisu': _mestoController.text.trim(),
              'adresa_servisu': _adresaController.text.trim(),
              'telefon_servisu': _telefonController.text.trim(),
              'hodinova_sazba':
                  double.tryParse(_sazbaController.text.replaceAll(',', '.')) ??
                  0.0,
              'prefix_zakazky': _prefixController.text.trim().isEmpty
                  ? 'ZAK'
                  : _prefixController.text.trim().toUpperCase(),
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
          padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 30),
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

                // --- VYKRESLENÍ PŘIHLAŠOVACÍHO FORMULÁŘE ---
                if (_isLogin) ...[
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

                  // NOVÉ: Tlačítko pro zapomenuté heslo
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: const Text(
                        'Zapomněli jste heslo?',
                        style: TextStyle(
                          color: Color(0xFF0061FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 15),
                  _buildMainButton(text: 'PŘIHLÁSIT SE', onPressed: _submit),
                ]
                // --- VYKRESLENÍ REGISTRACE - KROK 1 (Základní údaje) ---
                else if (!_isLogin && _registerStep == 1) ...[
                  const Text(
                    'Základní údaje o servisu',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  _buildAuthField(
                    controller: _icoServisuController,
                    labelText: 'IČO (Lupou stáhnete data)',
                    icon: Icons.numbers,
                    isDark: isDark,
                    isNumber: true,
                    customSuffix: _isLoadingAres
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search, color: Colors.blue),
                            onPressed: _fetchAresData,
                            tooltip: 'Hledat v ARES',
                          ),
                  ),
                  const SizedBox(height: 15),
                  _buildAuthField(
                    controller: _nazevServisuController,
                    labelText: 'Název servisu',
                    icon: Icons.business,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAuthField(
                          controller: _mestoController,
                          labelText: 'Město',
                          icon: Icons.location_city,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  _buildAuthField(
                    controller: _adresaController,
                    labelText: 'Ulice a č.p.',
                    icon: Icons.location_on,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 15),
                  _buildAuthField(
                    controller: _telefonController,
                    labelText: 'Telefon',
                    icon: Icons.phone,
                    isDark: isDark,
                    isNumber: true,
                  ),
                  const Divider(height: 40),
                  _buildAuthField(
                    controller: _emailController,
                    labelText: 'E-mail (pro přihlášení)',
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
                  const SizedBox(height: 15),
                  _buildAuthField(
                    controller: _confirmPasswordController,
                    labelText: 'Zopakujte heslo',
                    icon: Icons.lock_outline,
                    isDark: isDark,
                    isPassword: true,
                  ),

                  const SizedBox(height: 30),
                  _buildMainButton(text: 'POKRAČOVAT', onPressed: _nextStep),
                ]
                // --- VYKRESLENÍ REGISTRACE - KROK 2 (Průvodce nastavením) ---
                else if (!_isLogin && _registerStep == 2) ...[
                  const Text(
                    'Průvodce nastavením',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Tyto údaje můžete kdykoliv změnit v záložce Nastavení.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 30),

                  _buildAuthField(
                    controller: _sazbaController,
                    labelText: 'Hodinová sazba bez DPH (Kč)',
                    icon: Icons.attach_money,
                    isDark: isDark,
                    isNumber: true,
                  ),
                  const SizedBox(height: 20),
                  _buildAuthField(
                    controller: _prefixController,
                    labelText: 'Prefix číslování (např. ZAK)',
                    icon: Icons.abc,
                    isDark: isDark,
                    caps: true,
                  ),

                  const SizedBox(height: 30),
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: _prevStep,
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        padding: const EdgeInsets.all(18),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildMainButton(
                          text: 'DOKONČIT REGISTRACI',
                          onPressed: _submit,
                        ),
                      ),
                    ],
                  ),
                ],

                // --- PŘEPÍNAČ MEZI LOGIN A REGISTRACÍ ---
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                      _registerStep =
                          1; // Při přepnutí se vždy vrátíme na krok 1
                      // Pro jistotu vyčistíme hesla, aby tam nezůstala viset při přepínání oken
                      _passwordController.clear();
                      _confirmPasswordController.clear();
                    });
                  },
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

  // --- POMOCNÉ WIDGETY PRO ČISTŠÍ KÓD ---

  Widget _buildMainButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
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
            : Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
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
    bool caps = false,
    Widget? customSuffix,
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
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        textCapitalization: caps
            ? TextCapitalization.characters
            : TextCapitalization.none,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon, color: Colors.blue),
          suffixIcon: customSuffix,
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
