import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:html' as html;

// --- PŘIDANÉ KNIHOVNY PRO PDF ---
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'firebase_options.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FastCheckApp());
}

class FastCheckApp extends StatelessWidget {
  const FastCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FastCheck',
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0061FF), primary: const Color(0xFF0061FF), surface: const Color(0xFFFBFDFF)),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(brightness: Brightness.dark, seedColor: const Color(0xFF4D94FF), primary: const Color(0xFF4D94FF), surface: const Color(0xFF121212)),
            useMaterial3: true,
            fontFamily: 'Roboto',
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [const MainWizardPage(), const HistoryPage()];

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
              Icon(Icons.bolt, color: Theme.of(context).colorScheme.primary, size: 28),
              const SizedBox(width: 4),
              Text('FastCheck', style: TextStyle(fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87, letterSpacing: -0.5)),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: isDark ? Colors.amber : Colors.black54),
            onPressed: () => themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark,
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
          NavigationDestination(icon: Icon(Icons.add_circle_outline_rounded), selectedIcon: Icon(Icons.add_circle_rounded), label: 'Příjem'),
          NavigationDestination(icon: Icon(Icons.history_rounded), selectedIcon: Icon(Icons.history_rounded), label: 'Historie'),
        ],
      ),
    );
  }
}

class MainWizardPage extends StatefulWidget {
  const MainWizardPage({super.key});
  @override
  State<MainWizardPage> createState() => _MainWizardPageState();
}

