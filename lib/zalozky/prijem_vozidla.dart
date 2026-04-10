import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:signature/signature.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';

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
  bool _isCheckingZakazka = false;
  bool _isGeneratingCislo = false;

  final _jmenoController = TextEditingController();
  final _icoController = TextEditingController();
  final _adresaController = TextEditingController();
  final _telefonController = TextEditingController();
  final _emailZController = TextEditingController();

  String? _vybranyZakaznikId;
  List<Map<String, dynamic>> _nalezenaVozidla = [];

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
  void initState() {
    super.initState();
    _generujCisloZakazky();
  }

  // --- UPRAVENO: Načtení prefixu z nastavení a bezpečné řazení ---
  Future<void> _generujCisloZakazky() async {
    setState(() => _isGeneratingCislo = true);

    String prefixBase = 'ZAK'; // Výchozí stav

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Získání vlastního prefixu z nastavení servisu
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists &&
          nastaveniDoc.data()!.containsKey('prefix_zakazky')) {
        final storedPrefix = nastaveniDoc
            .data()!['prefix_zakazky']
            .toString()
            .trim();
        if (storedPrefix.isNotEmpty) prefixBase = storedPrefix;
      }

      // 2. Sestavení dnešního prefixu (např. OPRAVA-260410-)
      final todayPrefix = DateFormat('yyMMdd').format(DateTime.now());
      final prefix = '$prefixBase-$todayPrefix-';

      // 3. Šikovnější dotaz, který nepotřebuje nový speciální index ve Firebase
      // (Podíváme se prostě na posledních pár zakázek seřazených podle času)
      final querySnapshot = await FirebaseFirestore.instance
          .collection('zakazky')
          .where('servis_id', isEqualTo: user.uid)
          .orderBy('cas_prijeti', descending: true)
          .limit(20)
          .get();

      int nextNumber = 1;

      // 4. Najdeme tu nejnovější, která patří do dnešního dne
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final cislo = data['cislo_zakazky']?.toString() ?? '';

        if (cislo.startsWith(prefix)) {
          // Odřízneme text předpon a necháme jen koncové číslo
          final koncovka = cislo.substring(prefix.length);
          final lastIncrement = int.tryParse(koncovka) ?? 0;
          nextNumber = lastIncrement + 1;
          break; // Našli jsme tu největší, můžeme cyklus ukončit
        }
      }

      if (mounted) {
        setState(() {
          // Vytvoří číslo s nulami na začátku, např. 0001
          _zakazkaController.text =
              '$prefix${nextNumber.toString().padLeft(4, '0')}';
        });
      }
    } catch (e) {
      debugPrint('Chyba při generování čísla: $e');
      // Záložní řešení, pokud by např. selhal internet (nyní s TVÝM prefixem)
      if (mounted) {
        final todayPrefix = DateFormat('yyMMdd').format(DateTime.now());
        setState(() {
          _zakazkaController.text = '$prefixBase-$todayPrefix-0001';
        });
      }
    } finally {
      if (mounted) setState(() => _isGeneratingCislo = false);
    }
  }

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
            _moveNext();
          }
        },
      ),
    );
  }

  Future<void> _moveNext() async {
    FocusScope.of(context).unfocus();

    if (_currentPage == 1) {
      final zadaneCislo = _zakazkaController.text.trim();

      if (zadaneCislo.isEmpty || _spzController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Číslo zakázky a SPZ jsou povinné údaje!'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      setState(() => _isCheckingZakazka = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final docSnap = await FirebaseFirestore.instance
              .collection('zakazky')
              .where('servis_id', isEqualTo: user.uid)
              .where('cislo_zakazky', isEqualTo: zadaneCislo)
              .get();

          if (docSnap.docs.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Toto číslo zakázky již v databázi existuje! Zadejte prosím jiné.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 4),
              ),
            );
            setState(() => _isCheckingZakazka = false);
            return;
          }
        }
      } catch (e) {
        debugPrint('Chyba při kontrole čísla: $e');
      } finally {
        if (mounted) setState(() => _isCheckingZakazka = false);
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
    String zakazkaId = _zakazkaController.text.trim();

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

    _generujCisloZakazky();

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
            'Skenování pomocí AI funguje pouze v nainstalované aplikaci (APK/iOS).',
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
        const SizedBox(height: 30),

        if (_nalezenaVozidla.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.directions_car, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(
                      'Zákazník má uložená tato vozidla:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _nalezenaVozidla
                      .map(
                        (v) => ActionChip(
                          backgroundColor: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.white,
                          side: const BorderSide(color: Colors.blue),
                          label: Text(
                            '${v['spz']} ${v['znacka'] != null && v['znacka'].toString().isNotEmpty ? '(${v['znacka']} ${v['model'] ?? ''})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            setState(() {
                              _spzController.text = v['spz'] ?? '';
                              _vinController.text = v['vin'] ?? '';
                              _znackaController.text = v['znacka'] ?? '';
                              _modelController.text = v['model'] ?? '';
                              _rokVyrobyController.text = v['rok_vyroby'] ?? '';
                              _motorizaceController.text =
                                  v['motorizace'] ?? '';
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
            ),
          ),
          const SizedBox(height: 30),
        ],

        _buildInput(
          'Číslo zakázky *',
          Icons.onetwothree,
          _zakazkaController,
          isDark,
          caps: true,
          customSuffix: _isGeneratingCislo
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _generujCisloZakazky,
                  tooltip: 'Vygenerovat nové číslo',
                ),
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
                  onPressed:
                      (_isCheckingZakazka || _isUploading || _isGeneratingCislo)
                      ? null
                      : _moveNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child:
                      (_isCheckingZakazka || _isUploading || _isGeneratingCislo)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
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
