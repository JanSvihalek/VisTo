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
import 'firebase_options.dart'; // Soubor generovaný FlutterFire CLI

// --- GLOBÁLNÍ KONSTANTY ---
// Definice požadovaných fotografií s jejich popisy a ikonami
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
// ValueNotifier pro správu světlého/tmavého režimu v celé aplikaci
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  // Inicializace Flutter vazeb - nutné pro asynchronní operace před runApp
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializace Firebase aplikace s nastavením pro konkrétní platformu
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Spuštění hlavní aplikace
  runApp(const VistoApp());
}

// ==============================================================================
// HLAVNÍ APLIKACE A NASTAVENÍ TÉMATU
// ==============================================================================

class VistoApp extends StatelessWidget {
  const VistoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder naslouchá změnám v themeNotifieru
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false, // Skryje nápis "DEBUG" v rohu
          title:
              'Visto', // Název aplikace (např. v seznamu spuštěných aplikací)
          // Nastavení tématu pro světlý režim
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0061FF), // Základní modrá barva
              primary: const Color(0xFF0061FF),
              surface: const Color(0xFFFBFDFF), // Barva pozadí
            ),
            useMaterial3: true, // Použití moderního Material 3 designu
            fontFamily: 'Roboto', // Výchozí písmo
          ),

          // Nastavení tématu pro tmavý režim
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              brightness: Brightness.dark,
              seedColor: const Color(
                0xFF4D94FF,
              ), // Světlejší modrá pro tmavý režim
              primary: const Color(0xFF4D94FF),
              surface: const Color(0xFF121212), // Tmavé pozadí
            ),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),

          // Aktuálně vybraný režim tématu
          themeMode: currentMode,

          // Úvodní obrazovka
          home: const MainScreen(),
        );
      },
    );
  }
}

