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
      // IndexedStack drží obě stránky v paměti a zobrazuje jen tu aktivní
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
  final _poznamkyController = TextEditingController();

  // --- STAVOVÉ PROMĚNNÉ ---
  final List<XFile> _images = []; // Seznam pořízených fotografií
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
    // Schová klávesnici při posunu
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      // Jsme na posledním kroku, spustíme nahrávání
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
    // Ukáže načítací obrazovku
    setState(() {
      _isUploading = true;
    });
    try {
      // Samotné nahrávání dat a fotek
      await _uploadToFirebase();
      if (mounted) {
        // Úspěch - SnackBar a reset formuláře
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zakázka úspěšně odeslána'),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
      }
    } catch (e) {
      // Chyba - SnackBar s popisem chyby
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při odesílání: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Vždy schová načítací obrazovku
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // Hlavní asynchronní funkce pro nahrávání do Storage a Firestore
  Future<void> _uploadToFirebase() async {
    List<String> imageUrls = [];
    // Vygeneruje ID zakázky, pokud není zadáno (např. ID_časové_razítko)
    String zakazkaId = _zakazkaController.text.trim().isEmpty
        ? 'ID_${DateTime.now().millisecondsSinceEpoch}'
        : _zakazkaController.text.trim();

    // 1. Nahrávání fotografií do Firebase Storage
    for (int i = 0; i < _images.length; i++) {
      XFile image = _images[i];
      // Unikátní název souboru
      String fileName = 'foto_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      // Reference na místo uložení: zakazky/ID_zakázky/název_souboru.jpg
      Reference ref = FirebaseStorage.instance.ref().child(
        'zakazky/$zakazkaId/$fileName',
      );

      // Nahrání dat (readAsBytes funguje na mobilu i webu)
      await ref.putData(await image.readAsBytes());
      // Získání veřejné URL adresy fotky
      String downloadUrl = await ref.getDownloadURL();
      imageUrls.add(downloadUrl);
    }

    // 2. Nahrávání dat do Cloud Firestore
    // Ukládáme do kolekce 'zakazky', dokument má ID zakázky
    await FirebaseFirestore.instance.collection('zakazky').doc(zakazkaId).set({
      'cislo_zakazky': zakazkaId,
      'spz': _spzController.text.trim(), // Odstraní mezery na začátku/konci
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
      'fotografie_urls': imageUrls, // Seznam získaných URL adres fotek
      'cas_prijeti': FieldValue.serverTimestamp(), // Časové razítko ze serveru
    });
  }

  // Vymaže formulář a vrátí průvodce na začátek
  void _resetForm() {
    _zakazkaController.clear();
    _spzController.clear();
    _poznamkyController.clear();
    _images.clear();

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
    // Skočí na první stránku PageView bez animace
    _pageController.jumpToPage(0);
  }

  // --- LOGIKA POŘÍZENÍ FOTKY ---
  Future<void> _takePhoto() async {
    // Pořídí fotku z fotoaparátu, mírně sníží kvalitu (70%) pro rychlejší nahrávání
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (photo != null) {
      setState(() {
        _images.add(photo);
      });
    }
  }

  // --- LOGIKA SKENOVÁNÍ TEXTU (OCR) ---

  // Ošetření technického omezení webových prohlížečů
  Future<void> _scanText(
    TextEditingController controller,
    bool numbersOnly,
  ) async {
    // Skenování (ML Kit) funguje pouze v nativní mobilní aplikaci, nikoliv ve webovém prohlížeči.
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

    // Nativní mobilní část skenování
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;

      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final recognizedText = await textRecognizer.processImage(inputImage);

      String result = recognizedText.text;

      // Formátování výsledku
      if (numbersOnly) {
        // Ponechá jen číslice (vhodné pro číslo zakázky)
        result = result.replaceAll(RegExp(r'[^0-9]'), '');
      } else {
        // Ponechá jen velká písmena a číslice (vhodné pro SPZ)
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

    // Stack umožňuje překrýt hlavní obsah načítacím overlaem (_isUploading)
    return Stack(
      children: [
        Column(
          children: [
            // Hlavní obsah průvodce (PageVew)
            Expanded(
              child: PageView(
                controller: _pageController,
                // Aktualizace stavu při změně stránky
                onPageChanged: (idx) {
                  setState(() {
                    _currentPage = idx;
                  });
                },
                // Vypnutí scrollování prstem - posouváme jen tlačítky
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildInfoStep(isDark), // Krok 1: Číslo zakázky a SPZ
                  _buildPhotoStep(isDark), // Krok 2: Fotografie
                  _buildCheckStep(isDark), // Krok 3: Stav vozidla
                ],
              ),
            ),
            // Spodní panel s ukazatelem postupu a tlačítky "Zpět/Další"
            _buildBottomPanel(isDark),
          ],
        ),

        // Načítací overlay - zobrazí se jen pokud nahráváme do Firebase
        if (_isUploading)
          Container(
            color: Colors.black54, // Poloprůhledné tmavé pozadí
            child: const Center(
              child: Card(
                elevation: 10,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(), // Točící se kolečko
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

  // --- KROK 1: ZÁKLADNÍ ÚDAJE (Číslo zakázky, SPZ) ---
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
        // Pole pro číslo zakázky - caps: true zajistí automatická velká písmena
        _buildInput(
          'Číslo zakázky',
          Icons.tag,
          _zakazkaController,
          isDark,
          caps: true,
        ),
        const SizedBox(height: 20),
        // Pole pro SPZ - caps: true zajistí automatická velká písmena
        _buildInput(
          'SPZ vozidla',
          Icons.directions_car,
          _spzController,
          isDark,
          caps: true,
        ),
      ],
    ),
  );

  // --- KROK 2: FOTOGRAFIE (GridView) ---
  Widget _buildPhotoStep(bool isDark) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fotky vozu',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.builder(
            // Mřížka s 2 sloupci a mezerami 15px
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
            ),
            // Počet položek = fotky + 1 (pro tlačítko přidání)
            itemCount: _images.length + 1,
            itemBuilder: (context, index) {
              if (index == _images.length) {
                // Poslední položka je tlačítko pro přidání fotky
                return InkWell(
                  onTap: _takePhoto,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.blue.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      size: 40,
                      color: Colors.blue,
                    ),
                  ),
                );
              }
              // Položky se zobrazenou fotkou a tlačítkem smazat (X)
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    // Rozlišení načítání fotky na webu (URL) a mobilu (File)
                    child: kIsWeb
                        ? Image.network(_images[index].path, fit: BoxFit.cover)
                        : Image.file(
                            File(_images[index].path),
                            fit: BoxFit.cover,
                          ),
                  ),
                  // Tlačítko pro smazání fotky (X) v pravém horním rohu
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(index)),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.close, size: 16, color: Colors.red),
                      ),
                    ),
                  ),
                ],
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

        // 1. Poškození (Dropdown v původním designu textových polí)
        const Text(
          '1. Zjištěné poškození',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _vybranePoskozeni,
          hint: const Text('Vyberte z možností'),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          items: _poskozeniMoznosti
              .map(
                (String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (newValue) => setState(() => _vybranePoskozeni = newValue),
        ),
        const SizedBox(height: 25),

        // 2. STK
        const Text(
          '2. Platnost STK',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSimpleInput(
                'Měsíc',
                _stkMesicController,
                isDark,
                TextInputType.number,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSimpleInput(
                'Rok',
                _stkRokController,
                isDark,
                TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),

        // 3. Dezén Pneu
        const Text(
          '3. Hloubka dezénu pneu (v mm)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildSimpleInput(
                'Levá přední',
                _pneuLPController,
                isDark,
                const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSimpleInput(
                'Pravá přední',
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
              child: _buildSimpleInput(
                'Levá zadní',
                _pneuLZController,
                isDark,
                const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: _buildSimpleInput(
                'Pravá zadní',
                _pneuPZController,
                isDark,
                const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),

        // Pole pro volné poznámky
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
  );

  // Pomocný widget pro zachování přesného designu jednoduchých políček
  Widget _buildSimpleInput(
    String hint,
    TextEditingController controller,
    bool isDark,
    TextInputType type,
  ) {
    return TextField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

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
          // Ukazatel postupu (tenké čárky nahoře)
          Row(
            children: List.generate(
              _totalPages,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    // Modrá pro hotové/aktuální kroky, šedá pro budoucí
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
          // Tlačítka
          Row(
            children: [
              // Tlačítko "Zpět" - zobrazí se jen pokud nejsme na prvním kroku
              if (_currentPage > 0)
                IconButton.filledTonal(
                  onPressed: _moveBack,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                  padding: const EdgeInsets.all(15),
                ),
              if (_currentPage > 0) const SizedBox(width: 15),

              // Hlavní tlačítko "Další krok" / "Dokončit"
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
                  // Změna textu na posledním kroku
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
        // Automatická velká písmena pro SPZ/Zakázku
        textCapitalization: caps
            ? TextCapitalization.characters
            : TextCapitalization.none,
        // Výběr klávesnice podle numbersOnly
        keyboardType: numbersOnly ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.blue),
          // Tlačítko pro skenování textu (OCR) vpravo
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
}

// ==============================================================================
// STRÁNKA HISTORIE ZAKÁZEK (StreamBuilder, Firestore)
// ==============================================================================

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  // Pomocná funkce pro formátování časového razítka z Firestore do češtiny
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    // Převedení Firestore Timestampu na Dart DateTime
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat(
      'dd.MM.yyyy HH:mm',
    ).format(dt); // Formát: 15.05.2023 14:30
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
          // StreamBuilder se automaticky aktualizuje, když se změní data ve Firestore
          child: StreamBuilder<QuerySnapshot>(
            // Stream ze Firestore: kolekce 'zakazky', seřazeno podle času příjmu (sestupně)
            stream: FirebaseFirestore.instance
                .collection('zakazky')
                .orderBy('cas_prijeti', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              // Zobrazí načítací kolečko, dokud nejsou data
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs;

              // Zobrazí nápis "Zatím žádné zakázky", pokud je kolekce prázdná
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

              // Seznam zakázek
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  // Převedení dokumentu na Dart Mapu (Map<String, dynamic>)
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
                      ), // Ikona auta
                      title: Text(
                        'Zakázka ${data['cislo_zakazky']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      // Formátovaný datum a SPZ v podnadpisu
                      subtitle: Text(
                        'SPZ: ${data['spz']}\n${_formatDate(data['cas_prijeti'])}',
                      ),
                      isThreeLine: true,
                      // Otevření detailu zakázky vespod (BottomSheet)
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // BottomSheet může být přes celou obrazovku
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Výška se přizpůsobí obsahu
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Šedý indikátor pro zavření Sheetu prstem (Scroll handle)
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

            // Hlavička detailu (Název a tlačítko PDF)
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
                // Červená ikona PDF pro generování protokolu
                IconButton(
                  icon: const Icon(
                    Icons.picture_as_pdf,
                    color: Colors.redAccent,
                    size: 28,
                  ),
                  onPressed: () => _exportToPdf(context, data),
                  tooltip: 'Stáhnout PDF protokol',
                ),
              ],
            ),
            const SizedBox(height: 10),
            // SPZ a čas příjmu
            Text(
              'SPZ: ${data['spz']}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Přijato: ${_formatDate(data['cas_prijeti'])}',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),

            const Divider(height: 40),

            // ZOBRAZENÍ NOVÝCH DAT V HISTORII
            const Text(
              'Stav vozidla:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            if (data['stav_vozidla'] != null) ...[
              Text('Poškození: ${data['stav_vozidla']['poskozeni']}'),
              Text(
                'STK: ${data['stav_vozidla']['stk_mesic']} / ${data['stav_vozidla']['stk_rok']}',
              ),
              const SizedBox(height: 10),
              const Text(
                'Dezén Pneu:',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('LP', style: TextStyle(color: Colors.grey)),
                      Text(
                        '${data['stav_vozidla']['pneu_lp']} mm',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('PP', style: TextStyle(color: Colors.grey)),
                      Text(
                        '${data['stav_vozidla']['pneu_pp']} mm',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('LZ', style: TextStyle(color: Colors.grey)),
                      Text(
                        '${data['stav_vozidla']['pneu_lz']} mm',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('PZ', style: TextStyle(color: Colors.grey)),
                      Text(
                        '${data['stav_vozidla']['pneu_pz']} mm',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ],

            // Sekce Poznámky (pouze pokud existují)
            if (data['poznamky'] != null &&
                data['poznamky'].toString().isNotEmpty) ...[
              const SizedBox(height: 20),
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

            // Sekce Fotografie
            const Text(
              'Fotografie (klikni pro stažení/zvětšení):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            if ((data['fotografie_urls'] as List).isEmpty)
              const Text('Žádné fotografie nebyly pořízeny.')
            else
              SizedBox(
                height: 180,
                // Horizontální seznam fotek (scrolluje se doprava)
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: (data['fotografie_urls'] as List).length,
                  itemBuilder: (context, i) {
                    final imageUrl = data['fotografie_urls'][i];
                    return GestureDetector(
                      // Na webu otevře fotku v novém okně prohlížeče
                      onTap: () => html.window.open(imageUrl, "_blank"),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          // Načítání obrázku ze síťové URL
                          child: Image.network(
                            imageUrl,
                            width: 250,
                            fit: BoxFit.cover,
                            // Ošetření chyby nahrávání (např. CORS na webu)
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 250,
                                  color: Colors.grey[200],
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Chyba načítání (CORS)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            // Načítací indikátor, než se fotka stáhne
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 250,
                                color: Colors.grey[100],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                        ),
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

  // --- LOGIKA GENEROVÁNÍ PDF PROTOKOLU ---
  Future<void> _exportToPdf(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    // Ukáže uživateli informativní SnackBar, že se na PDF pracuje
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generuji PDF protokol...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Vytvoření nového PDF dokumentu
    final pdf = pw.Document();

    // Stažení moderních písem (z Google Fonts), která umí háčky a čárky (velmi důležité pro češtinu v PDF)
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    // Přidání stránky do PDF
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40), // Okraje stránky 40px
        build: (pw.Context context) {
          // Obsah PDF stránky (Sloupec)
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. HLAVIČKA PDF
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
                    // Typ dokumentu v šedé barvě
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

              // 2. ŠEDÝ BOX S ÚDAJI O ZAKÁZCE (Číslo, SPZ, Datum)
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
                    pw.Divider(color: PdfColors.grey300), // Vodorovná čára
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

              // 3. SEKCE STAV VOZIDLA
              pw.Text(
                'Stav vozidla',
                style: pw.TextStyle(font: fontBold, fontSize: 18),
              ),
              pw.SizedBox(height: 15),
              if (data['stav_vozidla'] != null) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Zjištěné poškození:',
                      style: pw.TextStyle(font: fontRegular),
                    ),
                    pw.Text(
                      data['stav_vozidla']['poskozeni'].toString(),
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
                      '${data['stav_vozidla']['stk_mesic']} / ${data['stav_vozidla']['stk_rok']}',
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
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(
                      children: [
                        pw.Text(
                          'LP',
                          style: pw.TextStyle(
                            font: fontRegular,
                            color: PdfColors.grey600,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          '${data['stav_vozidla']['pneu_lp']} mm',
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text(
                          'PP',
                          style: pw.TextStyle(
                            font: fontRegular,
                            color: PdfColors.grey600,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          '${data['stav_vozidla']['pneu_pp']} mm',
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text(
                          'LZ',
                          style: pw.TextStyle(
                            font: fontRegular,
                            color: PdfColors.grey600,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          '${data['stav_vozidla']['pneu_lz']} mm',
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ],
                    ),
                    pw.Column(
                      children: [
                        pw.Text(
                          'PZ',
                          style: pw.TextStyle(
                            font: fontRegular,
                            color: PdfColors.grey600,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          '${data['stav_vozidla']['pneu_pz']} mm',
                          style: pw.TextStyle(font: fontBold),
                        ),
                      ],
                    ),
                  ],
                ),
              ],

              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              // 4. SEKCE POZNÁMKY
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
                // Fallback, pokud poznámky chybí
                pw.Text(
                  'Bez dodatečných poznámek.',
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
              ],

              pw.Spacer(), // Posune patičku až na spodek stránky
              // 5. PATIČKA PDF
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

    // Otevře dialog pro sdílení, tisk nebo stažení vygenerovaného PDF
    // Na webu to soubor rovnou nabídne ke stažení nebo otevře v náhledu, na mobilu otevře standardní dialog sdílení.
    await Printing.sharePdf(
      bytes: await pdf.save(), // Převede PDF na surová data (byty)
      filename:
          'Protokol_${data['cislo_zakazky']}.pdf', // Navrhovaný název souboru
    );
  }
}
