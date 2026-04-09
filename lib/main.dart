import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Pro kIsWeb a ValueNotifier
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io'; // Pro práci se soubory na mobilu (File)
import 'package:intl/intl.dart'; // Pro formátování data
import 'dart:html' as html; // Pro stahování/otevírání fotek na webu

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
                    body: Center(child: CircularProgressIndicator()));
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
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
      } else {
        await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chyba: $e'), backgroundColor: Colors.red));
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
                const Text('Visto',
                    style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5)),
                const SizedBox(height: 40),
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                    ],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'E-mail servisu',
                      filled: true,
                      fillColor:
                          isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                              color:
                                  isDark ? Colors.grey[800]! : Colors.grey[300]!,
                              width: 1)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(color: Colors.blue, width: 2)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                              color:
                                  isDark ? Colors.grey[800]! : Colors.grey[300]!,
                              width: 1)),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                    ],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Heslo',
                      filled: true,
                      fillColor:
                          isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                              color:
                                  isDark ? Colors.grey[800]! : Colors.grey[300]!,
                              width: 1)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide:
                              const BorderSide(color: Colors.blue, width: 2)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide(
                              color:
                                  isDark ? Colors.grey[800]! : Colors.grey[300]!,
                              width: 1)),
                    ),
                  ),
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
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(
                            _isLogin ? 'PŘIHLÁSIT SE' : 'ZAREGISTROVAT SERVIS',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                      _isLogin
                          ? 'Nový servis? Vytvořit účet'
                          : 'Už máte účet? Přihlásit se',
                      style: const TextStyle(color: Colors.grey)),
                ),
              ],
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

  final List<Widget> _pages = [
    const MainWizardPage(),
    const ServiceProgressPage(),
    const HistoryPage()
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.grey),
          onPressed: () => FirebaseAuth.instance.signOut(),
          tooltip: 'Odhlásit se',
        ),
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
            label: 'Průběh servisu',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historie',
          ),
        ],
      ),
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
  final int _totalPages = 4; // Zvýšeno na 4 (přidán zákazník)
  bool _isUploading = false;

  // --- Zákazník ---
  final _jmenoController = TextEditingController();
  final _icoController = TextEditingController();
  final _adresaController = TextEditingController();
  final _telefonController = TextEditingController();
  final _emailZController = TextEditingController();

  // --- Vozidlo ---
  final _zakazkaController = TextEditingController();
  final _spzController = TextEditingController();
  final _vinController = TextEditingController();
  final _poznamkyController = TextEditingController();

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

  void _moveNext() {
    FocusScope.of(context).unfocus();

    // Validace Kroku 2 (Vozidlo)
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

    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _startDirectUpload();
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

    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc('${user.uid}_$zakazkaId')
        .set({
      'servis_id': user.uid,
      'cislo_zakazky': zakazkaId,
      'spz': _spzController.text.trim(),
      'vin': _vinController.text.trim(),
      // NOVÉ: Zákazník
      'zakaznik': {
        'jmeno': _jmenoController.text.trim(),
        'ico': _icoController.text.trim(),
        'adresa': _adresaController.text.trim(),
        'telefon': _telefonController.text.trim(),
        'email': _emailZController.text.trim(),
      },
      'stav_vozidla': {
        'tachometr': _tachometrController.text.trim(),
        'nadrz': _stavNadrze,
        'poskozeni':
            _vybranePoskozeni.isEmpty ? ['Neuvedeno'] : _vybranePoskozeni,
        'stk_mesic': _stkMesicController.text.trim(),
        'stk_rok': _stkRokController.text.trim(),
        'pneu_lp': _pneuLPController.text.trim(),
        'pneu_pp': _pneuPPController.text.trim(),
        'pneu_lz': _pneuLZController.text.trim(),
        'pneu_pz': _pneuPZController.text.trim(),
      },
      'poznamky': _poznamkyController.text.trim(),
      'fotografie_urls': imageUrlsByCategory,
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

    _zakazkaController.clear();
    _spzController.clear();
    _vinController.clear();
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
                  _buildZakaznikStep(isDark), // Nový krok 1
                  _buildVozidloStep(isDark),  // Bývalý InfoStep
                  _buildPhotoStep(isDark),
                  _buildCheckStep(isDark),
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

  // --- NOVÉ: 1. Krok (Zákazník) ---
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
            ),
            const SizedBox(height: 20),
            _buildInput(
              'IČO (volitelné)',
              Icons.business,
              _icoController,
              isDark,
              numbersOnly: true,
            ),
            const SizedBox(height: 20),
            _buildInput(
              'Adresa',
              Icons.location_on,
              _adresaController,
              isDark,
            ),
            const SizedBox(height: 20),
            _buildInput(
              'Telefonní číslo',
              Icons.phone,
              _telefonController,
              isDark,
              numbersOnly: true,
            ),
            const SizedBox(height: 20),
            _buildInput(
              'E-mail',
              Icons.email,
              _emailZController,
              isDark,
            ),
          ],
        ),
      );

  // --- UPRAVENO: 2. Krok (Vozidlo) ---
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
            _buildInput(
                'VIN kód', Icons.abc, _vinController, isDark, caps: true),
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
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 15),
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
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
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
                                            () => _categoryImages[key]!
                                                .removeAt(
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
                      fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      Icon(Icons.local_gas_station,
                          color: _stavNadrze < 20 ? Colors.red : Colors.blue),
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey),
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
                            final isSelected =
                                _vybranePoskozeni.contains(value);
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey),
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey),
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.grey),
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
                      fillColor:
                          isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                            color:
                                isDark ? Colors.grey[800]! : Colors.grey[300]!,
                            width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                            color:
                                isDark ? Colors.grey[800]! : Colors.grey[300]!,
                            width: 1),
                      ),
                    ),
                  ),
                ),
              ],
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
                            ? 'DOKONČIT'
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
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey),
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
              keyboardType:
                  numbersOnly ? TextInputType.number : TextInputType.text,
              decoration: InputDecoration(
                prefixIcon: Icon(icon, color: Colors.blue),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.document_scanner),
                  onPressed: () => _scanText(controller, numbersOnly),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(
                      color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                      width: 1),
                ),
              ),
            ),
          ),
        ],
      );

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
                width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                width: 1),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
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
                'Vyberte zakázku a zaznamenejte provedenou práci nebo přidejte fotodokumentaci.',
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
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Hledat auto (SPZ, VIN, Číslo)...',
                    prefixIcon: const Icon(Icons.search, color: Colors.blue),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                          width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide:
                          const BorderSide(color: Colors.blue, width: 2),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                          width: 1),
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
                        Icons.build_circle_outlined,
                        size: 80,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Žádné aktivní zakázky'
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
                  final docId = filteredDocs[index].id;
                  
                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: Colors.blue.withOpacity(0.3),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        child: Icon(Icons.build),
                      ),
                      title: Text(
                        'Zakázka ${data['cislo_zakazky']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      subtitle: Text(
                        'SPZ: ${data['spz']}' + 
                        (data['vin'] != null && data['vin'].toString().isNotEmpty ? ' • VIN: ${data['vin']}' : '') +
                        '\nČas příjmu: ${_formatDate(data['cas_prijeti'])}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ActiveJobScreen(
                              documentId: docId, 
                              zakazkaId: data['cislo_zakazky'].toString(), 
                              spz: data['spz'].toString()
                            ),
                          ),
                        );
                      },
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
// OBRAZOVKA PRO PŘIDÁVÁNÍ A MAZÁNÍ ÚKONŮ V ZAKÁZCE
// ==============================================================================