// ==============================================================================
// HLAVNÍ OBRAZOVKA S NAVIGACÍ (SCAFFOLD)
// ==============================================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Index aktuálně vybrané stránky v NavigationBaru
  int _currentIndex = 0;

  // Seznam stránek pro přepínání
  final List<Widget> _pages = [
    const MainWizardPage(), // Stránka pro nový příjem (Průvodce)
    const HistoryPage(), // Stránka s historií zakázek
  ];

  @override
  Widget build(BuildContext context) {
    // Zjištění, zda je aktivní tmavý režim
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,

      // Horní lišta aplikace (AppBar)
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ikonka blesku v primární barvě
              Icon(
                Icons.bolt,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 4),
              // Tučný název aplikace s upraveným prostrkáním (letterSpacing)
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
        centerTitle: true, // Vycentrování nadpisu
        backgroundColor: Colors.transparent, // Průhledné pozadí
        elevation: 0, // Bez stínu
        actions: [
          // Tlačítko pro přepínání světlého/tmavého režimu
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.amber : Colors.black54,
            ),
            onPressed: () {
              // Změna hodnoty v globálním notifieru
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      // Hlavní obsah obrazovky
      body: IndexedStack(index: _currentIndex, children: _pages),

      // Spodní navigační lišta (NavigationBar)
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          // Změna indexu a překreslení obrazovky
          setState(() {
            _currentIndex = index;
          });
        },
        // Mírně odlišná barva pozadí pro tmavý režim
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        // Barva indikátoru vybrané položky
        indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Příjem',
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
// STRÁNKA PRŮVODCE NOVÝM PŘÍJMEM (WIZARD)
// ==============================================================================

class MainWizardPage extends StatefulWidget {
  const MainWizardPage({super.key});
  @override
  State<MainWizardPage> createState() => _MainWizardPageState();
}

class _MainWizardPageState extends State<MainWizardPage> {
  // Kontroler pro PageView (přepínání kroků)
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3; // Celkový počet kroků
  bool _isUploading = false; // Příznak probíhajícího nahrávání do Firebase

  // --- KONTROLERY PRO TEXTOVÁ POLE ---
  final _zakazkaController = TextEditingController();
  final _spzController = TextEditingController();
  final _vinController = TextEditingController(); // NOVÉ: Kontroler pro VIN
  final _poznamkyController = TextEditingController();

  // --- STAVOVÉ PROMĚNNÉ ---
  // NOVÉ: Strukturovaný seznam pořízených fotografií
  final Map<String, XFile?> _categoryImages = {};
  final ImagePicker _picker = ImagePicker(); // Nástroj pro výběr/pořízení fotek

  // DATA PRO KROK 3: Stav vozidla
  String? _vybranePoskozeni;
  final List<String> _poskozeniMoznosti = [
    'Žádné',
    'Čelní sklo',
    'Stěrače',
    'Disky',
    'Karosérie',
  ];

  final _stkMesicController = TextEditingController();
  final _stkRokController = TextEditingController();

  final _pneuLPController = TextEditingController();
  final _pneuPPController = TextEditingController();
  final _pneuLZController = TextEditingController();
  final _pneuPZController = TextEditingController();

  // --- LOGIKA POSUNU V PRŮVODCI ---

  // Posun na další krok nebo dokončení nahrávání
  void _moveNext() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _startDirectUpload();
    }
  }

  // Posun na předchozí krok
  void _moveBack() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  // --- LOGIKA NAHRÁVÁNÍ DO FIREBASE ---

  // Funkce obalující nahrávání, ukazuje načítací overlay a SnackBar
  Future<void> _startDirectUpload() async {
    setState(() {
      _isUploading = true;
    });
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při odesílání: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // Hlavní asynchronní funkce pro nahrávání do Storage a Firestore
  Future<void> _uploadToFirebase() async {
    // NOVÉ: Strukturovaná mapa pro URL adresy fotek
    final Map<String, String> imageUrlsByCategory = {};
    String zakazkaId = _zakazkaController.text.trim().isEmpty
        ? 'ID_${DateTime.now().millisecondsSinceEpoch}'
        : _zakazkaController.text.trim();

    // 1. Nahrávání strukturovaných fotografií do Firebase Storage
    for (var entry in _categoryImages.entries) {
      final categoryKey = entry.key;
      final image = entry.value;

      if (image != null) {
        // Název souboru obsahuje kategorii a timestamp
        String fileName =
            '${categoryKey}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference ref = FirebaseStorage.instance.ref().child(
          'zakazky/$zakazkaId/$fileName',
        );

        await ref.putData(await image.readAsBytes());
        String downloadUrl = await ref.getDownloadURL();
        imageUrlsByCategory[categoryKey] = downloadUrl;
      }
    }

    // 2. Nahrávání dat do Cloud Firestore
    await FirebaseFirestore.instance.collection('zakazky').doc(zakazkaId).set({
      'cislo_zakazky': zakazkaId,
      'spz': _spzController.text.trim(),
      'vin': _vinController.text.trim(), // NOVÉ: Uložení VIN do databáze
      'stav_vozidla': {
        'poskozeni': _vybranePoskozeni ?? 'Neuvedeno',
        'stk_mesic': _stkMesicController.text.trim(),
        'stk_rok': _stkRokController.text.trim(),
        'pneu_lp': _pneuLPController.text.trim(),
        'pneu_pp': _pneuPPController.text.trim(),
        'pneu_lz': _pneuLZController.text.trim(),
        'pneu_pz': _pneuPZController.text.trim(),
      },
      'poznamky': _poznamkyController.text.trim(),
      'fotografie_urls': imageUrlsByCategory, // NOVÉ: Uložení mapy URL adres
      'cas_prijeti': FieldValue.serverTimestamp(),
    });
  }

  // Vymaže formulář a vrátí průvodce na začátek
  void _resetForm() {
    _zakazkaController.clear();
    _spzController.clear();
    _vinController.clear(); // NOVÉ: Vyčištění VIN
    _poznamkyController.clear();
    // NOVÉ: Vyčištění strukturovaných obrázků
    _categoryImages.clear();

    // Vyčištění polí pro krok 3
    _vybranePoskozeni = null;
    _stkMesicController.clear();
    _stkRokController.clear();
    _pneuLPController.clear();
    _pneuPPController.clear();
    _pneuLZController.clear();
    _pneuPZController.clear();

    setState(() {
      _currentPage = 0;
    });
    _pageController.jumpToPage(0);
  }

  // --- LOGIKA POŘÍZENÍ FOTKY (upravena o kategorii) ---
  Future<void> _takePhoto(String categoryKey) async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (photo != null) {
      setState(() {
        _categoryImages[categoryKey] = photo;
      });
    }
  }

  // --- LOGIKA SKENOVÁNÍ TEXTU (OCR) ---
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

      setState(() {
        controller.text = result;
      });
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
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                },
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildInfoStep(isDark), // Krok 1: Základní údaje + VIN
                  _buildPhotoStep(isDark), // Krok 2: Strukturované fotografie
                  _buildCheckStep(isDark), // Krok 3: Stav vozidla
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

  // --- KROK 1: ZÁKLADNÍ ÚDAJE (Číslo zakázky, SPZ, VIN) ---
  Widget _buildInfoStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Základní údaje',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 40),
        _buildInput(
          'Číslo zakázky',
          Icons.onetwothree,
          _zakazkaController,
          isDark,
          caps: true,
        ),
        const SizedBox(height: 20),
        _buildInput(
          'SPZ vozidla',
          Icons.abc,
          _spzController,
          isDark,
          caps: true,
        ),
        const SizedBox(height: 20),
        // NOVÉ: Pole pro VIN kód
        _buildInput(
          'VIN kód',
          Icons.abc, // Ikonka otisku prstu (unikátní identifikátor)
          _vinController,
          isDark,
          caps: true, // VIN obsahuje velká písmena
        ),
      ],
    ),
  );

  // --- KROK 2: STRUKTUROVANÉ FOTOGRAFIE (ListView) ---
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
          'Vyfoťte prosím následující části vozu:',
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
              final takenPhoto = _categoryImages[key];

              return Card(
                color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: takenPhoto != null
                        ? Colors.green.withOpacity(0.5)
                        : Colors.grey.withOpacity(0.2),
                    width: takenPhoto != null ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
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
                      const SizedBox(width: 15),
                      if (takenPhoto != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: kIsWeb
                              ? Image.network(
                                  takenPhoto.path,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                )
                              : Image.file(
                                  File(takenPhoto.path),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      const SizedBox(width: 10),
                      IconButton(
                        onPressed: () => _takePhoto(key),
                        icon: Icon(
                          takenPhoto != null
                              ? Icons.autorenew_rounded
                              : Icons.add_a_photo_rounded,
                          color: takenPhoto != null
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                      if (takenPhoto != null)
                        IconButton(
                          onPressed: () =>
                              setState(() => _categoryImages[key] = null),
                          icon: const Icon(
                            Icons.delete_rounded,
                            color: Colors.red,
                          ),
                        ),
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

  // --- KROK 3: STAV VOZIDLA A POZNÁMKY ---
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

        // 1. Poškození
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Zjištěné poškození',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _vybranePoskozeni,
              hint: const Text('Vyberte z možností'),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.blue,
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.car_crash, color: Colors.blue),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _poskozeniMoznosti
                  .map(
                    (String value) => DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    ),
                  )
                  .toList(),
              onChanged: (newValue) =>
                  setState(() => _vybranePoskozeni = newValue),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // 2. STK
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '2. Platnost STK',
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

        // 3. Dezén Pneu
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3. Hloubka dezénu pneu (v mm)',
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

        // Poznámky
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dodatečné poznámky',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  // --- SPODNÍ PANEL (Ukazatel postupu a tlačítka) ---
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
                    _currentPage == _totalPages - 1 ? 'DOKONČIT' : 'DALŠÍ KROK',
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

  // --- POMOCNÁ FUNKCE PRO TEXTOVÁ POLE ---
  Widget _buildInput(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isDark, {
    bool caps = false,
    bool numbersOnly = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        textCapitalization: caps
            ? TextCapitalization.characters
            : TextCapitalization.none,
        keyboardType: numbersOnly ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.blue),
          suffixIcon: IconButton(
            icon: const Icon(Icons.document_scanner),
            onPressed: () => _scanText(controller, numbersOnly),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
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
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue, size: 20),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
      ),
    );
  }
}

