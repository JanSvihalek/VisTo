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
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/constants.dart';

class MainWizardPage extends StatefulWidget {
  const MainWizardPage({super.key});
  @override
  State<MainWizardPage> createState() => _MainWizardPageState();
}

class _MainWizardPageState extends State<MainWizardPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 6;
  bool _isUploading = false;
  bool _isLoadingAres = false;
  bool _isCheckingZakazka = false;
  bool _isGeneratingCislo = false;
  bool _isLoadingSpz = false;

  final _jmenoController = TextEditingController();
  final _icoController = TextEditingController();
  final _adresaController = TextEditingController();
  final _telefonController = TextEditingController();
  final _emailZController = TextEditingController();

  // --- UPRAVENÉ: Proměnné pro defaultní nastavení e-mailu ---
  bool _odeslatEmail = true;
  bool _defaultOdeslatEmail = true; // Pamatuje si nastavení uživatele z Firebase

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
  final _poskozeniController = TextEditingController(); 
  double _stavNadrze = 50.0;

  final _stkMesicController = TextEditingController();
  final _stkRokController = TextEditingController();

  final _pneuLPController = TextEditingController();
  final _pneuPPController = TextEditingController();
  final _pneuLZController = TextEditingController();
  final _pneuPZController = TextEditingController();

  final List<TextEditingController> _pozadavkyControllers = [TextEditingController()];

  List<String> _rychleUkony = [];
  bool _isLoadingUkony = true;

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _generujCisloZakazky();
    _nactiNastaveni(); // Nově načítáme kompletní nastavení
  }

  // --- NOVÉ: Sloučené načítání nastavení z Firebase ---
  Future<void> _nactiNastaveni() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).get();
        if (doc.exists) {
          final data = doc.data()!;
          if (mounted) {
            setState(() {
              // 1. Načtení rychlých úkonů
              if (data.containsKey('rychle_ukony')) {
                _rychleUkony = List<String>.from(data['rychle_ukony']);
              } else {
                _rychleUkony = ['Výměna oleje a filtrů', 'Kontrola brzd', 'Servis klimatizace', 'Příprava a provedení STK', 'Geometrie kol', 'Pneuservis (přezutí)', 'Diagnostika závad'];
              }

              // 2. Načtení preference pro odesílání e-mailů
              if (data.containsKey('default_odesilat_emaily')) {
                _defaultOdeslatEmail = data['default_odesilat_emaily'] as bool;
                _odeslatEmail = _defaultOdeslatEmail; // Rovnou to aplikujeme na aktuální zakázku
              }

              _isLoadingUkony = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _rychleUkony = ['Výměna oleje a filtrů', 'Kontrola brzd', 'Servis klimatizace', 'Příprava a provedení STK', 'Geometrie kol', 'Pneuservis (přezutí)', 'Diagnostika závad'];
              _isLoadingUkony = false;
            });
          }
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingUkony = false);
      }
    }
  }

  Future<void> _generujCisloZakazky() async {
    setState(() => _isGeneratingCislo = true);

    String prefixBase = 'ZAK'; 

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

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

      final todayPrefix = DateFormat('yyMMdd').format(DateTime.now());
      final prefix = '$prefixBase-$todayPrefix-';

      final querySnapshot = await FirebaseFirestore.instance
          .collection('zakazky')
          .where('servis_id', isEqualTo: user.uid)
          .get();

      int nextNumber = 1;

      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final cislo = data['cislo_zakazky']?.toString() ?? '';

        if (cislo.startsWith(prefix)) {
          final koncovka = cislo.substring(prefix.length);
          final currentNum = int.tryParse(koncovka) ?? 0;
          if (currentNum >= nextNumber) {
            nextNumber = currentNum + 1;
          }
        }
      }

      if (mounted) {
        setState(() {
          _zakazkaController.text =
              '$prefix${nextNumber.toString().padLeft(4, '0')}';
        });
      }
    } catch (e) {
      debugPrint('Chyba při generování čísla: $e');
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

  Future<void> _hledatPodleSpz() async {
    final spz = _spzController.text.trim().toUpperCase().replaceAll(' ', '');
    if (spz.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zadejte alespoň část SPZ pro vyhledání.'), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoadingSpz = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      
      final vozidlaQuery = await FirebaseFirestore.instance.collection('vozidla')
          .where('servis_id', isEqualTo: user!.uid)
          .get();

      final nalezenaVozidla = vozidlaQuery.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((v) {
            final ulozenoSpz = (v['spz'] ?? '').toString().toUpperCase();
            return ulozenoSpz.startsWith(spz);
          })
          .toList();

      if (nalezenaVozidla.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Žádné vozidlo s touto SPZ nebylo nalezeno.'), backgroundColor: Colors.blueGrey));
        return;
      }

      if (nalezenaVozidla.length == 1) {
        await _aplikovatVybraneVozidlo(nalezenaVozidla.first);
      } else {
        _otevritVyberNalezenychVozidel(nalezenaVozidla);
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při vyhledávání: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoadingSpz = false);
    }
  }

  Future<void> _aplikovatVybraneVozidlo(Map<String, dynamic> vozidloData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _spzController.text = vozidloData['spz']?.toString() ?? '';
      _znackaController.text = vozidloData['znacka']?.toString() ?? '';
      _modelController.text = vozidloData['model']?.toString() ?? '';
      _vinController.text = vozidloData['vin']?.toString() ?? '';
      _rokVyrobyController.text = vozidloData['rok_vyroby']?.toString() ?? '';
      _motorizaceController.text = vozidloData['motorizace']?.toString() ?? '';
      if (vozidloData['palivo'] != null && _moznostiPaliva.contains(vozidloData['palivo'])) {
        _vybranePalivo = vozidloData['palivo'];
      }
      if (vozidloData['prevodovka'] != null && _moznostiPrevodovky.contains(vozidloData['prevodovka'])) {
        _vybranaPrevodovka = vozidloData['prevodovka'];
      }
    });

    final zakaznikId = vozidloData['zakaznik_id'];
    if (zakaznikId != null && zakaznikId.toString().isNotEmpty) {
      final zakQuery = await FirebaseFirestore.instance.collection('zakaznici')
          .where('servis_id', isEqualTo: user.uid)
          .where('id_zakaznika', isEqualTo: zakaznikId)
          .get();

      if (zakQuery.docs.isNotEmpty) {
        final z = zakQuery.docs.first.data();
        setState(() {
          _vybranyZakaznikId = z['id_zakaznika']?.toString();
          _jmenoController.text = z['jmeno']?.toString() ?? '';
          _icoController.text = z['ico']?.toString() ?? '';
          _adresaController.text = z['adresa']?.toString() ?? '';
          _telefonController.text = z['telefon']?.toString() ?? '';
          _emailZController.text = z['email']?.toString() ?? '';
        });
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Údaje o vozidle a zákazníkovi byly načteny.'), backgroundColor: Colors.green));
    }
  }

  void _otevritVyberNalezenychVozidel(List<Map<String, dynamic>> vozidla) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text('Nalezeno více vozidel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('Vyberte konkrétní vozidlo ze seznamu:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            Expanded(
              child: ListView.separated(
                itemCount: vozidla.length,
                separatorBuilder: (c, i) => const Divider(),
                itemBuilder: (context, index) {
                  final v = vozidla[index];
                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.blue, foregroundColor: Colors.white, child: Icon(Icons.directions_car)),
                    title: Text(v['spz'] ?? 'Neznámá SPZ', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${v['znacka'] ?? ''} ${v['model'] ?? ''}'),
                    onTap: () {
                      Navigator.pop(context);
                      _aplikovatVybraneVozidlo(v);
                    },
                  );
                }
              )
            )
          ]
        )
      )
    );
  }

  @override
  void dispose() {
    _spzController.dispose();
    _znackaController.dispose();
    _modelController.dispose();
    _vinController.dispose();
    _jmenoController.dispose();
    _telefonController.dispose();
    _emailZController.dispose();
    _tachometrController.dispose();
    _poskozeniController.dispose();
    _signatureController.dispose();
    for (var c in _pozadavkyControllers) { c.dispose(); }
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

  Future<void> _moveNext() async {
    FocusScope.of(context).unfocus();

    if (_currentPage == 0) {
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

  pw.Widget _buildCompactRowPdf(String label1, String value1, String label2, String value2, pw.Font fontReg, pw.Font fontBld) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(label1, style: pw.TextStyle(font: fontReg, fontSize: 10, color: PdfColors.grey700)), pw.SizedBox(width: 4), pw.Expanded(child: pw.Text(value1, style: pw.TextStyle(font: fontBld, fontSize: 11)))])),
          if (label2.isNotEmpty) pw.Expanded(child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [pw.Text(label2, style: pw.TextStyle(font: fontReg, fontSize: 10, color: PdfColors.grey700)), pw.SizedBox(width: 4), pw.Expanded(child: pw.Text(value2, style: pw.TextStyle(font: fontBld, fontSize: 11)))]))
          else pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    );
  }

  Future<Uint8List> _generateSilentPdf(Map<String, dynamic> data, Map<String, dynamic> stav, Map<String, dynamic> zakaznik, String? podpisUrl) async {
    final user = FirebaseAuth.instance.currentUser;
    String hlavickaNazev = 'Fixio';
    String hlavickaIco = '';
    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).get();
      if (nastaveniDoc.exists) {
        hlavickaNazev = nastaveniDoc.data()?['nazev_servisu'] ?? 'Fixio';
        hlavickaIco = nastaveniDoc.data()?['ico_servisu'] ?? '';
      }
    }

    pw.MemoryImage? podpisImage;
    if (podpisUrl != null) {
      try {
        final response = await http.get(Uri.parse(podpisUrl));
        if (response.statusCode == 200) podpisImage = pw.MemoryImage(response.bodyBytes);
      } catch (e) { debugPrint("Chyba PDF podpisu: $e"); }
    }

    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    String poskozeniPdfText = 'Neuvedeno';
    if (stav['poskozeni'] is List) { poskozeniPdfText = (stav['poskozeni'] as List).join(', '); } 
    else if (stav['poskozeni'] != null) { poskozeniPdfText = stav['poskozeni'].toString(); }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text(hlavickaNazev, style: pw.TextStyle(font: fontBold, fontSize: 24, color: PdfColors.blue800)),
                      if (hlavickaIco.isNotEmpty) pw.Text('IČO: $hlavickaIco', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey700)),
                  ]),
                  pw.Text('Protokol o příjmu', style: pw.TextStyle(font: fontRegular, fontSize: 20, color: PdfColors.grey600)),
                ])),
            pw.SizedBox(height: 15),
            pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Údaje o zákazníkovi', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue800)), pw.SizedBox(height: 5),
                  _buildCompactRowPdf('Jméno / Firma:', zakaznik['jmeno']?.toString() ?? '-', 'IČO:', zakaznik['ico']?.toString() ?? '-', fontRegular, fontBold),
                  _buildCompactRowPdf('Adresa:', zakaznik['adresa']?.toString() ?? '-', 'Telefon:', zakaznik['telefon']?.toString() ?? '-', fontRegular, fontBold),
                  _buildCompactRowPdf('E-mail:', zakaznik['email']?.toString() ?? '-', '', '', fontRegular, fontBold),
                ])),
            pw.SizedBox(height: 15),
            pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Údaje o vozidle', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.grey800)), pw.SizedBox(height: 5),
                  _buildCompactRowPdf('Zakázka č.:', data['cislo_zakazky'].toString(), 'SPZ:', data['spz'].toString(), fontRegular, fontBold),
                  _buildCompactRowPdf('Značka/Model:', '${data['znacka'] ?? '-'} ${data['model'] ?? ''}', 'VIN:', data['vin']?.toString() ?? '-', fontRegular, fontBold),
                ])),
            pw.SizedBox(height: 20),
            pw.Text('Stav vozidla při příjmu', style: pw.TextStyle(font: fontBold, fontSize: 14)), pw.SizedBox(height: 8),
            _buildCompactRowPdf('Tachometr:', '${stav['tachometr']} km', 'Palivo:', '${stav['nadrz']} %', fontRegular, fontBold),
            _buildCompactRowPdf('Poškození:', poskozeniPdfText, '', '', fontRegular, fontBold),
            if (data['poznamky'] != null && data['poznamky'].toString().isNotEmpty) ...[
              pw.SizedBox(height: 10), pw.Text('Poznámky:', style: pw.TextStyle(font: fontBold, fontSize: 12)), pw.Text(data['poznamky'].toString(), style: pw.TextStyle(font: fontRegular, fontSize: 11)),
            ],
            pw.Spacer(),
            if (podpisImage != null) ...[
              pw.Divider(color: PdfColors.grey300), pw.SizedBox(height: 10),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('Podpis zákazníka:', style: pw.TextStyle(font: fontBold, fontSize: 12)), pw.SizedBox(height: 5),
                      pw.Image(podpisImage, width: 150, height: 60), pw.Container(width: 150, height: 1, color: PdfColors.black),
                  ]),
                  pw.Text('Vygenerováno aplikací Fixio', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey500)),
              ]),
            ]
          ];
        },
      ),
    );
    return pdf.save();
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

    List<String> pozadovaneUkony = _pozadavkyControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    Map<String, dynamic> zakazkaData = {
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
      'pozadavky_zakaznika': pozadovaneUkony,
      'poznamky': _poskozeniController.text.trim(),
      'fotografie_urls': imageUrlsByCategory,
      'podpis_url': podpisUrl,
      'provedene_prace': [],
      'cas_prijeti': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc('${user.uid}_$zakazkaId')
        .set(zakazkaData);

    final emailZakanika = _emailZController.text.trim();
    
    if (_odeslatEmail && emailZakanika.isNotEmpty && emailZakanika.contains('@')) {
      
      String odesilatelJmeno = 'Fixio Servis';
      final docNastaveni = await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).get();
      if (docNastaveni.exists) {
        odesilatelJmeno = docNastaveni.data()?['nazev_servisu'] ?? 'Fixio Servis';
      }

      final pdfBytes = await _generateSilentPdf(zakazkaData, zakazkaData['stav_vozidla'], zakazkaData['zakaznik'], podpisUrl);

      Reference pdfRef = FirebaseStorage.instance.ref().child('servisy/${user.uid}/zakazky/$zakazkaId/protokol_$zakazkaId.pdf');
      await pdfRef.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
      String pdfDownloadUrl = await pdfRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('maily').add({
        'to': emailZakanika,
        'from': '$odesilatelJmeno (přes Fixio) <jan.svihalek00@gmail.com>', 
        'replyTo': user.email,
        'message': {
          'subject': 'Protokol o přijetí vozidla $spz - $odesilatelJmeno',
          'html': '''
            <div style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; border: 1px solid #eee; padding: 20px; border-radius: 10px;">
              <h2 style="color: #2196F3; border-bottom: 2px solid #2196F3; padding-bottom: 10px;">Dobrý den,</h2>
              <p>v příloze Vám zasíláme odkaz na podepsaný protokol o přijetí Vašeho vozidla <b>$spz</b> do našeho servisu.</p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="$pdfDownloadUrl" style="background-color: #2196F3; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px; display: inline-block;">Zobrazit a stáhnout protokol</a>
              </div>
              <p>V případě jakýchkoliv dotazů na tento e-mail jednoduše odpovězte, zpráva nám bude doručena.</p>
              <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
              <p style="font-size: 12px; color: #777;">Tento e-mail byl vygenerován automaticky systémem <b>Fixio</b> pro servis <b>$odesilatelJmeno</b>.</p>
            </div>
          ''',
        }
      });
    }
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
    _poskozeniController.clear();
    _signatureController.clear();
    
    for (var c in _pozadavkyControllers) { c.dispose(); }
    _pozadavkyControllers.clear();
    _pozadavkyControllers.add(TextEditingController());

    _generujCisloZakazky();
    
    // --- OPRAVENÉ: Reset zaškrtávátka zpět na uživatelův default z Firebase ---
    _odeslatEmail = _defaultOdeslatEmail;

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
                  _buildVozidloStep(isDark),
                  _buildZakaznikStep(isDark),
                  _buildCheckStep(isDark),
                  _buildPhotoStep(isDark),
                  _buildPraceStep(isDark), 
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
                        'Odesílám zakázku a protokol...',
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

  Widget _buildVozidloStep(bool isDark) => SingleChildScrollView(
    padding: const EdgeInsets.all(30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'Příjem vozidla',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              flex: 2,
              child: _buildInput(
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
            ),
          ],
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
          'SPZ vozidla (Klikněte na lupu pro dotažení) *',
          Icons.abc,
          _spzController,
          isDark,
          caps: true,
          customSuffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.document_scanner),
                onPressed: () => _scanText(_spzController, false),
                tooltip: 'Naskenovat SPZ fotoaparátem',
              ),
              _isLoadingSpz
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
                      onPressed: _hledatPodleSpz,
                      tooltip: 'Vyhledat auto a majitele z historie',
                    ),
            ],
          )
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
        
        // --- UPRAVENÉ: Checkbox se chová podle defaultního nastavení ---
        const SizedBox(height: 10),
        Row(
          children: [
            Checkbox(
              value: _odeslatEmail,
              onChanged: (val) => setState(() => _odeslatEmail = val ?? true),
              activeColor: Colors.blue,
            ),
            const Expanded(
              child: Text(
                'Odeslat zákazníkovi protokol e-mailem (pokud je vyplněn)',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
        // ------------------------------------------
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
              'Dodatečné poznámky k vozu',
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
                controller: _poskozeniController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Jakékoliv další detaily k příjmu...',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 60),
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
              final category = photoCategories[key]!;
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

  Widget _buildPraceStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Požadované práce',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            'Na čem jsme se se zákazníkem domluvili?',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          
          if (!_isLoadingUkony && _rychleUkony.isNotEmpty) ...[
            const Text('Rychlý výběr nejčastějších úkonů:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rychleUkony.map((ukon) => ActionChip(
                label: Text(ukon, style: const TextStyle(fontSize: 13)),
                backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.blue.withOpacity(0.05),
                side: BorderSide(color: Colors.blue.withOpacity(0.3)),
                onPressed: () {
                  setState(() {
                    if (_pozadavkyControllers.last.text.isEmpty) {
                      _pozadavkyControllers.last.text = ukon;
                    } else {
                      _pozadavkyControllers.add(TextEditingController(text: ukon));
                    }
                  });
                },
              )).toList(),
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 20),
          ],

          const Text('Seznam požadavků k zakázce:', style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 20),

          ...List.generate(_pozadavkyControllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: _buildInput(
                      'Úkon ${index + 1}',
                      Icons.build_circle_outlined,
                      _pozadavkyControllers[index],
                      isDark,
                    ),
                  ),
                  if (_pozadavkyControllers.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      child: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 30),
                        onPressed: () => setState(() => _pozadavkyControllers.removeAt(index)),
                      ),
                    ),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => setState(() => _pozadavkyControllers.add(TextEditingController())),
            icon: const Icon(Icons.add),
            label: const Text('Přidat jiný úkon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          )
        ],
      ),
    );
  }

  Widget _buildPodpisStep(bool isDark) {
    final validniPozadavky = _pozadavkyControllers.where((c) => c.text.trim().isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shrnutí a podpis',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Zákazník: ${_jmenoController.text.isEmpty ? 'Neuvedeno' : _jmenoController.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 5),
                Text('Vozidlo: ${_spzController.text.toUpperCase()} ${_znackaController.text}', style: const TextStyle(fontSize: 16)),
                
                if (validniPozadavky.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Divider(),
                  ),
                  const Text('Sjednané úkony:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16)),
                  const SizedBox(height: 10),
                  ...validniPozadavky.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        Expanded(child: Text(c.text, style: const TextStyle(fontSize: 15))),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Zákazník svým podpisem stvrzuje správnost výše uvedených údajů a souhlasí se stavem vozidla při převzetí do servisu.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 20),
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
  }

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