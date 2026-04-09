import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Pro kIsWeb a ValueNotifier
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io'; // Pro práci se soubory na mobilu (File)
import 'package:intl/intl.dart'; // Pro formátování data
import 'dart:html' as html; // Pro stahování/otevírání fotek na webu
import 'dart:ui' as ui; // Pro práci s obrázky podpisu

// --- KNIHOVNY PRO ARES A PODPIS ---
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:signature/signature.dart'; // Podpisový arch

// --- KNIHOVNY PRO PDF EXPORT ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart'; // Pro sdílení/tisk PDF

// --- FIREBASE IMPORTY ---
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Přihlašování
import 'firebase_options.dart'; // Soubor generovaný FlutterFire CLI

// --- GLOBÁLNÍ KONSTANTY ---
const Map<String, dynamic> photoCategories = {
  'karoserie': {
    'label': 'Karoserie (celkový pohled)',
    'icon': Icons.directions_car_rounded,
  },
  'disky': {'label': 'Disky a kola', 'icon': Icons.tire_repair_rounded},
  'sklo': {'label': 'Čelní sklo', 'icon': Icons.branding_watermark_rounded},
  'nadrz': {'label': 'Stav nádrže', 'icon': Icons.local_gas_station_rounded},
  'tachometr': {
    'label': 'Tachometr (ujetá vzdálenost)',
    'icon': Icons.speed_rounded,
  },
  'stk': {'label': 'Nálepka STK', 'icon': Icons.check_circle_outline_rounded},
};

// --- STAVY ZAKÁZKY ---
const List<String> stavyZakazky = [
  'Přijato',
  'V opravě',
  'Čeká na díly',
  'K vyzvednutí',
  'Dokončeno',
];

Color getStatusColor(String stav) {
  switch (stav) {
    case 'Přijato':
      return Colors.blue;
    case 'V opravě':
      return Colors.orange;
    case 'Čeká na díly':
      return Colors.redAccent;
    case 'K vyzvednutí':
      return Colors.purple;
    case 'Dokončeno':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// --- TŘÍDA PRO DÍLY ---
class DilInput {
  final cislo = TextEditingController();
  final nazev = TextEditingController();
  final pocet = TextEditingController(text: '1');
  final cenaBezDph = TextEditingController();
  final cenaSDph = TextEditingController();

  void dispose() {
    cislo.dispose();
    nazev.dispose();
    pocet.dispose();
    cenaBezDph.dispose();
    cenaSDph.dispose();
  }
}

// --- GLOBÁLNÍ STAV ---
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VistoApp());
}

// ==============================================================================
// HLAVNÍ APLIKACE A NASTAVENÍ TÉMATU
// ==============================================================================

class VistoApp extends StatelessWidget {
  const VistoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Visto',
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0061FF),
              primary: const Color(0xFF0061FF),
              surface: const Color(0xFFFBFDFF),
            ),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              brightness: Brightness.dark,
              seedColor: const Color(0xFF4D94FF),
              primary: const Color(0xFF4D94FF),
              surface: const Color(0xFF121212),
            ),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          themeMode: currentMode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasData) {
                return const MainScreen();
              }
              return const AuthScreen();
            },
          ),
        );
      },
    );
  }
}

// ==============================================================================
// AUTH SCREEN (LOGIN / REGISTRACE)
// ==============================================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // NOVÉ: Políčka pro registraci
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
        // Registrace
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        // Uložení nastavení servisu
        await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(userCredential.user!.uid)
            .set({
              'nazev_servisu': _nazevServisuController.text.trim(),
              'ico_servisu': _icoServisuController.text.trim(),
              'hodinova_sazba': 0.0, // Výchozí sazba
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
                const Icon(Icons.bolt, color: Color(0xFF0061FF), size: 80),
                const Text(
                  'Visto',
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Zobrazení polí navíc při registraci
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

// ==============================================================================
// HLAVNÍ OBRAZOVKA S NAVIGACÍ
// ==============================================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // NOVÉ: Přidána záložka Nastavení
  final List<Widget> _pages = [
    const MainWizardPage(),
    const ServiceProgressPage(),
    const HistoryPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 4),
              Text(
                'Visto',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.amber : Colors.black54,
            ),
            onPressed: () =>
                themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Příjem',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_circle_outlined),
            selectedIcon: Icon(Icons.build_circle),
            label: 'Průběh',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historie',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Nastavení',
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// NOVÉ: STRÁNKA NASTAVENÍ (PROFIL SERVISU)
// ==============================================================================

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nazevController = TextEditingController();
  final _icoController = TextEditingController();
  final _sazbaController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _nazevController.text = data['nazev_servisu'] ?? '';
        _icoController.text = data['ico_servisu'] ?? '';
        _sazbaController.text = (data['hodinova_sazba'] ?? 0.0).toString();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(user.uid)
            .set({
              'nazev_servisu': _nazevController.text.trim(),
              'ico_servisu': _icoController.text.trim(),
              'hodinova_sazba':
                  double.tryParse(_sazbaController.text.replaceAll(',', '.')) ??
                  0.0,
            }, SetOptions(merge: true));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nastavení úspěšně uloženo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při ukládání: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nastavení servisu',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Přihlášen jako: ${user?.email ?? "Neznámý uživatel"}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          _buildSettingsInput(
            'Název servisu (Zobrazí se v PDF)',
            Icons.business,
            _nazevController,
            isDark,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'IČO servisu (Zobrazí se v PDF)',
            Icons.numbers,
            _icoController,
            isDark,
            isNumber: true,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'Hodinová sazba bez DPH (Kč)',
            Icons.attach_money,
            _sazbaController,
            isDark,
            isNumber: true,
          ),

          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ULOŽIT NASTAVENÍ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),

          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Odhlásit se',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsInput(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isDark, {
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
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
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
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
        ),
      ],
    );
  }
}

// ==============================================================================
// STRÁNKA PRŮVODCE NOVÝM PŘÍJMEM
// ==============================================================================

class MainWizardPage extends StatefulWidget {
  const MainWizardPage({super.key});
  @override
  State<MainWizardPage> createState() => _MainWizardPageState();
}