// ==============================================================================
// STRÁNKA HISTORIE ZAKÁZEK (StreamBuilder, Firestore)
// ==============================================================================

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(30, 30, 30, 10),
          child: Text(
            'Historie',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('zakazky')
                .orderBy('cas_prijeti', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));

              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;

              if (docs.isEmpty)
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inbox_rounded,
                        size: 80,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Zatím žádné zakázky',
                        style: TextStyle(
                          fontSize: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
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
                      // Zobrazení SPZ a Data
                      subtitle: Text(
                        'SPZ: ${data['spz']}\n${_formatDate(data['cas_prijeti'])}',
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

  // --- DETAIL ZAKÁZKY (Zobrazí se zespodu jako BottomSheet) ---
  void _showDetail(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
    // NOVÉ: Načtení strukturovaných fotek (pokud existují)
    final Map<String, dynamic> imageUrlsByCategory =
        data['fotografie_urls'] as Map<String, dynamic>? ?? {};

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
                      _exportToPdf(context, data, stav, imageUrlsByCategory),
                  tooltip: 'Stáhnout PDF protokol',
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Základní údaje - Nyní včetně VIN kódu
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

            const Text(
              'Stav vozidla:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            _buildDetailRow(
              'Poškození:',
              stav['poskozeni']?.toString() ?? 'Neuvedeno',
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

            if (imageUrlsByCategory.isEmpty)
              const Text('Žádné fotografie nebyly pořízeny.')
            else
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imageUrlsByCategory.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 15),
                  itemBuilder: (context, i) {
                    final entry = imageUrlsByCategory.entries.elementAt(i);
                    final key = entry.key;
                    final imageUrl = entry.value as String;
                    final category = photoCategories[key];
                    final label = category != null
                        ? category['label'] as String
                        : 'Neznámá část';

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
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- LOGIKA GENEROVÁNÍ PDF PROTOKOLU (upravena o strukturované fotky) ---
  Future<void> _exportToPdf(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> imageUrlsByCategory,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generuji PDF protokol...'),
        duration: Duration(seconds: 1),
      ),
    );

    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
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
                      'Protokol o příjmu',
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
                    // NOVÉ: VIN v PDF
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

              // STAV VOZIDLA
              pw.Text(
                'Stav vozidla',
                style: pw.TextStyle(font: fontBold, fontSize: 18),
              ),
              pw.SizedBox(height: 15),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Zjištěné poškození:',
                    style: pw.TextStyle(font: fontRegular),
                  ),
                  pw.Text(
                    stav['poskozeni']?.toString() ?? 'Neuvedeno',
                    style: pw.TextStyle(font: fontBold),
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
              // NOVÉ: Fotodokumentace v PDF
              pw.Text(
                'Fotodokumentace',
                style: pw.TextStyle(font: fontBold, fontSize: 18),
              ),
              pw.SizedBox(height: 15),

              if (imageUrlsByCategory.isEmpty)
                pw.Text(
                  'Žádné fotografie nebyly pořízeny.',
                  style: pw.TextStyle(font: fontRegular, fontSize: 12),
                )
              else
                ...imageUrlsByCategory.entries.map((entry) {
                  final key = entry.key;
                  final category = photoCategories[key];
                  final label = category != null
                      ? category['label'] as String
                      : 'Neznámá část';

                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Row(
                      children: [
                        // Vlastní modrý puntík místo pw.Bullet
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
                          label,
                          style: pw.TextStyle(font: fontRegular, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }), // Tady jsme smazali to .toList()

              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              if (data['poznamky'] != null &&
                  data['poznamky'].toString().isNotEmpty) ...[
                pw.Text(
                  'Poznámky k příjmu:',
                  style: pw.TextStyle(font: fontBold, fontSize: 16),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  data['poznamky'].toString(),
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 12,
                    color: PdfColors.grey800,
                  ),
                ),
              ] else ...[
                pw.Text(
                  'Bez dodatečných poznámek.',
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
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
            ],
          );
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Protokol_${data['cislo_zakazky']}.pdf',
    );
  }
}