class ActiveJobScreen extends StatelessWidget {
  final String documentId;
  final String zakazkaId;
  final String spz;

  const ActiveJobScreen({super.key, required this.documentId, required this.zakazkaId, required this.spz});

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
      builder: (context) => _AddWorkSheet(documentId: documentId, zakazkaId: zakazkaId),
    );
  }

  Future<void> _deleteWork(BuildContext context, Map<String, dynamic> workItem) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat úkon?'),
        content: const Text('Opravdu chcete tento záznam o práci odstranit? Tato akce je nevratná.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ZRUŠIT')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SMAZAT', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('zakazky').doc(documentId).update({
        'provedene_prace': FieldValue.arrayRemove([workItem])
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 1,
        title: Text('Oprava: $zakazkaId ($spz)', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('zakazky').doc(documentId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Chyba: ${snapshot.error}"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Center(child: Text("Dokument nenalezen."));

          final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text('Zaznamenané úkony', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: provedenePrace.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.build_circle_outlined, size: 80, color: Colors.grey.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text('Zatím nebyly přidány žádné práce.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: provedenePrace.length,
                      itemBuilder: (context, index) {
                        final prace = provedenePrace[provedenePrace.length - 1 - index];
                        final fotky = prace['fotografie_urls'] as List<dynamic>? ?? [];
                        final dily = prace['pouzite_dily'];
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 15),
                          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15), 
                            side: BorderSide(color: Colors.blue.withOpacity(0.3))
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(prace['nazev'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () => _deleteWork(context, prace),
                                    ),
                                  ],
                                ),
                                Text(_formatDate(prace['cas']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                
                                if (prace['popis'] != null && prace['popis'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(prace['popis'], style: const TextStyle(fontSize: 14)),
                                ],
                                
                                if (dily != null) ...[
                                  const SizedBox(height: 5),
                                  if (dily is List && dily.isNotEmpty)
                                    Text('Použité díly: ${dily.join(', ')}', style: const TextStyle(fontSize: 14))
                                  else if (dily is String && dily.isNotEmpty)
                                    Text('Použité díly: $dily', style: const TextStyle(fontSize: 14)),
                                ],
                                
                                if (prace['delka_prace'] != null && prace['delka_prace'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text('Délka práce: ${prace['delka_prace']}', style: const TextStyle(fontSize: 14)),
                                ],
                                if (fotky.isNotEmpty) ...[
                                  const SizedBox(height: 15),
                                  SizedBox(
                                    height: 100,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: fotky.length,
                                      separatorBuilder: (c, i) => const SizedBox(width: 10),
                                      itemBuilder: (c, i) => GestureDetector(
                                        onTap: () => html.window.open(fotky[i], "_blank"),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8), 
                                          child: Image.network(fotky[i], width: 140, fit: BoxFit.cover)
                                        ),
                                      )
                                    )
                                  )
                                ]
                              ],
                            ),
                          )
                        );
                      },
                    ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: () => _openAddWorkDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('ZAZNAMENAT ÚKON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue, 
                      foregroundColor: Colors.white, 
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                    ),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================================
// SUB-WIDGET PRO VKLÁDÁNÍ NOVÉ PRÁCE (BOTTOM SHEET S DYNAMICKÝMI DÍLY)
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
  
  final List<TextEditingController> _dilyControllers = [];
  
  final List<XFile> _workImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;

  @override
  void dispose() {
    _nazevController.dispose();
    _popisController.dispose();
    _delkaController.dispose();
    for (var controller in _dilyControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60, maxWidth: 1280, maxHeight: 1280);
    if (photo != null) setState(() => _workImages.add(photo));
  }

  Future<void> _pickFromGallery() async {
    final photos = await _picker.pickMultiImage(imageQuality: 60, maxWidth: 1280, maxHeight: 1280);
    if (photos.isNotEmpty) setState(() => _workImages.addAll(photos));
  }

  Future<void> _saveWork() async {
    if (_nazevController.text.trim().isEmpty) return;
    setState(() => _isSaving = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      List<String> uploadedUrls = [];

      for (int i = 0; i < _workImages.length; i++) {
        String fileName = 'prace_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        Reference ref = FirebaseStorage.instance.ref().child('servisy/${user!.uid}/zakazky/${widget.zakazkaId}/$fileName');
        await ref.putData(await _workImages[i].readAsBytes());
        uploadedUrls.add(await ref.getDownloadURL());
      }

      List<String> pouziteDily = _dilyControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      await FirebaseFirestore.instance.collection('zakazky').doc(widget.documentId).update({
        'provedene_prace': FieldValue.arrayUnion([{
          'nazev': _nazevController.text.trim(),
          'popis': _popisController.text.trim(),
          'pouzite_dily': pouziteDily, 
          'delka_prace': _delkaController.text.trim(),
          'cas': Timestamp.now(),
          'fotografie_urls': uploadedUrls,
        }])
      });

      if (mounted) Navigator.pop(context); 
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white, 
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25))
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 30, left: 30, right: 30),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zaznamenat práci', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            TextField(
              controller: _nazevController,
              decoration: InputDecoration(
                labelText: 'Název úkonu (např. Výměna oleje) *', 
                filled: true, 
                fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
              ),
            ),
            const SizedBox(height: 15),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Použité díly:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 10),
                ...List.generate(_dilyControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dilyControllers[index],
                            decoration: InputDecoration(
                              hintText: 'Název dílu (např. Olejový filtr)',
                              filled: true,
                              fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _dilyControllers[index].dispose();
                              _dilyControllers.removeAt(index);
                            });
                          },
                        )
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _dilyControllers.add(TextEditingController());
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat díl'),
                ),
              ],
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _delkaController,
              decoration: InputDecoration(
                labelText: 'Délka práce (např. 2h 30m)', 
                filled: true, 
                fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
              ),
            ),
            const SizedBox(height: 15),
            
            TextField(
              controller: _popisController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Popis práce / poznámka', 
                filled: true, 
                fillColor: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100], 
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
              ),
            ),
            const SizedBox(height: 20),
            
            const Text('Fotografie k úkonu:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      width: 80, 
                      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue)), 
                      child: const Icon(Icons.add_a_photo, color: Colors.blue)
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _pickFromGallery,
                    child: Container(
                      width: 80, 
                      decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueGrey)), 
                      child: const Icon(Icons.photo_library, color: Colors.blueGrey)
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
                              child: kIsWeb ? Image.network(_workImages[i].path, width: 80, height: 80, fit: BoxFit.cover) : Image.file(File(_workImages[i].path), width: 80, height: 80, fit: BoxFit.cover)
                            )
                          ),
                          Positioned(
                            top: 2, right: 12, 
                            child: GestureDetector(
                              onTap: () => setState(() => _workImages.removeAt(i)), 
                              child: const CircleAvatar(radius: 10, backgroundColor: Colors.white, child: Icon(Icons.close, size: 12, color: Colors.red))
                            )
                          )
                        ]
                      )
                    )
                  )
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                ),
                child: _isSaving 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                  : const Text('ULOŽIT ÚKON', style: TextStyle(fontWeight: FontWeight.bold)),
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
// STRÁNKA HISTORIE ZAKÁZEK (DETAIL KE ČTENÍ A TISK PDF)
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
                          width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide(
                          color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                          width: 1),
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
                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.car_repair),
                      ),
                      title: Text(
                        'Zakázka ${data['cislo_zakazky']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'SPZ: ${data['spz']}' + 
                        (data['vin'] != null && data['vin'].toString().isNotEmpty ? ' • VIN: ${data['vin']}' : '') +
                        '\nČas příjmu: ${_formatDate(data['cas_prijeti'])}',
                      ),
                      isThreeLine: true,
                      onTap: () => _showDetail(context, data, isDark),
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

  // --- DETAIL ZAKÁZKY ---
  void _showDetail(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
    final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {}; // NOVÉ
    final rawUrls = data['fotografie_urls'];
    final Map<String, dynamic> imageUrlsByCategoryRaw = {};

    if (rawUrls is Map) {
      imageUrlsByCategoryRaw.addAll(Map<String, dynamic>.from(rawUrls));
    } else if (rawUrls is List) {
      imageUrlsByCategoryRaw['ostatni'] = rawUrls;
    }

    final List<Map<String, String>> allPhotos = [];
    for (var entry in imageUrlsByCategoryRaw.entries) {
      final key = entry.key;
      final categoryLabel =
          photoCategories[key]?['label'] ?? 'Ostatní / Starší fotky';
      final urls = entry.value as List<dynamic>? ?? [];
      for (var url in urls) {
        allPhotos.add({'url': url.toString(), 'label': categoryLabel});
      }
    }

    String poskozeniText = 'Neuvedeno';
    if (stav['poskozeni'] is List) {
      poskozeniText = (stav['poskozeni'] as List).join(', ');
    } else if (stav['poskozeni'] != null) {
      poskozeniText = stav['poskozeni'].toString();
    }

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
                  onPressed: () =>
                      _exportToPdf(context, data, stav, zakaznik, imageUrlsByCategoryRaw),
                  tooltip: 'Stáhnout PDF protokol',
                ),
              ],
            ),
            const SizedBox(height: 10),

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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'Přijato: ${_formatDate(data['cas_prijeti'])}',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),

            const Divider(height: 40),

            // --- NOVÉ: Zákazník ---
            if (zakaznik.isNotEmpty && (zakaznik['jmeno']?.toString().isNotEmpty == true || zakaznik['ico']?.toString().isNotEmpty == true)) ...[
              const Text(
                'Zákazník:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 15),
              if (zakaznik['jmeno']?.toString().isNotEmpty == true)
                _buildDetailRow('Jméno / Firma:', zakaznik['jmeno'], Icons.person, Colors.blueGrey),
              if (zakaznik['ico']?.toString().isNotEmpty == true)
                _buildDetailRow('IČO:', zakaznik['ico'], Icons.business, Colors.blueGrey),
              if (zakaznik['adresa']?.toString().isNotEmpty == true)
                _buildDetailRow('Adresa:', zakaznik['adresa'], Icons.location_on, Colors.blueGrey),
              if (zakaznik['telefon']?.toString().isNotEmpty == true)
                _buildDetailRow('Telefon:', zakaznik['telefon'], Icons.phone, Colors.blueGrey),
              if (zakaznik['email']?.toString().isNotEmpty == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email, color: Colors.blue, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: SelectableText(zakaznik['email'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                    ],
                  ),
                ),
              const Divider(height: 40),
            ],

            const Text(
              'Stav vozidla:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            _buildDetailRow(
              'Tachometr:',
              '${stav['tachometr']?.toString().isNotEmpty == true ? stav['tachometr'] : 'Neuvedeno'} km',
              Icons.speed,
              Colors.grey,
            ),
            _buildDetailRow(
              'Palivo:',
              stav['nadrz'] != null ? '${stav['nadrz'].toInt()} %' : 'Neuvedeno',
              Icons.local_gas_station,
              Colors.blueGrey,
            ),
            const SizedBox(height: 10),

            _buildDetailRow(
              'Poškození:',
              poskozeniText,
              Icons.warning_amber_rounded,
              Colors.orange,
            ),
            _buildDetailRow(
              'Platnost STK:',
              '${stav['stk_mesic'] ?? '-'} / ${stav['stk_rok'] ?? '-'}',
              Icons.calendar_month_rounded,
              Colors.blue,
            ),

            const SizedBox(height: 10),
            const Text(
              'Dezén Pneu:',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('LP', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${stav['pneu_lp'] ?? '-'} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('PP', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${stav['pneu_pp'] ?? '-'} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('LZ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${stav['pneu_lz'] ?? '-'} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('PZ', style: TextStyle(color: Colors.grey)),
                    Text(
                      '${stav['pneu_pz'] ?? '-'} mm',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (data['poznamky'] != null &&
                data['poznamky'].toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Poznámky:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 5),
              Text(
                data['poznamky'],
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.black87,
                ),
              ),
            ],

            const SizedBox(height: 30),

            const Text(
              'Fotografie:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            if (allPhotos.isEmpty)
              const Text('Žádné fotografie nebyly pořízeny.')
            else
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: allPhotos.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 15),
                  itemBuilder: (context, i) {
                    final photo = allPhotos[i];
                    final imageUrl = photo['url']!;
                    final label = photo['label']!;

                    return GestureDetector(
                      onTap: () => html.window.open(imageUrl, "_blank"),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.network(
                              imageUrl,
                              width: 250,
                              height: 180,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 250,
                                    height: 180,
                                    color: Colors.grey[200],
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.broken_image,
                                          color: Colors.red,
                                          size: 40,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Chyba (CORS)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: 250,
                                      height: 180,
                                      color: Colors.grey[100],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start, 
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- PDF EXPORT ---
  Future<void> _exportToPdf(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrlsByCategory,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generuji PDF protokol (po vygenerování vyberte E-mail k odeslání)...'),
        duration: Duration(seconds: 2),
      ),
    );

    final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];

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
                  pw.Text(
                    'VISTO',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 28,
                      color: PdfColors.blue800,
                    ),
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
            pw.SizedBox(height: 20),

            // --- ZÁKAZNÍK (PDF) ---
            if (zakaznik.isNotEmpty && (zakaznik['jmeno']?.toString().isNotEmpty == true || zakaznik['ico']?.toString().isNotEmpty == true)) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(10),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Údaje o zákazníkovi', style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.blue800)),
                    pw.SizedBox(height: 10),
                    if (zakaznik['jmeno']?.toString().isNotEmpty == true)
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Jméno / Firma:', style: pw.TextStyle(font: fontRegular, fontSize: 12)), pw.Text(zakaznik['jmeno'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 12))]),
                    if (zakaznik['ico']?.toString().isNotEmpty == true)
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('IČO:', style: pw.TextStyle(font: fontRegular, fontSize: 12)), pw.Text(zakaznik['ico'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 12))]),
                    if (zakaznik['adresa']?.toString().isNotEmpty == true)
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Adresa:', style: pw.TextStyle(font: fontRegular, fontSize: 12)), pw.Text(zakaznik['adresa'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 12))]),
                    if (zakaznik['telefon']?.toString().isNotEmpty == true)
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Telefon:', style: pw.TextStyle(font: fontRegular, fontSize: 12)), pw.Text(zakaznik['telefon'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 12))]),
                    if (zakaznik['email']?.toString().isNotEmpty == true)
                      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('E-mail:', style: pw.TextStyle(font: fontRegular, fontSize: 12)), pw.Text(zakaznik['email'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 12))]),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
            ],

            pw.Container(
              padding: const pw.EdgeInsets.all(15),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(10),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Zakázka č.:',
                        style: pw.TextStyle(font: fontRegular, fontSize: 14),
                      ),
                      pw.Text(
                        data['cislo_zakazky'].toString(),
                        style: pw.TextStyle(font: fontBold, fontSize: 16),
                      ),
                    ],
                  ),
                  pw.Divider(color: PdfColors.grey300),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'SPZ vozidla:',
                        style: pw.TextStyle(font: fontRegular, fontSize: 14),
                      ),
                      pw.Text(
                        data['spz'].toString(),
                        style: pw.TextStyle(font: fontBold, fontSize: 16),
                      ),
                    ],
                  ),
                  if (data['vin'] != null &&
                      data['vin'].toString().isNotEmpty) ...[
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'VIN kód:',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 14,
                          ),
                        ),
                        pw.Text(
                          data['vin'].toString(),
                          style: pw.TextStyle(font: fontBold, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                  pw.Divider(color: PdfColors.grey300),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Datum a čas příjmu:',
                        style: pw.TextStyle(font: fontRegular, fontSize: 14),
                      ),
                      pw.Text(
                        _formatDate(data['cas_prijeti']),
                        style: pw.TextStyle(font: fontBold, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            pw.Text(
              'Stav vozidla při příjmu',
              style: pw.TextStyle(font: fontBold, fontSize: 18),
            ),
            pw.SizedBox(height: 15),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Stav tachometru:',
                  style: pw.TextStyle(font: fontRegular),
                ),
                pw.Text(
                  '${stav['tachometr']?.toString().isNotEmpty == true ? stav['tachometr'] : 'Neuvedeno'} km',
                  style: pw.TextStyle(font: fontBold),
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Stav paliva v nádrži:',
                  style: pw.TextStyle(font: fontRegular),
                ),
                pw.Text(
                  stav['nadrz'] != null ? '${stav['nadrz'].toInt()} %' : 'Neuvedeno',
                  style: pw.TextStyle(font: fontBold),
                ),
              ],
            ),
            pw.SizedBox(height: 5),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Zjištěné poškození:',
                  style: pw.TextStyle(font: fontRegular),
                ),
                pw.Expanded(
                  child: pw.Text(
                    poskozeniPdfText,
                    style: pw.TextStyle(font: fontBold),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Platnost STK:',
                  style: pw.TextStyle(font: fontRegular),
                ),
                pw.Text(
                  '${stav['stk_mesic'] ?? '-'} / ${stav['stk_rok'] ?? '-'}',
                  style: pw.TextStyle(font: fontBold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Text(
              'Hloubka dezénu pneu:',
              style: pw.TextStyle(font: fontBold, fontSize: 14),
            ),
            pw.SizedBox(height: 10),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(8),
                ),
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
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold),
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
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pp'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold),
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
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_lz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold),
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
                          fontSize: 10,
                        ),
                      ),
                      pw.Text(
                        '${stav['pneu_pz'] ?? '-'} mm',
                        style: pw.TextStyle(font: fontBold),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 30),
            pw.Text(
              'Fotodokumentace příjmu',
              style: pw.TextStyle(font: fontBold, fontSize: 18),
            ),
            pw.SizedBox(height: 15),

            if (imageUrlsByCategory.values.every(
              (list) => (list as List).isEmpty,
            ))
              pw.Text(
                'Žádné fotografie nebyly pořízeny.',
                style: pw.TextStyle(font: fontRegular, fontSize: 12),
              )
            else
              ...imageUrlsByCategory.entries
                  .where((e) => (e.value as List<dynamic>).isNotEmpty)
                  .map((entry) {
                    final key = entry.key;
                    final urls = entry.value as List<dynamic>;
                    final category = photoCategories[key];
                    final label = category != null
                        ? category['label'] as String
                        : 'Ostatní / Starší fotky';

                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 5),
                      child: pw.Row(
                        children: [
                          pw.Container(
                            width: 4,
                            height: 4,
                            decoration: const pw.BoxDecoration(
                              shape: pw.BoxShape.circle,
                              color: PdfColors.blue,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            '$label (${urls.length}x)',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                  .toList(),

            pw.SizedBox(height: 20),

            if (provedenePrace.isNotEmpty) ...[
              pw.NewPage(), 
              pw.Text(
                'Záznam o opravě / Provedené práce',
                style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.blue800),
              ),
              pw.SizedBox(height: 15),
              ...provedenePrace.map((prace) {
                final pocetFotek = (prace['fotografie_urls'] as List?)?.length ?? 0;
                final dily = prace['pouzite_dily'];
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 15),
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey50,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(prace['nazev'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 14)),
                          pw.Text(_formatDate(prace['cas']), style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey600)),
                        ],
                      ),
                      if (prace['popis'] != null && prace['popis'].toString().isNotEmpty) ...[
                        pw.SizedBox(height: 5),
                        pw.Text(prace['popis'].toString(), style: pw.TextStyle(font: fontRegular, fontSize: 12)),
                      ],
                      if (dily != null) ...[
                        pw.SizedBox(height: 3),
                        if (dily is List && dily.isNotEmpty)
                          pw.Text('Použité díly: ${dily.join(', ')}', style: pw.TextStyle(font: fontRegular, fontSize: 12))
                        else if (dily is String && dily.isNotEmpty)
                          pw.Text('Použité díly: $dily', style: pw.TextStyle(font: fontRegular, fontSize: 12)),
                      ],
                      if (prace['delka_prace'] != null && prace['delka_prace'].toString().isNotEmpty) ...[
                        pw.SizedBox(height: 3),
                        pw.Text('Délka práce: ${prace['delka_prace']}', style: pw.TextStyle(font: fontRegular, fontSize: 12)),
                      ],
                      if (pocetFotek > 0) ...[
                        pw.SizedBox(height: 5),
                        pw.Text('Pořízená fotodokumentace: $pocetFotek fotek', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.blue)),
                      ]
                    ],
                  ),
                );
              }),
            ],

            pw.Spacer(),
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