class _MainWizardPageState extends State<MainWizardPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 5;
  bool _isUploading = false;
  bool _isLoadingAres = false;

  // --- Zákazník ---
  final _jmenoController = TextEditingController();
  final _icoController = TextEditingController();
  final _adresaController = TextEditingController();
  final _telefonController = TextEditingController();
  final _emailZController = TextEditingController();

  String? _vybranyZakaznikId;
  List<Map<String, dynamic>> _nalezenaVozidla = [];

  // --- Vozidlo ---
  final _zakazkaController = TextEditingController();
  final _spzController = TextEditingController();
  final _vinController = TextEditingController();
  final _motorizaceController = TextEditingController();
  final _poznamkyController = TextEditingController();
  final _znackaController = TextEditingController();
  final _modelController = TextEditingController();
  final _rokVyrobyController = TextEditingController();

  String _vybranePalivo = 'Benzín';
  final List<String> _moznostiPaliva = [
    'Benzín',
    'Nafta',
    'Elektro',
    'Hybrid',
    'LPG/CNG',
    'Jiné',
  ];

  String _vybranaPrevodovka = 'Manuální';
  final List<String> _moznostiPrevodovky = ['Manuální', 'Automatická', 'Jiné'];

  final Map<String, List<XFile>> _categoryImages = {};
  final ImagePicker _picker = ImagePicker();

  final List<String> _vybranePoskozeni = [];
  final List<String> _poskozeniMoznosti = [
    'Žádné',
    'Čelní sklo',
    'Stěrače',
    'Disky',
    'Karosérie',
  ];

  final _tachometrController = TextEditingController();
  double _stavNadrze = 50.0;

  final _stkMesicController = TextEditingController();
  final _stkRokController = TextEditingController();

  final _pneuLPController = TextEditingController();
  final _pneuPPController = TextEditingController();
  final _pneuLZController = TextEditingController();
  final _pneuPZController = TextEditingController();

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _fetchAresData() async {
    final ico = _icoController.text.trim();
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
          _jmenoController.text = data['obchodniJmeno'] ?? '';
          final sidlo = data['sidlo'] ?? {};
          final ulice = sidlo['textovaAdresa'] ?? '';
          _adresaController.text = ulice;
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

  void _otevritVyberZakaznika() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VyberZakaznikaSheet(
        onVybrano: (zakaznik) async {
          setState(() {
            _vybranyZakaznikId = zakaznik['id_zakaznika'];
            _jmenoController.text = zakaznik['jmeno'] ?? '';
            _icoController.text = zakaznik['ico'] ?? '';
            _adresaController.text = zakaznik['adresa'] ?? '';
            _telefonController.text = zakaznik['telefon'] ?? '';
            _emailZController.text = zakaznik['email'] ?? '';
          });

          final user = FirebaseAuth.instance.currentUser;
          if (user != null && _vybranyZakaznikId != null) {
            final vozidlaSnap = await FirebaseFirestore.instance
                .collection('vozidla')
                .where('servis_id', isEqualTo: user.uid)
                .where('zakaznik_id', isEqualTo: _vybranyZakaznikId)
                .get();
            setState(() {
              _nalezenaVozidla = vozidlaSnap.docs
                  .map((d) => d.data() as Map<String, dynamic>)
                  .toList();
            });
          }
        },
      ),
    );
  }

  void _moveNext() {
    FocusScope.of(context).unfocus();

    if (_currentPage == 1) {
      if (_zakazkaController.text.trim().isEmpty ||
          _spzController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Číslo zakázky a SPZ jsou povinné údaje!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    if (_currentPage == _totalPages - 1) {
      if (_signatureController.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zákazník musí připojit podpis před odesláním.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      _startDirectUpload();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _moveBack() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _startDirectUpload() async {
    setState(() => _isUploading = true);
    try {
      await _uploadToFirebase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zakázka úspěšně odeslána'),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při odesílání: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Nejste přihlášeni!');

    final Map<String, List<String>> imageUrlsByCategory = {};
    String zakazkaId = _zakazkaController.text.trim().isEmpty
        ? 'ID_${DateTime.now().millisecondsSinceEpoch}'
        : _zakazkaController.text.trim();

    for (var entry in _categoryImages.entries) {
      final categoryKey = entry.key;
      final images = entry.value;

      imageUrlsByCategory[categoryKey] = [];

      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        String fileName =
            '${categoryKey}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        Reference ref = FirebaseStorage.instance.ref().child(
          'servisy/${user.uid}/zakazky/$zakazkaId/$fileName',
        );
        await ref.putData(await image.readAsBytes());
        String downloadUrl = await ref.getDownloadURL();
        imageUrlsByCategory[categoryKey]!.add(downloadUrl);
      }
    }

    String? podpisUrl;
    if (_signatureController.isNotEmpty) {
      final Uint8List? signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes != null) {
        Reference ref = FirebaseStorage.instance.ref().child(
          'servisy/${user.uid}/zakazky/$zakazkaId/podpis_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await ref.putData(signatureBytes);
        podpisUrl = await ref.getDownloadURL();
      }
    }

    String zakaznikId =
        _vybranyZakaznikId ?? 'ZAK_${DateTime.now().millisecondsSinceEpoch}';
    if (_jmenoController.text.trim().isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('zakaznici')
          .doc('${user.uid}_$zakaznikId')
          .set({
            'servis_id': user.uid,
            'id_zakaznika': zakaznikId,
            'jmeno': _jmenoController.text.trim(),
            'ico': _icoController.text.trim(),
            'adresa': _adresaController.text.trim(),
            'telefon': _telefonController.text.trim(),
            'email': _emailZController.text.trim(),
            'posledni_navsteva': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }

    String spz = _spzController.text.trim().toUpperCase();
    if (spz.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('vozidla')
          .doc('${user.uid}_$spz')
          .set({
            'servis_id': user.uid,
            'zakaznik_id': zakaznikId,
            'spz': spz,
            'vin': _vinController.text.trim().toUpperCase(),
            'znacka': _znackaController.text.trim(),
            'model': _modelController.text.trim(),
            'rok_vyroby': _rokVyrobyController.text.trim(),
            'motorizace': _motorizaceController.text.trim(),
            'palivo': _vybranePalivo,
            'prevodovka': _vybranaPrevodovka,
            'posledni_navsteva': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }

    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc('${user.uid}_$zakazkaId')
        .set({
          'servis_id': user.uid,
          'cislo_zakazky': zakazkaId,
          'spz': spz,
          'vin': _vinController.text.trim().toUpperCase(),
          'znacka': _znackaController.text.trim(),
          'model': _modelController.text.trim(),
          'rok_vyroby': _rokVyrobyController.text.trim(),
          'motorizace': _motorizaceController.text.trim(),
          'palivo_typ': _vybranePalivo,
          'prevodovka': _vybranaPrevodovka,
          'stav_zakazky': 'Přijato',
          'zakaznik': {
            'id_zakaznika': zakaznikId,
            'jmeno': _jmenoController.text.trim(),
            'ico': _icoController.text.trim(),
            'adresa': _adresaController.text.trim(),
            'telefon': _telefonController.text.trim(),
            'email': _emailZController.text.trim(),
          },
          'stav_vozidla': {
            'tachometr': _tachometrController.text.trim(),
            'nadrz': _stavNadrze,
            'poskozeni': _vybranePoskozeni.isEmpty
                ? ['Neuvedeno']
                : _vybranePoskozeni,
            'stk_mesic': _stkMesicController.text.trim(),
            'stk_rok': _stkRokController.text.trim(),
            'pneu_lp': _pneuLPController.text.trim(),
            'pneu_pp': _pneuPPController.text.trim(),
            'pneu_lz': _pneuLZController.text.trim(),
            'pneu_pz': _pneuPZController.text.trim(),
          },
          'poznamky': _poznamkyController.text.trim(),
          'fotografie_urls': imageUrlsByCategory,
          'podpis_url': podpisUrl,
          'provedene_prace': [],
          'cas_prijeti': FieldValue.serverTimestamp(),
        });
  }

  void _resetForm() {
    _jmenoController.clear();
    _icoController.clear();
    _adresaController.clear();
    _telefonController.clear();
    _emailZController.clear();
    _vybranyZakaznikId = null;
    _nalezenaVozidla.clear();

    _zakazkaController.clear();
    _spzController.clear();
    _vinController.clear();
    _znackaController.clear();
    _modelController.clear();
    _rokVyrobyController.clear();
    _motorizaceController.clear();
    _vybranePalivo = 'Benzín';
    _vybranaPrevodovka = 'Manuální';
    _poznamkyController.clear();
    _categoryImages.clear();
    _vybranePoskozeni.clear();
    _stkMesicController.clear();
    _stkRokController.clear();
    _pneuLPController.clear();
    _pneuPPController.clear();
    _pneuLZController.clear();
    _pneuPZController.clear();

    _tachometrController.clear();
    _stavNadrze = 50.0;
    _signatureController.clear();

    setState(() => _currentPage = 0);
    _pageController.jumpToPage(0);
  }

  Future<void> _takePhotoSeries(String categoryKey) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sériové focení zapnuto. Foťák se bude otevírat, dokud nedáte "Zpět/Zrušit".',
        ),
        duration: Duration(seconds: 3),
      ),
    );

    while (true) {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 60,
        maxWidth: 1280,
        maxHeight: 1280,
      );

      if (photo != null) {
        setState(() {
          if (_categoryImages[categoryKey] == null)
            _categoryImages[categoryKey] = [];
          _categoryImages[categoryKey]!.add(photo);
        });
      } else {
        break;
      }
    }
  }

  Future<void> _pickFromGallery(String categoryKey) async {
    final List<XFile> photos = await _picker.pickMultiImage(
      imageQuality: 60,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (photos.isNotEmpty) {
      setState(() {
        if (_categoryImages[categoryKey] == null)
          _categoryImages[categoryKey] = [];
        _categoryImages[categoryKey]!.addAll(photos);
      });
    }
  }

  Future<void> _scanText(
    TextEditingController controller,
    bool numbersOnly,
  ) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Skenování pomocí AI funguje pouze v nainstalované aplikaci (APK/iOS), nikoliv v prohlížeči.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;
      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final recognizedText = await textRecognizer.processImage(inputImage);
      String result = recognizedText.text;

      if (numbersOnly) {
        result = result.replaceAll(RegExp(r'[^0-9]'), '');
      } else {
        result = result.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
      }

      setState(() => controller.text = result);
      textRecognizer.close();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba skenování: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildZakaznikStep(isDark),
                  _buildVozidloStep(isDark),
                  _buildPhotoStep(isDark),
                  _buildCheckStep(isDark),
                  _buildPodpisStep(isDark),
                ],
              ),
            ),
            _buildBottomPanel(isDark),
          ],
        ),
        if (_isUploading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Card(
                elevation: 10,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text(
                        'Odesílám zakázku...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildZakaznikStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Údaje o zákazníkovi',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),

        _buildInput(
          'Jméno a příjmení / Název firmy',
          Icons.person,
          _jmenoController,
          isDark,
          customSuffix: IconButton(
            icon: const Icon(Icons.person_search, color: Colors.blue),
            onPressed: _otevritVyberZakaznika,
            tooltip: 'Hledat uloženého zákazníka',
          ),
        ),
        const SizedBox(height: 20),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'IČO (ARES vyhledávání)',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
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
                controller: _icoController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.business, color: Colors.blue),
                  suffixIcon: _isLoadingAres
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
            ),
          ],
        ),

        const SizedBox(height: 20),
        _buildInput('Adresa', Icons.location_on, _adresaController, isDark),
        const SizedBox(height: 20),
        _buildInput(
          'Telefonní číslo',
          Icons.phone,
          _telefonController,
          isDark,
          numbersOnly: true,
        ),
        const SizedBox(height: 20),
        _buildInput('E-mail', Icons.email, _emailZController, isDark),

        if (_nalezenaVozidla.isNotEmpty) ...[
          const SizedBox(height: 30),
          const Divider(),
          const SizedBox(height: 15),
          const Text(
            'Uložená vozidla zákazníka:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _nalezenaVozidla
                .map(
                  (v) => ActionChip(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.blue),
                    label: Text(
                      '${v['spz']} ${v['znacka'] != null && v['znacka'].toString().isNotEmpty ? '(${v['znacka']} ${v['model'] ?? ''})' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    avatar: const Icon(
                      Icons.directions_car,
                      color: Colors.blue,
                      size: 16,
                    ),
                    onPressed: () {
                      setState(() {
                        _spzController.text = v['spz'] ?? '';
                        _vinController.text = v['vin'] ?? '';
                        _znackaController.text = v['znacka'] ?? '';
                        _modelController.text = v['model'] ?? '';
                        _rokVyrobyController.text = v['rok_vyroby'] ?? '';
                        _motorizaceController.text = v['motorizace'] ?? '';
                        if (v['palivo'] != null &&
                            _moznostiPaliva.contains(v['palivo']))
                          _vybranePalivo = v['palivo'];
                        if (v['prevodovka'] != null &&
                            _moznostiPrevodovky.contains(v['prevodovka']))
                          _vybranaPrevodovka = v['prevodovka'];
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Údaje o vozidle byly doplněny.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ],
    ),
  );

  Widget _buildVozidloStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Údaje o vozidle',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),
        _buildInput(
          'Číslo zakázky *',
          Icons.onetwothree,
          _zakazkaController,
          isDark,
          caps: true,
        ),
        const SizedBox(height: 20),
        _buildInput(
          'SPZ vozidla *',
          Icons.abc,
          _spzController,
          isDark,
          caps: true,
        ),
        const SizedBox(height: 20),
        _buildInput('VIN kód', Icons.abc, _vinController, isDark, caps: true),
        const SizedBox(height: 20),
        _buildInput(
          'Značka (např. Škoda)',
          Icons.directions_car,
          _znackaController,
          isDark,
        ),
        const SizedBox(height: 20),
        _buildInput(
          'Model (např. Octavia)',
          Icons.directions_car_filled,
          _modelController,
          isDark,
        ),
        const SizedBox(height: 20),
        _buildInput(
          'Rok výroby',
          Icons.calendar_today,
          _rokVyrobyController,
          isDark,
          numbersOnly: true,
        ),
        const SizedBox(height: 20),
        _buildInput(
          'Motorizace (např. 2.0 TDI)',
          Icons.settings,
          _motorizaceController,
          isDark,
        ),
        const SizedBox(height: 20),
        _buildDropdown(
          'Typ paliva',
          Icons.local_gas_station,
          _vybranePalivo,
          _moznostiPaliva,
          (v) => setState(() => _vybranePalivo = v!),
          isDark,
        ),
        const SizedBox(height: 20),
        _buildDropdown(
          'Převodovka',
          Icons.settings_input_component,
          _vybranaPrevodovka,
          _moznostiPrevodovky,
          (v) => setState(() => _vybranaPrevodovka = v!),
          isDark,
        ),
      ],
    ),
  );

  Widget _buildPhotoStep(bool isDark) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fotodokumentace',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          'Vyfoťte sérii fotek, nebo vyberte hromadně z galerie.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            itemCount: photoCategories.length,
            separatorBuilder: (context, index) => const SizedBox(height: 15),
            itemBuilder: (context, index) {
              final key = photoCategories.keys.elementAt(index);
              final category = photoCategories[key];
              final label = category['label'] as String;
              final icon = category['icon'] as IconData;
              final takenPhotos = _categoryImages[key] ?? [];

              return Card(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: takenPhotos.isNotEmpty
                        ? Colors.green.withOpacity(0.5)
                        : Colors.grey.withOpacity(0.2),
                    width: takenPhotos.isNotEmpty ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: Colors.blue, size: 30),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _pickFromGallery(key),
                            icon: const Icon(
                              Icons.photo_library_rounded,
                              color: Colors.blueGrey,
                            ),
                            tooltip: 'Přidat z galerie',
                          ),
                          IconButton(
                            onPressed: () => _takePhotoSeries(key),
                            icon: const Icon(
                              Icons.add_a_photo_rounded,
                              color: Colors.blue,
                            ),
                            tooltip: 'Sériové focení',
                          ),
                        ],
                      ),
                      if (takenPhotos.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: takenPhotos.length,
                            itemBuilder: (context, photoIndex) {
                              final photo = takenPhotos[photoIndex];
                              return Stack(
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: kIsWeb
                                          ? Image.network(
                                              photo.path,
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.file(
                                              File(photo.path),
                                              width: 80,
                                              height: 80,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 14,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _categoryImages[key]!.removeAt(
                                          photoIndex,
                                        ),
                                      ),
                                      child: const CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.white,
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildCheckStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stav vozidla',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 30),

        _buildInput(
          'Stav tachometru (km)',
          Icons.speed,
          _tachometrController,
          isDark,
          numbersOnly: true,
        ),
        const SizedBox(height: 25),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stav paliva v nádrži (${_stavNadrze.toInt()} %)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.local_gas_station,
                    color: _stavNadrze < 20 ? Colors.red : Colors.blue,
                  ),
                  Expanded(
                    child: Slider(
                      value: _stavNadrze,
                      min: 0,
                      max: 100,
                      divisions: 4,
                      label: '${_stavNadrze.toInt()} %',
                      activeColor: Colors.blue,
                      onChanged: (val) => setState(() => _stavNadrze = val),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        const Divider(),
        const SizedBox(height: 20),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Zjištěné poškození (lze vybrat více)',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
                border: Border.all(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 15),
                    child: Icon(Icons.car_crash, color: Colors.blue),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _poskozeniMoznosti.map((String value) {
                        final isSelected = _vybranePoskozeni.contains(value);
                        return FilterChip(
                          label: Text(value),
                          selected: isSelected,
                          onSelected: (bool selected) {
                            setState(() {
                              if (value == 'Žádné') {
                                if (selected) {
                                  _vybranePoskozeni.clear();
                                  _vybranePoskozeni.add('Žádné');
                                } else {
                                  _vybranePoskozeni.remove('Žádné');
                                }
                              } else {
                                if (selected) {
                                  _vybranePoskozeni.remove('Žádné');
                                  _vybranePoskozeni.add(value);
                                } else {
                                  _vybranePoskozeni.remove(value);
                                }
                              }
                            });
                          },
                          selectedColor: Colors.blue.withOpacity(0.2),
                          checkmarkColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSelected
                                  ? Colors.blue
                                  : (isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[300]!),
                            ),
                          ),
                          backgroundColor: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey[50],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platnost STK',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildHalfInput(
                    'Měsíc',
                    Icons.calendar_month,
                    _stkMesicController,
                    isDark,
                    TextInputType.number,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildHalfInput(
                    'Rok',
                    Icons.edit_calendar,
                    _stkRokController,
                    isDark,
                    TextInputType.number,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 25),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hloubka dezénu pneu (v mm)',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildHalfInput(
                    'Levá př.',
                    Icons.tire_repair,
                    _pneuLPController,
                    isDark,
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildHalfInput(
                    'Pravá př.',
                    Icons.tire_repair,
                    _pneuPPController,
                    isDark,
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: _buildHalfInput(
                    'Levá zad.',
                    Icons.tire_repair,
                    _pneuLZController,
                    isDark,
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildHalfInput(
                    'Pravá zad.',
                    Icons.tire_repair,
                    _pneuPZController,
                    isDark,
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dodatečné poznámky',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
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
                controller: _poznamkyController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Poznámky...',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Icon(Icons.notes, color: Colors.blue),
                  ),
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
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildPodpisStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Shrnutí a podpis',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          'Zákazník svým podpisem stvrzuje správnost výše uvedených údajů a souhlasí se stavem vozidla při převzetí do servisu.',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
        const SizedBox(height: 30),

        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
            borderRadius: BorderRadius.circular(15),
            color: Colors.white,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Signature(
              controller: _signatureController,
              height: 250,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _signatureController.clear(),
            icon: const Icon(Icons.clear, color: Colors.red),
            label: const Text(
              'Smazat podpis',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildBottomPanel(bool isDark) => Container(
    padding: const EdgeInsets.fromLTRB(30, 20, 30, 30),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF121212) : Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10,
          offset: const Offset(0, -5),
        ),
      ],
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: List.generate(
              _totalPages,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index <= _currentPage
                        ? Colors.blue
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (_currentPage > 0)
                IconButton.filledTonal(
                  onPressed: _moveBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  padding: const EdgeInsets.all(15),
                ),
              if (_currentPage > 0) const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: _moveNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _currentPage == _totalPages - 1
                        ? 'DOKONČIT A ODESLAT'
                        : 'DALŠÍ KROK',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildInput(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isDark, {
    bool caps = false,
    bool numbersOnly = false,
    Widget? customSuffix,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      Container(
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
          textCapitalization: caps
              ? TextCapitalization.characters
              : TextCapitalization.none,
          keyboardType: numbersOnly ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.blue),
            suffixIcon:
                customSuffix ??
                IconButton(
                  icon: const Icon(Icons.document_scanner),
                  onPressed: () => _scanText(controller, numbersOnly),
                ),
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
      ),
    ],
  );

  Widget _buildDropdown(
    String label,
    IconData icon,
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Container(
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
          child: DropdownButtonFormField<String>(
            value: value,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onChanged,
            decoration: InputDecoration(
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
        ),
      ],
    );
  }

  Widget _buildHalfInput(
    String hint,
    IconData icon,
    TextEditingController controller,
    bool isDark,
    TextInputType type,
  ) {
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
        keyboardType: type,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.blue, size: 20),
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
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}

// --- VYHLEDÁVÁNÍ ZÁKAZNÍKA (BOTTOM SHEET) ---
class _VyberZakaznikaSheet extends StatefulWidget {
  final Function(Map<String, dynamic>) onVybrano;

  const _VyberZakaznikaSheet({required this.onVybrano});

  @override
  State<_VyberZakaznikaSheet> createState() => _VyberZakaznikaSheetState();
}

class _VyberZakaznikaSheetState extends State<_VyberZakaznikaSheet> {
  String _hledanyText = '';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Vybrat existujícího zákazníka',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          TextField(
            onChanged: (val) =>
                setState(() => _hledanyText = val.toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Hledat podle jména, IČO, telefonu...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('zakaznici')
                  .where('servis_id', isEqualTo: user?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                final zakaznici = snapshot.data!.docs
                    .map((d) => d.data() as Map<String, dynamic>)
                    .where((z) {
                      final jmeno = (z['jmeno'] ?? '').toString().toLowerCase();
                      final ico = (z['ico'] ?? '').toString().toLowerCase();
                      final tel = (z['telefon'] ?? '').toString().toLowerCase();
                      return jmeno.contains(_hledanyText) ||
                          ico.contains(_hledanyText) ||
                          tel.contains(_hledanyText);
                    })
                    .toList();

                if (zakaznici.isEmpty)
                  return const Center(child: Text('Žádný zákazník nenalezen.'));

                return ListView.separated(
                  itemCount: zakaznici.length,
                  separatorBuilder: (c, i) => const Divider(),
                  itemBuilder: (context, index) {
                    final z = zakaznici[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(
                        z['jmeno'] ?? 'Neznámé jméno',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${z['telefon'] ?? ''} ${z['ico'] != null && z['ico'].toString().isNotEmpty ? '• IČO: ${z['ico']}' : ''}',
                      ),
                      onTap: () {
                        widget.onVybrano(z);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==============================================================================
// STRÁNKA "PRŮBĚH SERVISU"
// ==============================================================================

class ServiceProgressPage extends StatefulWidget {
  const ServiceProgressPage({super.key});

  @override
  State<ServiceProgressPage> createState() => _ServiceProgressPageState();
}

class _ServiceProgressPageState extends State<ServiceProgressPage> {
  String _searchQuery = '';

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return const Center(child: Text("Nejste přihlášeni."));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Průběh servisu',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Aktivní zakázky v řešení.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 15),
              Container(
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
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Hledat SPZ, VIN nebo číslo...',
                    prefixIcon: const Icon(Icons.search, color: Colors.blue),
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
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('zakazky')
                .where('servis_id', isEqualTo: user.uid)
                .orderBy('cas_prijeti', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                if (data['stav_zakazky'] == 'Dokončeno') return false;

                final cislo =
                    data['cislo_zakazky']?.toString().toLowerCase() ?? '';
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final vin = data['vin']?.toString().toLowerCase() ?? '';
                return cislo.contains(_searchQuery) ||
                    spz.contains(_searchQuery) ||
                    vin.contains(_searchQuery);
              }).toList();

              if (docs.isEmpty)
                return const Center(
                  child: Text('Žádné aktivní zakázky k zobrazení.'),
                );

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;
                  final stav = data['stav_zakazky'] ?? 'Přijato';

                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${data['spz']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: getStatusColor(stav).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: getStatusColor(stav)),
                            ),
                            child: Text(
                              stav,
                              style: TextStyle(
                                color: getStatusColor(stav),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Zakázka: ${data['cislo_zakazky']}' +
                              (data['znacka'] != null &&
                                      data['znacka'].toString().isNotEmpty
                                  ? '\n${data['znacka']} ${data['model'] ?? ''}'
                                  : '') +
                              '\nČas příjmu: ${_formatDate(data['cas_prijeti'])}',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ActiveJobScreen(
                            documentId: docId,
                            zakazkaId: data['cislo_zakazky'].toString(),
                            spz: data['spz'].toString(),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// OBRAZOVKA PRO PŘIDÁVÁNÍ ÚKONŮ A ZMĚNU STAVU
// ==============================================================================

class ActiveJobScreen extends StatelessWidget {
  final String documentId;
  final String zakazkaId;
  final String spz;

  const ActiveJobScreen({
    super.key,
    required this.documentId,
    required this.zakazkaId,
    required this.spz,
  });

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  void _openAddWorkDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _AddWorkSheet(documentId: documentId, zakazkaId: zakazkaId),
    );
  }

  Future<void> _deleteWork(
    BuildContext context,
    Map<String, dynamic> workItem,
  ) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat úkon?'),
        content: const Text(
          'Opravdu chcete tento záznam o práci odstranit? Tato akce je nevratná.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ZRUŠIT'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SMAZAT', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('zakazky')
          .doc(documentId)
          .update({
            'provedene_prace': FieldValue.arrayRemove([workItem]),
          });
    }
  }

  Future<void> _zmenitStav(BuildContext context, String novyStav) async {
    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc(documentId)
        .update({'stav_zakazky': novyStav});
    if (novyStav == 'Dokončeno') {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zakázka přesunuta do Historie.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  pw.Widget _buildCompactRow(
    String label1,
    String value1,
    String label2,
    String value2,
    pw.Font fontReg,
    pw.Font fontBld,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label1,
                  style: pw.TextStyle(
                    font: fontReg,
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    value1,
                    style: pw.TextStyle(font: fontBld, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          if (label2.isNotEmpty)
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    label2,
                    style: pw.TextStyle(
                      font: fontReg,
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Text(
                      value2,
                      style: pw.TextStyle(font: fontBld, fontSize: 11),
                    ),
                  ),
                ],
              ),
            )
          else
            pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    );
  }

  Future<void> _exportToPdf(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrlsByCategory,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Generuji PDF protokol (po vygenerování vyberte E-mail k odeslání)...',
        ),
        duration: Duration(seconds: 2),
      ),
    );

    // --- Načtení hlavičky servisu z nastavení ---
    final user = FirebaseAuth.instance.currentUser;
    String hlavickaNazev = 'VISTO';
    String hlavickaIco = '';
    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists) {
        hlavickaNazev = nastaveniDoc.data()?['nazev_servisu'] ?? 'VISTO';
        hlavickaIco = nastaveniDoc.data()?['ico_servisu'] ?? '';
      }
    }

    final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];
    final podpisUrl = data['podpis_url'] as String?;
    pw.MemoryImage? podpisImage;

    if (podpisUrl != null) {
      try {
        final response = await http.get(Uri.parse(podpisUrl));
        if (response.statusCode == 200) {
          podpisImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Chyba při stahování podpisu do PDF: $e");
      }
    }

    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    String poskozeniPdfText = 'Neuvedeno';
    if (stav['poskozeni'] is List) {
      poskozeniPdfText = (stav['poskozeni'] as List).join(', ');
    } else if (stav['poskozeni'] != null) {
      poskozeniPdfText = stav['poskozeni'].toString();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        hlavickaNazev,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 24,
                          color: PdfColors.blue800,
                        ),
                      ),
                      if (hlavickaIco.isNotEmpty)
                        pw.Text(
                          'IČO: $hlavickaIco',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                  pw.Text(
                    'Protokol o příjmu a opravě',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 20,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            if (zakaznik.isNotEmpty &&
                (zakaznik['jmeno']?.toString().isNotEmpty == true ||
                    zakaznik['ico']?.toString().isNotEmpty == true)) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Údaje o zákazníkovi',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 12,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    _buildCompactRow(
                      'Jméno / Firma:',
                      zakaznik['jmeno']?.toString() ?? '-',
                      'IČO:',
                      zakaznik['ico']?.toString() ?? '-',
                      fontRegular,
                      fontBold,
                    ),
                    _buildCompactRow(
                      'Adresa:',
                      zakaznik['adresa']?.toString() ?? '-',
                      'Telefon:',
                      zakaznik['telefon']?.toString() ?? '-',
                      fontRegular,
                      fontBold,
                    ),
                    _buildCompactRow(
                      'E-mail:',
                      zakaznik['email']?.toString() ?? '-',
                      '',
                      '',
                      fontRegular,
                      fontBold,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
            ],

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Údaje o vozidle',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 12,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  _buildCompactRow(
                    'Zakázka č.:',
                    data['cislo_zakazky'].toString(),
                    'Přijato:',
                    _formatDate(data['cas_prijeti']),
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'SPZ:',
                    data['spz'].toString(),
                    'VIN:',
                    data['vin']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Značka:',
                    data['znacka']?.toString() ?? '-',
                    'Model:',
                    data['model']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Rok výroby:',
                    data['rok_vyroby']?.toString() ?? '-',
                    'Motorizace:',
                    data['motorizace']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Typ paliva:',
                    data['palivo_typ']?.toString() ?? '-',
                    'Převodovka:',
                    data['prevodovka']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            pw.Text(
              'Stav vozidla při příjmu',
              style: pw.TextStyle(font: fontBold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            _buildCompactRow(
              'Tachometr:',
              '${stav['tachometr']?.toString().isNotEmpty == true ? stav['tachometr'] : '-'} km',
              'Palivo v nádrži:',
              '${stav['nadrz']?.toInt() ?? '-'} %',
              fontRegular,
              fontBold,
            ),
            _buildCompactRow(
              'Platnost STK:',
              '${stav['stk_mesic'] ?? '-'} / ${stav['stk_rok'] ?? '-'}',
              'Poškození:',
              poskozeniPdfText,
              fontRegular,
              fontBold,
            ),
            pw.SizedBox(height: 15),

            pw.Text(
              'Hloubka dezénu pneu:',
              style: pw.TextStyle(font: fontBold, fontSize: 12),
            ),
            pw.SizedBox(height: 5),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(
                        'Levá Přední',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Pravá Přední',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Levá Zadní',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Pravá Zadní',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            pw.Text(
              'Fotodokumentace příjmu',
              style: pw.TextStyle(font: fontBold, fontSize: 14),
            ),
            pw.SizedBox(height: 10),

            if (imageUrlsByCategory.values.every(
              (list) => (list as List).isEmpty,
            ))
              pw.Text(
                'Žádné fotografie nebyly pořízeny.',
                style: pw.TextStyle(font: fontRegular, fontSize: 11),
              )
            else
              pw.Wrap(
                spacing: 15,
                runSpacing: 5,
                children: imageUrlsByCategory.entries
                    .where((e) => (e.value as List<dynamic>).isNotEmpty)
                    .map((entry) {
                      final key = entry.key;
                      final urls = entry.value as List<dynamic>;
                      final label =
                          photoCategories[key]?['label'] ??
                          'Ostatní / Starší fotky';
                      return pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Container(
                            width: 4,
                            height: 4,
                            decoration: const pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              color: PdfColors.blue,
                            ),
                          ),
                          pw.SizedBox(width: 6),
                          pw.Text(
                            '$label (${urls.length}x)',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    })
                    .toList(),
              ),

            if (data['poznamky'] != null &&
                data['poznamky'].toString().isNotEmpty) ...[
              pw.SizedBox(height: 15),
              pw.Text(
                'Poznámky k příjmu:',
                style: pw.TextStyle(font: fontBold, fontSize: 12),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                data['poznamky'].toString(),
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 11,
                  color: PdfColors.grey800,
                ),
              ),
            ],

            pw.SizedBox(height: 20),

            if (provedenePrace.isNotEmpty) ...[
              pw.NewPage(),
              pw.Text(
                'Záznam o opravě a dodané díly',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 18,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 15),
              ...provedenePrace.map((prace) {
                final pocetFotek =
                    (prace['fotografie_urls'] as List?)?.length ?? 0;
                final dily = prace['pouzite_dily'] as List<dynamic>? ?? [];

                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey50,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '${prace['nazev']} (Cena úkonu: ${prace['cena_s_dph']} Kč s DPH)',
                            style: pw.TextStyle(font: fontBold, fontSize: 14),
                          ),
                          pw.Text(
                            _formatDate(prace['cas']),
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      if (prace['delka_prace'] != null &&
                          prace['delka_prace'].toString().isNotEmpty)
                        pw.Text(
                          'Délka práce: ${prace['delka_prace']} h',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                      if (prace['popis'] != null &&
                          prace['popis'].toString().isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          prace['popis'].toString(),
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                      ],
                      if (dily.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Použité díly:',
                          style: pw.TextStyle(font: fontBold, fontSize: 11),
                        ),
                        ...dily
                            .map(
                              (dil) => pw.Padding(
                                padding: const pw.EdgeInsets.only(
                                  top: 2,
                                  left: 10,
                                ),
                                child: pw.Text(
                                  '• ${dil['nazev']} (${dil['cislo']}) - ${dil['pocet']} ks - ${dil['cena_s_dph']} Kč s DPH',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ],
                      if (pocetFotek > 0) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Pořízená fotodokumentace: $pocetFotek fotek',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],

            pw.Spacer(),

            if (podpisImage != null) ...[
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Podpis zákazníka:',
                        style: pw.TextStyle(font: fontBold, fontSize: 12),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Image(podpisImage, width: 150, height: 60),
                      pw.Container(
                        width: 150,
                        height: 1,
                        color: PdfColors.black,
                      ),
                    ],
                  ),
                  pw.Text(
                    'Vygenerováno aplikací Visto',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 10,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ] else ...[
              pw.Center(
                child: pw.Text(
                  'Vygenerováno aplikací Visto',
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 10,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ],
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Protokol_${data['cislo_zakazky']}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 1,
        title: Text(
          'Oprava: $zakazkaId ($spz)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('zakazky')
            .doc(documentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("Chyba: ${snapshot.error}"));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null)
            return const Center(child: Text("Dokument nenalezen."));

          final provedenePrace =
              data['provedene_prace'] as List<dynamic>? ?? [];
          final aktualniStav = data['stav_zakazky'] ?? 'Přijato';
          final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
          final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
          final rawUrls = data['fotografie_urls'];
          final Map<String, dynamic> imageUrlsByCategoryRaw = {};

          if (rawUrls is Map) {
            imageUrlsByCategoryRaw.addAll(Map<String, dynamic>.from(rawUrls));
          } else if (rawUrls is List) {
            imageUrlsByCategoryRaw['ostatni'] = rawUrls;
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    const Text(
                      'Stav zakázky: ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: getStatusColor(aktualniStav).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: getStatusColor(aktualniStav),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: aktualniStav,
                            isExpanded: true,
                            dropdownColor: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.white,
                            items: stavyZakazky
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s,
                                      style: TextStyle(
                                        color: getStatusColor(s),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (novyStav) {
                              if (novyStav != null)
                                _zmenitStav(context, novyStav);
                            },
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.picture_as_pdf,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _exportToPdf(
                        context,
                        data,
                        stav,
                        zakaznik,
                        imageUrlsByCategoryRaw,
                      ),
                      tooltip: 'Stáhnout PDF',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(
                  'Zaznamenané úkony',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: provedenePrace.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.build_circle_outlined,
                              size: 80,
                              color: Colors.grey.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Zatím nebyly přidány žádné práce.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: provedenePrace.length,
                        itemBuilder: (context, index) {
                          final prace =
                              provedenePrace[provedenePrace.length - 1 - index];
                          final fotky =
                              prace['fotografie_urls'] as List<dynamic>? ?? [];
                          final dily =
                              prace['pouzite_dily'] as List<dynamic>? ?? [];

                          return Card(
                            margin: const EdgeInsets.only(bottom: 15),
                            color: isDark
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${prace['nazev']} (${prace['cena_s_dph']} Kč s DPH)',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            _deleteWork(context, prace),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                          size: 20,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _formatDate(prace['cas']),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),

                                  if (prace['popis'] != null &&
                                      prace['popis'].toString().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      prace['popis'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],

                                  if (prace['delka_prace'] != null &&
                                      prace['delka_prace']
                                          .toString()
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'Čas práce: ${prace['delka_prace']} h',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue,
                                        ),
                                      ),
                                    ),

                                  if (dily.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Použité díly:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    ...dily
                                        .map(
                                          (dil) => Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                              left: 10,
                                            ),
                                            child: Text(
                                              '• ${dil['nazev']} (${dil['cislo']}) - ${dil['pocet']} ks - ${dil['cena_s_dph']} Kč s DPH',
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ],

                                  if (fotky.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 15),
                                      child: SizedBox(
                                        height: 100,
                                        child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: fotky.length,
                                          separatorBuilder: (c, i) =>
                                              const SizedBox(width: 10),
                                          itemBuilder: (c, i) =>
                                              GestureDetector(
                                                onTap: () => html.window.open(
                                                  fotky[i],
                                                  "_blank",
                                                ),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: Image.network(
                                                    fotky[i],
                                                    width: 140,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: () => _openAddWorkDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'ZAZNAMENAT ÚKON',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================================
// SUB-WIDGET PRO VKLÁDÁNÍ NOVÉ PRÁCE S KALKULACÍ
// ==============================================================================

class _AddWorkSheet extends StatefulWidget {
  final String documentId;
  final String zakazkaId;

  const _AddWorkSheet({required this.documentId, required this.zakazkaId});

  @override
  State<_AddWorkSheet> createState() => _AddWorkSheetState();
}

class _AddWorkSheetState extends State<_AddWorkSheet> {
  final _nazevController = TextEditingController();
  final _popisController = TextEditingController();
  final _delkaController = TextEditingController();
  final _praceCenaBezDphController = TextEditingController();
  final _praceCenaSDphController = TextEditingController();

  final List<DilInput> _dilyInputs = [];

  final List<XFile> _workImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  double _hodinovaSazba = 0.0;

  @override
  void initState() {
    super.initState();
    _nactiHodinovouSazbu();
  }

  // --- NOVÉ: Načtení hodinové sazby servisu ---
  Future<void> _nactiHodinovouSazbu() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        setState(() {
          _hodinovaSazba = (doc.data()?['hodinova_sazba'] ?? 0.0).toDouble();
        });
      }
    }
  }

  // --- NOVÉ: Automatický výpočet ceny práce ---
  void _vypocitejCenuPrace(String hodiny) {
    double pocetHodin = double.tryParse(hodiny.replaceAll(',', '.')) ?? 0.0;
    double cenaBezDph = pocetHodin * _hodinovaSazba;

    _praceCenaBezDphController.text = cenaBezDph.toStringAsFixed(2);
    _vypocitejDPH(cenaBezDph.toString(), _praceCenaSDphController);
  }

  @override
  void dispose() {
    _nazevController.dispose();
    _popisController.dispose();
    _delkaController.dispose();
    _praceCenaBezDphController.dispose();
    _praceCenaSDphController.dispose();
    for (var dil in _dilyInputs) {
      dil.dispose();
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (photo != null) setState(() => _workImages.add(photo));
  }

  Future<void> _pickFromGallery() async {
    final photos = await _picker.pickMultiImage(
      imageQuality: 60,
      maxWidth: 1280,
      maxHeight: 1280,
    );
    if (photos.isNotEmpty) setState(() => _workImages.addAll(photos));
  }

  Future<void> _saveWork() async {
    if (_nazevController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      List<String> uploadedUrls = [];
      for (int i = 0; i < _workImages.length; i++) {
        String fileName =
            'prace_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        Reference ref = FirebaseStorage.instance.ref().child(
          'servisy/${user!.uid}/zakazky/${widget.zakazkaId}/$fileName',
        );
        await ref.putData(await _workImages[i].readAsBytes());
        uploadedUrls.add(await ref.getDownloadURL());
      }

      List<Map<String, dynamic>> pouziteDily = _dilyInputs
          .map(
            (dil) => {
              'cislo': dil.cislo.text.trim(),
              'nazev': dil.nazev.text.trim(),
              'pocet':
                  double.tryParse(dil.pocet.text.replaceAll(',', '.')) ?? 1.0,
              'cena_bez_dph':
                  double.tryParse(dil.cenaBezDph.text.replaceAll(',', '.')) ??
                  0.0,
              'cena_s_dph':
                  double.tryParse(dil.cenaSDph.text.replaceAll(',', '.')) ??
                  0.0,
            },
          )
          .where((d) => d['nazev'].toString().isNotEmpty)
          .toList();

      await FirebaseFirestore.instance
          .collection('zakazky')
          .doc(widget.documentId)
          .update({
            'provedene_prace': FieldValue.arrayUnion([
              {
                'nazev': _nazevController.text.trim(),
                'popis': _popisController.text.trim(),
                'pouzite_dily': pouziteDily,
                'delka_prace': _delkaController.text.trim(),
                'cena_bez_dph':
                    double.tryParse(
                      _praceCenaBezDphController.text.replaceAll(',', '.'),
                    ) ??
                    0.0,
                'cena_s_dph':
                    double.tryParse(
                      _praceCenaSDphController.text.replaceAll(',', '.'),
                    ) ??
                    0.0,
                'cas': Timestamp.now(),
                'fotografie_urls': uploadedUrls,
              },
            ]),
          });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Chyba: $e')));
      setState(() => _isSaving = false);
    }
  }

  void _vypocitejDPH(String hodnota, TextEditingController cilovyController) {
    double bezDph = double.tryParse(hodnota.replaceAll(',', '.')) ?? 0.0;
    double sDph = bezDph * 1.21;
    cilovyController.text = sDph.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 30,
        left: 30,
        right: 30,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Zaznamenat práci',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nazevController,
              decoration: InputDecoration(
                labelText: 'Název úkonu *',
                filled: true,
                fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _delkaController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _vypocitejCenuPrace, // NOVÉ: Výpočet při změně
                    decoration: InputDecoration(
                      labelText: 'Čas práce (hodiny)',
                      hintText: 'např. 1.5',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _praceCenaBezDphController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (val) =>
                        _vypocitejDPH(val, _praceCenaSDphController),
                    decoration: InputDecoration(
                      labelText: 'Cena bez DPH',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _praceCenaSDphController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cena s DPH',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2C2C2C)
                          : Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Použité díly:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 10),
                ...List.generate(_dilyInputs.length, (index) {
                  final dil = _dilyInputs[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: dil.cislo,
                                decoration: InputDecoration(
                                  hintText: 'Číslo dílu',
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: dil.nazev,
                                decoration: InputDecoration(
                                  hintText: 'Název dílu',
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => setState(() {
                                dil.dispose();
                                _dilyInputs.removeAt(index);
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: dil.pocet,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'Počet',
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: dil.cenaBezDph,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (val) =>
                                    _vypocitejDPH(val, dil.cenaSDph),
                                decoration: InputDecoration(
                                  labelText: 'Cena bez DPH/ks',
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: dil.cenaSDph,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Cena s DPH/ks',
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF2C2C2C)
                                      : Colors.grey[100],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () => setState(() => _dilyInputs.add(DilInput())),
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat díl'),
                ),
              ],
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _popisController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Popis / poznámka k úkonu',
                filled: true,
                fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Fotografie k úkonu:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: const Icon(Icons.add_a_photo, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _pickFromGallery,
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueGrey),
                      ),
                      child: const Icon(
                        Icons.photo_library,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _workImages.length,
                      itemBuilder: (c, i) => Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(right: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: kIsWeb
                                  ? Image.network(
                                      _workImages[i].path,
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.file(
                                      File(_workImages[i].path),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                    ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 12,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _workImages.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.close,
                                  size: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveWork,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'ULOŽIT ÚKON',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// STRÁNKA HISTORIE ZAKÁZEK
// ==============================================================================

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _searchQuery = '';

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return const Center(child: Text("Nejste přihlášeni."));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 30, 30, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Historie',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Hledat SPZ, VIN nebo číslo...',
                    prefixIcon: const Icon(Icons.search, color: Colors.blue),
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
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('zakazky')
                .where('servis_id', isEqualTo: user.uid)
                .orderBy('cas_prijeti', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final allDocs = snapshot.data!.docs;
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final cislo =
                    data['cislo_zakazky']?.toString().toLowerCase() ?? '';
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final vin = data['vin']?.toString().toLowerCase() ?? '';

                return cislo.contains(_searchQuery) ||
                    spz.contains(_searchQuery) ||
                    vin.contains(_searchQuery);
              }).toList();

              if (filteredDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 80,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Zatím žádné zakázky'
                            : 'Nic nenalezeno',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final data =
                      filteredDocs[index].data() as Map<String, dynamic>;
                  final stav = data['stav_zakazky'] ?? 'Přijato';
                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    child: ListTile(
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${data['spz']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: getStatusColor(stav).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: getStatusColor(stav),
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              stav,
                              style: TextStyle(
                                color: getStatusColor(stav),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'Zakázka: ${data['cislo_zakazky']}' +
                              (data['znacka'] != null &&
                                      data['znacka'].toString().isNotEmpty
                                  ? ' • ${data['znacka']} ${data['model'] ?? ''}'
                                  : '') +
                              (data['vin'] != null &&
                                      data['vin'].toString().isNotEmpty
                                  ? ' • VIN: ${data['vin']}'
                                  : '') +
                              '\nČas příjmu: ${_formatDate(data['cas_prijeti'])}',
                        ),
                      ),
                      isThreeLine: true,
                      onTap: () => _showHistoryDetail(context, data, isDark),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- DETAIL ZAKÁZKY (ČTENÍ PRO HISTORII) ---
  void _showHistoryDetail(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
    final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
    final rawUrls = data['fotografie_urls'];
    final Map<String, dynamic> imageUrlsByCategoryRaw = {};
    if (rawUrls is Map) {
      imageUrlsByCategoryRaw.addAll(Map<String, dynamic>.from(rawUrls));
    } else if (rawUrls is List) {
      imageUrlsByCategoryRaw['ostatni'] = rawUrls;
    }

    final List<Map<String, String>> allPhotos = [];
    imageUrlsByCategoryRaw.forEach((key, urls) {
      final label = photoCategories[key]?['label'] ?? 'Ostatní';
      for (var url in (urls as List)) {
        allPhotos.add({'url': url.toString(), 'label': label});
      }
    });

    String poskozeniText = (stav['poskozeni'] is List)
        ? (stav['poskozeni'] as List).join(', ')
        : (stav['poskozeni'] ?? 'Neuvedeno').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Zakázka ${data['cislo_zakazky']}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                  onPressed: () => _exportHistoryToPdf(context, data),
                  tooltip: 'Stáhnout PDF',
                ),
              ],
            ),
            Text(
              'SPZ: ${data['spz']}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (data['vin'] != null && data['vin'].toString().isNotEmpty)
              Text(
                'VIN: ${data['vin']}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            Text(
              'Přijato: ${_formatDate(data['cas_prijeti'])}',
              style: TextStyle(color: Colors.grey[600]),
            ),

            const Divider(height: 40),

            if (zakaznik.isNotEmpty &&
                (zakaznik['jmeno']?.toString().isNotEmpty == true ||
                    zakaznik['ico']?.toString().isNotEmpty == true)) ...[
              const Text(
                'Zákazník:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              if (zakaznik['jmeno']?.toString().isNotEmpty == true)
                _buildDetailRow(
                  'Jméno / Firma:',
                  zakaznik['jmeno'],
                  Icons.person,
                  Colors.blueGrey,
                ),
              if (zakaznik['ico']?.toString().isNotEmpty == true)
                _buildDetailRow(
                  'IČO:',
                  zakaznik['ico'],
                  Icons.business,
                  Colors.blueGrey,
                ),
              if (zakaznik['adresa']?.toString().isNotEmpty == true)
                _buildDetailRow(
                  'Adresa:',
                  zakaznik['adresa'],
                  Icons.location_on,
                  Colors.blueGrey,
                ),
              if (zakaznik['telefon']?.toString().isNotEmpty == true)
                _buildDetailRow(
                  'Telefon:',
                  zakaznik['telefon'],
                  Icons.phone,
                  Colors.blueGrey,
                ),
              if (zakaznik['email']?.toString().isNotEmpty == true)
                _buildDetailRow(
                  'E-mail:',
                  zakaznik['email'],
                  Icons.email,
                  Colors.blueGrey,
                ),
              const Divider(height: 40),
            ],

            const Text(
              'Stav vozidla:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            if (data['znacka'] != null && data['znacka'].toString().isNotEmpty)
              _buildDetailRow(
                'Značka:',
                data['znacka'],
                Icons.directions_car,
                Colors.blueGrey,
              ),
            if (data['model'] != null && data['model'].toString().isNotEmpty)
              _buildDetailRow(
                'Model:',
                data['model'],
                Icons.directions_car_filled,
                Colors.blueGrey,
              ),
            if (data['rok_vyroby'] != null &&
                data['rok_vyroby'].toString().isNotEmpty)
              _buildDetailRow(
                'Rok výroby:',
                data['rok_vyroby'],
                Icons.calendar_today,
                Colors.blueGrey,
              ),

            if (data['motorizace'] != null &&
                data['motorizace'].toString().isNotEmpty)
              _buildDetailRow(
                'Motor:',
                data['motorizace'],
                Icons.settings,
                Colors.blueGrey,
              ),
            if (data['palivo_typ'] != null &&
                data['palivo_typ'].toString().isNotEmpty)
              _buildDetailRow(
                'Palivo:',
                data['palivo_typ'],
                Icons.local_gas_station,
                Colors.blueGrey,
              ),
            if (data['prevodovka'] != null &&
                data['prevodovka'].toString().isNotEmpty)
              _buildDetailRow(
                'Převodovka:',
                data['prevodovka'],
                Icons.settings_input_component,
                Colors.blueGrey,
              ),

            _buildDetailRow(
              'Tachometr:',
              '${stav['tachometr'] ?? '-'} km',
              Icons.speed,
              Colors.grey,
            ),
            _buildDetailRow(
              'Palivo:',
              '${stav['nadrz']?.toInt() ?? '-'} %',
              Icons.local_gas_station,
              Colors.blueGrey,
            ),
            _buildDetailRow(
              'Poškození:',
              poskozeniText,
              Icons.warning_amber_rounded,
              Colors.orange,
            ),

            const SizedBox(height: 20),
            const Text(
              'Fotografie z příjmu:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (allPhotos.isEmpty)
              const Text('Žádné fotky.')
            else
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: allPhotos.length,
                  separatorBuilder: (c, i) => const SizedBox(width: 15),
                  itemBuilder: (c, i) => GestureDetector(
                    onTap: () =>
                        html.window.open(allPhotos[i]['url']!, "_blank"),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            allPhotos[i]['url']!,
                            width: 180,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          allPhotos[i]['label']!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String l, String v, IconData i, Color c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(i, color: c, size: 20),
        const SizedBox(width: 10),
        Text(l, style: const TextStyle(color: Colors.grey)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  pw.Widget _buildCompactRow(
    String label1,
    String value1,
    String label2,
    String value2,
    pw.Font fontReg,
    pw.Font fontBld,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label1,
                  style: pw.TextStyle(
                    font: fontReg,
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    value1,
                    style: pw.TextStyle(font: fontBld, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          if (label2.isNotEmpty)
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    label2,
                    style: pw.TextStyle(
                      font: fontReg,
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Expanded(
                    child: pw.Text(
                      value2,
                      style: pw.TextStyle(font: fontBld, fontSize: 11),
                    ),
                  ),
                ],
              ),
            )
          else
            pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    );
  }

  Future<void> _exportHistoryToPdf(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generuji PDF...'),
        duration: Duration(seconds: 1),
      ),
    );

    // --- Načtení hlavičky servisu z nastavení ---
    final user = FirebaseAuth.instance.currentUser;
    String hlavickaNazev = 'VISTO';
    String hlavickaIco = '';
    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists) {
        hlavickaNazev = nastaveniDoc.data()?['nazev_servisu'] ?? 'VISTO';
        hlavickaIco = nastaveniDoc.data()?['ico_servisu'] ?? '';
      }
    }

    final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
    final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
    final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];
    final podpisUrl = data['podpis_url'] as String?;
    pw.MemoryImage? podpisImage;

    if (podpisUrl != null) {
      try {
        final response = await http.get(Uri.parse(podpisUrl));
        if (response.statusCode == 200) {
          podpisImage = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        debugPrint("Chyba podpisu PDF: $e");
      }
    }

    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    String poskozeniPdfText = 'Neuvedeno';
    if (stav['poskozeni'] is List)
      poskozeniPdfText = (stav['poskozeni'] as List).join(', ');
    else if (stav['poskozeni'] != null)
      poskozeniPdfText = stav['poskozeni'].toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        hlavickaNazev,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 24,
                          color: PdfColors.blue800,
                        ),
                      ),
                      if (hlavickaIco.isNotEmpty)
                        pw.Text(
                          'IČO: $hlavickaIco',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                  pw.Text(
                    'Protokol o příjmu a opravě',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 20,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            if (zakaznik.isNotEmpty &&
                (zakaznik['jmeno']?.toString().isNotEmpty == true ||
                    zakaznik['ico']?.toString().isNotEmpty == true)) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Údaje o zákazníkovi',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 12,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    _buildCompactRow(
                      'Jméno / Firma:',
                      zakaznik['jmeno']?.toString() ?? '-',
                      'IČO:',
                      zakaznik['ico']?.toString() ?? '-',
                      fontRegular,
                      fontBold,
                    ),
                    _buildCompactRow(
                      'Adresa:',
                      zakaznik['adresa']?.toString() ?? '-',
                      'Telefon:',
                      zakaznik['telefon']?.toString() ?? '-',
                      fontRegular,
                      fontBold,
                    ),
                    _buildCompactRow(
                      'E-mail:',
                      zakaznik['email']?.toString() ?? '-',
                      '',
                      '',
                      fontRegular,
                      fontBold,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 15),
            ],

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Údaje o vozidle',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 12,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  _buildCompactRow(
                    'Zakázka č.:',
                    data['cislo_zakazky'].toString(),
                    'Přijato:',
                    _formatDate(data['cas_prijeti']),
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'SPZ:',
                    data['spz'].toString(),
                    'VIN:',
                    data['vin']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Značka:',
                    data['znacka']?.toString() ?? '-',
                    'Model:',
                    data['model']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Rok výroby:',
                    data['rok_vyroby']?.toString() ?? '-',
                    'Motorizace:',
                    data['motorizace']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                  _buildCompactRow(
                    'Typ paliva:',
                    data['palivo_typ']?.toString() ?? '-',
                    'Převodovka:',
                    data['prevodovka']?.toString() ?? '-',
                    fontRegular,
                    fontBold,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            pw.Text(
              'Stav vozidla při příjmu',
              style: pw.TextStyle(font: fontBold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            _buildCompactRow(
              'Tachometr:',
              '${stav['tachometr']?.toString().isNotEmpty == true ? stav['tachometr'] : '-'} km',
              'Palivo v nádrži:',
              '${stav['nadrz']?.toInt() ?? '-'} %',
              fontRegular,
              fontBold,
            ),
            _buildCompactRow(
              'Platnost STK:',
              '${stav['stk_mesic'] ?? '-'} / ${stav['stk_rok'] ?? '-'}',
              'Poškození:',
              poskozeniPdfText,
              fontRegular,
              fontBold,
            ),
            pw.SizedBox(height: 15),

            pw.Text(
              'Hloubka dezénu pneu:',
              style: pw.TextStyle(font: fontBold, fontSize: 12),
            ),
            pw.SizedBox(height: 5),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(
                        'Levá Přední',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Pravá Přední',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Levá Zadní',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text(
                        'Pravá Zadní',
                        style: pw.TextStyle(
                          font: fontRegular,
                          color: PdfColors.grey600,
                          fontSize: 9,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            if (data['poznamky'] != null &&
                data['poznamky'].toString().isNotEmpty) ...[
              pw.Text(
                'Poznámky k příjmu:',
                style: pw.TextStyle(font: fontBold, fontSize: 12),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                data['poznamky'].toString(),
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 11,
                  color: PdfColors.grey800,
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            if (provedenePrace.isNotEmpty) ...[
              pw.NewPage(),
              pw.Text(
                'Záznam o opravě a dodané díly',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 18,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 15),
              ...provedenePrace.map((prace) {
                final pocetFotek =
                    (prace['fotografie_urls'] as List?)?.length ?? 0;
                final dily = prace['pouzite_dily'] as List<dynamic>? ?? [];

                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey50,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            '${prace['nazev']} (Cena úkonu: ${prace['cena_s_dph']} Kč s DPH)',
                            style: pw.TextStyle(font: fontBold, fontSize: 14),
                          ),
                          pw.Text(
                            _formatDate(prace['cas']),
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                              color: PdfColors.grey600,
                            ),
                          ),
                        ],
                      ),
                      if (prace['delka_prace'] != null &&
                          prace['delka_prace'].toString().isNotEmpty)
                        pw.Text(
                          'Délka práce: ${prace['delka_prace']} h',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 11,
                            color: PdfColors.grey700,
                          ),
                        ),
                      if (prace['popis'] != null &&
                          prace['popis'].toString().isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          prace['popis'].toString(),
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                      ],
                      if (dily.isNotEmpty) ...[
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Použité díly:',
                          style: pw.TextStyle(font: fontBold, fontSize: 11),
                        ),
                        ...dily
                            .map(
                              (dil) => pw.Padding(
                                padding: const pw.EdgeInsets.only(
                                  top: 2,
                                  left: 10,
                                ),
                                child: pw.Text(
                                  '• ${dil['nazev']} (${dil['cislo']}) - ${dil['pocet']} ks - ${dil['cena_s_dph']} Kč s DPH',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ],
                      if (pocetFotek > 0) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Pořízená fotodokumentace: $pocetFotek fotek',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],

            pw.Spacer(),

            if (podpisImage != null) ...[
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 10),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Podpis zákazníka:',
                        style: pw.TextStyle(font: fontBold, fontSize: 12),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Image(podpisImage, width: 150, height: 60),
                      pw.Container(
                        width: 150,
                        height: 1,
                        color: PdfColors.black,
                      ),
                    ],
                  ),
                  pw.Text(
                    'Vygenerováno aplikací Visto',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 10,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ] else ...[
              pw.Center(
                child: pw.Text(
                  'Vygenerováno aplikací Visto',
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 10,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ],
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Protokol_${data['cislo_zakazky']}.pdf',
    );
  }
}