class _MainWizardPageState extends State<MainWizardPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 3;
  bool _isUploading = false;

  final _zakazkaController = TextEditingController();
  final _spzController = TextEditingController();
  final _poznamkyController = TextEditingController();
  final List<XFile> _images = [];
  final ImagePicker _picker = ImagePicker();

  final Map<String, bool> _checklist = {'Plná nádrž': false, 'Interiér čistý': false, 'Poškození disků': false, 'Lékárnička/Výbava': false};

  void _moveNext() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    } else {
      _startDirectUpload();
    }
  }

  void _moveBack() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
  }

  Future<void> _startDirectUpload() async {
    setState(() => _isUploading = true);
    try {
      await _uploadToFirebase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zakázka úspěšně odeslána'), backgroundColor: Colors.green));
        _resetForm();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při odesílání: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadToFirebase() async {
    List<String> imageUrls = [];
    String zakazkaId = _zakazkaController.text.trim().isEmpty ? 'ID_${DateTime.now().millisecondsSinceEpoch}' : _zakazkaController.text.trim();

    for (int i = 0; i < _images.length; i++) {
      XFile image = _images[i];
      String fileName = 'foto_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      Reference ref = FirebaseStorage.instance.ref().child('zakazky/$zakazkaId/$fileName');
      await ref.putData(await image.readAsBytes());
      imageUrls.add(await ref.getDownloadURL());
    }

    await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'fastcheck').collection('zakazky').doc(zakazkaId).set({
      'cislo_zakazky': zakazkaId, 'spz': _spzController.text.trim(), 'checklist': _checklist, 'poznamky': _poznamkyController.text.trim(), 'fotografie_urls': imageUrls, 'cas_prijeti': FieldValue.serverTimestamp(),
    });
  }

  void _resetForm() {
    _zakazkaController.clear(); _spzController.clear(); _poznamkyController.clear(); _images.clear();
    _checklist.updateAll((key, value) => false);
    setState(() => _currentPage = 0);
    _pageController.jumpToPage(0);
  }

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (photo != null) setState(() => _images.add(photo));
  }

  Future<void> _scanText(TextEditingController controller, bool numbersOnly) async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;
    final inputImage = InputImage.fromFilePath(photo.path);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final recognizedText = await textRecognizer.processImage(inputImage);
    String result = recognizedText.text;
    result = numbersOnly ? result.replaceAll(RegExp(r'[^0-9]'), '') : result.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    setState(() => controller.text = result);
    textRecognizer.close();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Column(
          children: [
            Expanded(child: PageView(controller: _pageController, onPageChanged: (idx) => setState(() => _currentPage = idx), physics: const NeverScrollableScrollPhysics(), children: [_buildInfoStep(isDark), _buildPhotoStep(isDark), _buildCheckStep(isDark)])),
            _buildBottomPanel(isDark),
          ],
        ),
        if (_isUploading) Container(color: Colors.black54, child: const Center(child: Card(elevation: 10, child: Padding(padding: EdgeInsets.symmetric(horizontal: 40, vertical: 30), child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 20), Text('Odesílám zakázku...', style: TextStyle(fontWeight: FontWeight.bold))]))))),
      ],
    );
  }

  Widget _buildInfoStep(bool isDark) => SingleChildScrollView(padding: const EdgeInsets.all(30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Základní údaje', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)), const SizedBox(height: 40), _buildInput('Číslo zakázky', Icons.car_repair, _zakazkaController, isDark, keyboard: TextInputType.number), const SizedBox(height: 20), _buildInput('SPZ vozidla', Icons.abc, _spzController, isDark, caps: true)]));
  Widget _buildPhotoStep(bool isDark) => Padding(padding: const EdgeInsets.all(30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Fotky vozu', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)), const SizedBox(height: 20), Expanded(child: GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15), itemCount: _images.length + 1, itemBuilder: (context, index) { if (index == _images.length) return InkWell(onTap: _takePhoto, child: Container(decoration: BoxDecoration(color: isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2)), child: const Icon(Icons.add_a_photo_rounded, size: 40, color: Colors.blue))); return Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(20), child: kIsWeb ? Image.network(_images[index].path, fit: BoxFit.cover) : Image.file(File(_images[index].path), fit: BoxFit.cover)), Positioned(top: 8, right: 8, child: GestureDetector(onTap: () => setState(() => _images.removeAt(index)), child: const CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Icon(Icons.close, size: 16, color: Colors.red))))]); }))]));
  Widget _buildCheckStep(bool isDark) => SingleChildScrollView(padding: const EdgeInsets.all(30), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Checklist', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)), const SizedBox(height: 20), ..._checklist.keys.map((key) => Card(elevation: 0, color: isDark ? const Color(0xFF1E1E1E) : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)), child: CheckboxListTile(title: Text(key), value: _checklist[key], onChanged: (v) => setState(() => _checklist[key] = v!), activeColor: Colors.blue))), const SizedBox(height: 20), TextField(controller: _poznamkyController, maxLines: 3, decoration: InputDecoration(hintText: 'Poznámky...', filled: true, fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)))]));
  Widget _buildBottomPanel(bool isDark) => Container(padding: const EdgeInsets.fromLTRB(30, 20, 30, 30), decoration: BoxDecoration(color: isDark ? const Color(0xFF121212) : Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]), child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [Row(children: List.generate(_totalPages, (index) => Expanded(child: Container(height: 4, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: index <= _currentPage ? Colors.blue : Colors.grey[300], borderRadius: BorderRadius.circular(2)))))), const SizedBox(height: 20), Row(children: [if (_currentPage > 0) IconButton.filledTonal(onPressed: _moveBack, icon: const Icon(Icons.arrow_back_ios_new_rounded), padding: const EdgeInsets.all(15)), if (_currentPage > 0) const SizedBox(width: 15), Expanded(child: ElevatedButton(onPressed: _moveNext, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))), child: Text(_currentPage == _totalPages - 1 ? 'DOKONČIT' : 'DALŠÍ KROK', style: const TextStyle(fontWeight: FontWeight.bold))))])])));
  Widget _buildInput(String label, IconData icon, TextEditingController controller, bool isDark, {bool caps = false, TextInputType keyboard = TextInputType.text}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 8), TextField(controller: controller, textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none, keyboardType: keyboard, decoration: InputDecoration(prefixIcon: Icon(icon, color: Colors.blue), suffixIcon: IconButton(icon: const Icon(Icons.document_scanner), onPressed: () => _scanText(controller, keyboard == TextInputType.number)), filled: true, fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)))]);
}

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
        const Padding(padding: EdgeInsets.fromLTRB(30, 30, 30, 10), child: Text('Historie', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold))),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'fastcheck').collection('zakazky').orderBy('cas_prijeti', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.inbox_rounded, size: 80, color: Colors.grey.withOpacity(0.5)), const SizedBox(height: 16), Text('Zatím žádné zakázky', style: TextStyle(fontSize: 18, color: isDark ? Colors.grey[400] : Colors.grey[600]))]));
              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.car_repair)),
                      title: Text('Zakázka ${data['cislo_zakazky']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('SPZ: ${data['spz']}\n${_formatDate(data['cas_prijeti'])}'),
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

  void _showDetail(BuildContext context, Map<String, dynamic> data, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Zakázka ${data['cislo_zakazky']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 28),
                  onPressed: () => _exportToPdf(context, data),
                  tooltip: 'Stáhnout PDF protokol',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('SPZ: ${data['spz']}', style: const TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.w500)),
            Text('Přijato: ${_formatDate(data['cas_prijeti'])}', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700])),
            const Divider(height: 40),
            const Text('Checklist:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            ...(data['checklist'] as Map<String, dynamic>).entries.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Icon(e.value ? Icons.check_circle : Icons.cancel, color: e.value ? Colors.green : Colors.red, size: 18), const SizedBox(width: 8), Text('${e.key}: ${e.value ? "ANO" : "NE"}')]))),
            if (data['poznamky'] != null && data['poznamky'].toString().isNotEmpty) ...[const SizedBox(height: 20), const Text('Poznámky:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 5), Text(data['poznamky'], style: TextStyle(color: isDark ? Colors.grey[300] : Colors.black87))],
            const SizedBox(height: 30),
            const Text('Fotografie (klikni pro stažení/zvětšení):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 15),
            if ((data['fotografie_urls'] as List).isEmpty) const Text('Žádné fotografie nebyly pořízeny.')
            else SizedBox(height: 180, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: (data['fotografie_urls'] as List).length, itemBuilder: (context, i) { final imageUrl = data['fotografie_urls'][i]; return GestureDetector(onTap: () => html.window.open(imageUrl, "_blank"), child: Padding(padding: const EdgeInsets.only(right: 15), child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.network(imageUrl, width: 250, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: 250, color: Colors.grey[200], child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.broken_image, color: Colors.red, size: 40), SizedBox(height: 8), Text('Chyba načítání (CORS)', style: TextStyle(fontSize: 12, color: Colors.red))])), loadingBuilder: (context, child, loadingProgress) { if (loadingProgress == null) return child; return Container(width: 250, color: Colors.grey[100], child: const Center(child: CircularProgressIndicator())); })))); })),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- NOVÁ FUNKCE PRO GENEROVÁNÍ PDF ---
  Future<void> _exportToPdf(BuildContext context, Map<String, dynamic> data) async {
    // Ukáže uživateli, že se na tom pracuje
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Generuji PDF protokol...'), duration: Duration(seconds: 1)),
    );

    final pdf = pw.Document();

    // Stáhneme font, který umí háčky a čárky (velmi důležité pro češtinu v PDF)
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
              // Hlavička
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('FASTCHECK', style: pw.TextStyle(font: fontBold, fontSize: 28, color: PdfColors.blue800)),
                    pw.Text('Protokol o příjmu', style: pw.TextStyle(font: fontRegular, fontSize: 20, color: PdfColors.grey600)),
                  ]
                )
              ),
              pw.SizedBox(height: 20),

              // Informace o zakázce
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Zakázka č.:', style: pw.TextStyle(font: fontRegular, fontSize: 14)),
                        pw.Text(data['cislo_zakazky'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 16)),
                      ]
                    ),
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('SPZ vozidla:', style: pw.TextStyle(font: fontRegular, fontSize: 14)),
                        pw.Text(data['spz'].toString(), style: pw.TextStyle(font: fontBold, fontSize: 16)),
                      ]
                    ),
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Datum a čas příjmu:', style: pw.TextStyle(font: fontRegular, fontSize: 14)),
                        pw.Text(_formatDate(data['cas_prijeti']), style: pw.TextStyle(font: fontBold, fontSize: 14)),
                      ]
                    ),
                  ]
                )
              ),
              pw.SizedBox(height: 30),

              // Checklist
              pw.Text('Stav vozidla (Checklist)', style: pw.TextStyle(font: fontBold, fontSize: 18)),
              pw.SizedBox(height: 15),
              ...(data['checklist'] as Map<String, dynamic>).entries.map((e) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Row(
                    children: [
                      // Vykreslíme malý barevný puntík místo složité ikony
                      pw.Container(
                        width: 12, height: 12,
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: e.value ? PdfColors.green : PdfColors.red,
                        )
                      ),
                      pw.SizedBox(width: 10),
                      pw.Text(e.key, style: pw.TextStyle(font: fontRegular, fontSize: 14)),
                      pw.Spacer(),
                      pw.Text(e.value ? 'ANO' : 'NE', style: pw.TextStyle(font: fontBold, fontSize: 14, color: e.value ? PdfColors.green : PdfColors.red)),
                    ]
                  )
                );
              }),
              
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 20),

              // Poznámky
              if (data['poznamky'] != null && data['poznamky'].toString().isNotEmpty) ...[
                pw.Text('Poznámky k příjmu:', style: pw.TextStyle(font: fontBold, fontSize: 16)),
                pw.SizedBox(height: 10),
                pw.Text(data['poznamky'].toString(), style: pw.TextStyle(font: fontRegular, fontSize: 12, color: PdfColors.grey800)),
              ] else ...[
                pw.Text('Bez dodatečných poznámek.', style: pw.TextStyle(font: fontRegular, fontSize: 12, color: PdfColors.grey600)),
              ],
              
              pw.Spacer(),
              
              // Patička
              pw.Center(
                child: pw.Text('Vygenerováno aplikací FastCheck', style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey500))
              )
            ],
          );
        },
      ),
    );

    // Otevře dialog pro sdílení / uložení PDF 
    // (Na webu to stáhne soubor nebo otevře náhled, na mobilu to nabídne sdílení)
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Protokol_${data['cislo_zakazky']}.pdf',
    );
  }
}