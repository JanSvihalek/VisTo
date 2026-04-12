import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:html' as html;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../core/constants.dart';

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

              // Řazení lokálně
              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['cas_prijeti'] as Timestamp?;
                final timeB = dataB['cas_prijeti'] as Timestamp?;
                if (timeA == null && timeB == null) return 0;
                if (timeA == null) return 1;
                if (timeB == null) return -1;
                return timeB.compareTo(timeA);
              });

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

  void _openAddWorkDialog(
    BuildContext context, {
    String? initialTitle,
    Map<String, dynamic>? existingWork,
    int? editIndex,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddWorkScreen(
          documentId: documentId,
          zakazkaId: zakazkaId,
          initialTitle: initialTitle,
          existingWork: existingWork,
          editIndex: editIndex,
        ),
      ),
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
    if (confirm == true)
      await FirebaseFirestore.instance
          .collection('zakazky')
          .doc(documentId)
          .update({
            'provedene_prace': FieldValue.arrayRemove([workItem]),
          });
  }

  Future<void> _zmenitStav(BuildContext context, String novyStav) async {
    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc(documentId)
        .update({'stav_zakazky': novyStav});
  }

  void _ukoncitZakazkuDialog(BuildContext context) {
    String vybranaPlatba = 'Převodem';
    final moznostiPlatby = ['Převodem', 'Hotově', 'Kartou'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Ukončení zakázky',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Způsob úhrady:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: vybranaPlatba,
                    isExpanded: true,
                    items: moznostiPlatby
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => vybranaPlatba = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Vyberte, jakým způsobem chcete tuto zakázku uzavřít a přesunout do historie:',
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                onPressed: () =>
                    _zpracovatUkonceni(context, 'faktura', vybranaPlatba),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Předat k fakturaci'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () =>
                    _zpracovatUkonceni(context, 'bez_faktury', vybranaPlatba),
                icon: const Icon(Icons.handshake),
                label: const Text('Dokončit BEZ fakturace'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _zpracovatUkonceni(context, 'zruseno', ''),
                icon: const Icon(Icons.cancel, color: Colors.red),
                label: const Text(
                  'Nerealizuje se (Zrušit)',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ZPĚT'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _zpracovatUkonceni(
    BuildContext context,
    String zpusob,
    String platba,
  ) async {
    await FirebaseFirestore.instance
        .collection('zakazky')
        .doc(documentId)
        .update({
          'stav_zakazky': 'Dokončeno',
          'zpusob_ukonceni': zpusob,
          'forma_uhrady': platba,
        });

    if (context.mounted) {
      Navigator.pop(context);
      Navigator.pop(context);

      String message = 'Zakázka byla ukončena a přesunuta do Historie.';
      if (zpusob == 'faktura')
        message = 'Zakázka přesunuta do záložky Fakturace.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
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

  Future<Uint8List> _exportToPdf(
    PdfPageFormat format,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrlsByCategory,
  ) async {
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
        if (response.statusCode == 200)
          podpisImage = pw.MemoryImage(response.bodyBytes);
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

                double celkemPracePdf = (prace['cena_s_dph'] ?? 0.0).toDouble();
                double celkemDilyPdf = 0.0;
                for (var dil in dily) {
                  double pocet = (dil['pocet'] ?? 1.0).toDouble();
                  double cenaKs = (dil['cena_s_dph'] ?? 0.0).toDouble();
                  celkemDilyPdf += (pocet * cenaKs);
                }
                double celkemUkonPdf = celkemPracePdf + celkemDilyPdf;

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
                            '${prace['nazev']} (Celkem: ${celkemUkonPdf.toStringAsFixed(2)} Kč)',
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
                                  '• ${dil['nazev']} (${dil['cislo']}) - ${dil['pocet']} ks - ${dil['cena_s_dph']} Kč',
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
  'Vygenerováno aplikací Fixio', // <-- Zde
  style: pw.TextStyle(
// ...
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
                  'Vygenerováno aplikací Fixio',
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
    return pdf.save();
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
          final pozadavky =
              data['pozadavky_zakaznika'] as List<dynamic>? ?? []; // NOVÉ
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
                                .where((s) => s != 'Dokončeno')
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
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Scaffold(
                              appBar: AppBar(
                                title: const Text('Náhled protokolu'),
                              ),
                              body: PdfPreview(
                                build: (format) => _exportToPdf(
                                  format,
                                  data,
                                  stav,
                                  zakaznik,
                                  imageUrlsByCategoryRaw,
                                ),
                                allowSharing: true,
                                allowPrinting: true,
                                canChangeOrientation: false,
                                canChangePageFormat: false,
                                loadingWidget: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      tooltip: 'Zobrazit PDF',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // --- ZMĚNA: Přepis na jeden velký ListView pro požadavky i úkony ---
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // --- ZPRACOVÁNÍ POŽADAVKŮ ---
                    if (pozadavky.isNotEmpty) ...[
                      const Text(
                        'Požadavky od zákazníka (k řešení)',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...pozadavky.map(
                        (p) => Card(
                          color: Colors.orange.withOpacity(0.05),
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: ListTile(
                            title: Text(
                              p.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: ElevatedButton.icon(
                              icon: const Icon(Icons.build, size: 18),
                              label: const Text('ZPRACOVAT'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _openAddWorkDialog(
                                context,
                                initialTitle: p.toString(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 40),
                    ],

                    // --- ZAZNAMENANÉ ÚKONY ---
                    const Text(
                      'Zaznamenané úkony',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (provedenePrace.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 30),
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
                    else
                      ...List.generate(provedenePrace.length, (index) {
                        // Invertujeme index pro zobrazení od nejnovějšího
                        final trueIndex = provedenePrace.length - 1 - index;
                        final prace = provedenePrace[trueIndex];
                        final fotky =
                            prace['fotografie_urls'] as List<dynamic>? ?? [];
                        final dily =
                            prace['pouzite_dily'] as List<dynamic>? ?? [];

                        double celkemPrace = (prace['cena_s_dph'] ?? 0.0)
                            .toDouble();
                        double celkemDily = 0.0;
                        for (var dil in dily) {
                          double pocet = (dil['pocet'] ?? 1.0).toDouble();
                          double cenaKs = (dil['cena_s_dph'] ?? 0.0).toDouble();
                          celkemDily += (pocet * cenaKs);
                        }
                        double celkemUkon = celkemPrace + celkemDily;

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
                                        '${prace['nazev']} (Celkem: ${celkemUkon.toStringAsFixed(2)} Kč)',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    // TLAČÍTKO EDITACE PŘIDÁNO SEM
                                    IconButton(
                                      onPressed: () => _openAddWorkDialog(
                                        context,
                                        existingWork: prace,
                                        editIndex: trueIndex,
                                      ),
                                      icon: const Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                        size: 20,
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
                                    prace['delka_prace'].toString().isNotEmpty)
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
                                            '• ${dil['nazev']} (${dil['cislo']}) - ${dil['pocet']} ks - ${dil['cena_s_dph']} Kč',
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
                                        itemBuilder: (c, i) => GestureDetector(
                                          onTap: () => html.window.open(
                                            fotky[i],
                                            "_blank",
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                      }),
                  ],
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
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _ukoncitZakazkuDialog(context),
                          icon: const Icon(Icons.flag),
                          label: const Text(
                            'UKONČIT',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openAddWorkDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'PŘIDAT ÚKON',
                            style: TextStyle(fontWeight: FontWeight.bold),
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
                    ],
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

class AddWorkScreen extends StatefulWidget {
  final String documentId;
  final String zakazkaId;
  // --- NOVÉ PROMENNÉ PRO EDITACI A POŽADAVKY ---
  final String? initialTitle;
  final Map<String, dynamic>? existingWork;
  final int? editIndex;

  const AddWorkScreen({
    super.key,
    required this.documentId,
    required this.zakazkaId,
    this.initialTitle,
    this.existingWork,
    this.editIndex,
  });

  @override
  State<AddWorkScreen> createState() => _AddWorkScreenState();
}

class _AddWorkScreenState extends State<AddWorkScreen> {
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
  bool _jePlatceDph = false;

  double _celkovaCenaSDph = 0.0;

  @override
  void initState() {
    super.initState();
    _nactiHodinovouSazbu();

    // Pokud jsme rozklikli požadavek, předvyplníme název
    if (widget.initialTitle != null) {
      _nazevController.text = widget.initialTitle!;
    }

    // Pokud editujeme existující úkon, předvyplníme vše
    if (widget.existingWork != null) {
      _nazevController.text = widget.existingWork!['nazev'] ?? '';
      _popisController.text = widget.existingWork!['popis'] ?? '';
      _delkaController.text = widget.existingWork!['delka_prace'] ?? '';
      _praceCenaBezDphController.text =
          (widget.existingWork!['cena_bez_dph'] ?? 0.0).toStringAsFixed(2);
      _praceCenaSDphController.text =
          (widget.existingWork!['cena_s_dph'] ?? 0.0).toStringAsFixed(2);

      final dily = widget.existingWork!['pouzite_dily'] as List<dynamic>? ?? [];
      for (var d in dily) {
        final input = DilInput();
        input.cislo.text = d['cislo'] ?? '';
        input.nazev.text = d['nazev'] ?? '';
        input.pocet.text = (d['pocet'] ?? 1.0).toString();
        input.cenaBezDph.text = (d['cena_bez_dph'] ?? 0.0).toStringAsFixed(2);
        input.cenaSDph.text = (d['cena_s_dph'] ?? 0.0).toStringAsFixed(2);
        _dilyInputs.add(input);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prepocitatCelkem();
      });
    }
  }

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
          _jePlatceDph = doc.data()?['platce_dph'] ?? false;
        });
      }
    }
  }

  void _prepocitatCelkovouCenu() {
    double celkemPrace =
        double.tryParse(_praceCenaSDphController.text.replaceAll(',', '.')) ??
        0.0;
    double celkemDily = 0.0;

    for (var dil in _dilyInputs) {
      double pocet =
          double.tryParse(dil.pocet.text.replaceAll(',', '.')) ?? 0.0;
      double cenaKs =
          double.tryParse(dil.cenaSDph.text.replaceAll(',', '.')) ?? 0.0;
      celkemDily += (pocet * cenaKs);
    }

    setState(() {
      _celkovaCenaSDph = celkemPrace + celkemDily;
    });
  }

  void _vypocitejCenuPraceZ_Hodin(String hodiny) {
    double pocetHodin = double.tryParse(hodiny.replaceAll(',', '.')) ?? 0.0;
    double cenaBezDph = pocetHodin * _hodinovaSazba;

    double sDph = _jePlatceDph ? (cenaBezDph * 1.21) : cenaBezDph;

    _praceCenaBezDphController.text = cenaBezDph.toStringAsFixed(2);
    _praceCenaSDphController.text = sDph.toStringAsFixed(2);
    _prepocitatCelkem();
  }

  void _prepocitatDphPrace(String bezDphText) {
    double bezDph = double.tryParse(bezDphText.replaceAll(',', '.')) ?? 0.0;
    double sDph = _jePlatceDph ? (bezDph * 1.21) : bezDph;
    _praceCenaSDphController.text = sDph.toStringAsFixed(2);
    _prepocitatCelkem();
  }

  void _prepocitatDphDilu(DilInput dil, String bezDphText) {
    double bezDph = double.tryParse(bezDphText.replaceAll(',', '.')) ?? 0.0;
    double sDph = _jePlatceDph ? (bezDph * 1.21) : bezDph;
    dil.cenaSDph.text = sDph.toStringAsFixed(2);
    _prepocitatCelkem();
  }

  void _prepocitatCelkem() {
    _prepocitatCelkovouCenu();
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
    if (_nazevController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Zadejte alespoň název úkonu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      List<String> uploadedUrls = [];

      // Nahrání případných NOVÝCH fotek
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

      // Pokud editujeme, spojíme staré fotky s novými
      List<String> finalFotky = [];
      if (widget.existingWork != null) {
        finalFotky.addAll(
          List<String>.from(widget.existingWork!['fotografie_urls'] ?? []),
        );
      }
      finalFotky.addAll(uploadedUrls);

      Map<String, dynamic> novyUkon = {
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
        'cas':
            widget.existingWork?['cas'] ??
            Timestamp.now(), // Při editaci zachovat původní čas
        'fotografie_urls': finalFotky,
      };

      // ROZHODOVÁNÍ: Editace nebo nový zápis
      if (widget.editIndex != null) {
        // Editace starého úkonu (bezpečná úprava pole přes index)
        final doc = await FirebaseFirestore.instance
            .collection('zakazky')
            .doc(widget.documentId)
            .get();
        List<dynamic> prace = List.from(doc.data()?['provedene_prace'] ?? []);
        if (widget.editIndex! >= 0 && widget.editIndex! < prace.length) {
          prace[widget.editIndex!] = novyUkon;
          await FirebaseFirestore.instance
              .collection('zakazky')
              .doc(widget.documentId)
              .update({'provedene_prace': prace});
        }
      } else {
        // Zápis nového úkonu
        Map<String, dynamic> updates = {
          'provedene_prace': FieldValue.arrayUnion([novyUkon]),
        };

        // Pokud jsme "Zpracovávali" požadavek z příjmu, rovnou ho smažeme ze seznamu požadavků
        if (widget.initialTitle != null) {
          updates['pozadavky_zakaznika'] = FieldValue.arrayRemove([
            widget.initialTitle,
          ]);
        }

        await FirebaseFirestore.instance
            .collection('zakazky')
            .doc(widget.documentId)
            .update(updates);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Chyba: $e')));
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.existingWork != null ? 'Úprava úkonu' : 'Nová položka dokladu',
        ),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.build, color: Colors.blue),
                              SizedBox(width: 10),
                              Text(
                                'Hlavička úkonu',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            _nazevController,
                            'Název úkonu *',
                            isDark,
                            isBold: true,
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTextField(
                                  _delkaController,
                                  'Čas (hod)',
                                  isDark,
                                  isNumber: true,
                                  onChanged: _vypocitejCenuPraceZ_Hodin,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildTextField(
                                  _praceCenaBezDphController,
                                  _jePlatceDph
                                      ? 'Cena bez DPH'
                                      : 'Cena (bez DPH)',
                                  isDark,
                                  isNumber: true,
                                  onChanged: _prepocitatDphPrace,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildTextField(
                                  _praceCenaSDphController,
                                  _jePlatceDph ? 'Cena s DPH' : 'Konečná cena',
                                  isDark,
                                  isNumber: true,
                                  onChanged: (v) => _prepocitatCelkem(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Card(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.inventory_2, color: Colors.orange),
                              SizedBox(width: 10),
                              Text(
                                'Materiál a díly',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),

                          ...List.generate(_dilyInputs.length, (index) {
                            final dil = _dilyInputs[index];

                            double dPocet =
                                double.tryParse(
                                  dil.pocet.text.replaceAll(',', '.'),
                                ) ??
                                0.0;
                            double dCena =
                                double.tryParse(
                                  dil.cenaSDph.text.replaceAll(',', '.'),
                                ) ??
                                0.0;
                            double rCelkem = dPocet * dCena;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF2C2C2C)
                                    : Colors.grey[50],
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _buildTextField(
                                          dil.cislo,
                                          'Číslo dílu',
                                          isDark,
                                          compact: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 4,
                                        child: _buildTextField(
                                          dil.nazev,
                                          'Název dílu',
                                          isDark,
                                          compact: true,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            dil.dispose();
                                            _dilyInputs.removeAt(index);
                                            _prepocitatCelkem();
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 1,
                                        child: _buildTextField(
                                          dil.pocet,
                                          'Ks',
                                          isDark,
                                          isNumber: true,
                                          compact: true,
                                          onChanged: (v) => _prepocitatCelkem(),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: _buildTextField(
                                          dil.cenaBezDph,
                                          _jePlatceDph
                                              ? 'Bez DPH/ks'
                                              : 'Cena/ks',
                                          isDark,
                                          isNumber: true,
                                          compact: true,
                                          onChanged: (v) =>
                                              _prepocitatDphDilu(dil, v),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        flex: 2,
                                        child: _buildTextField(
                                          dil.cenaSDph,
                                          _jePlatceDph
                                              ? 'S DPH/ks'
                                              : 'Konečná/ks',
                                          isDark,
                                          isNumber: true,
                                          compact: true,
                                          onChanged: (v) => _prepocitatCelkem(),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Celkem za materiál: ',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${rCelkem.toStringAsFixed(2)} Kč',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),

                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _dilyInputs.add(DilInput())),
                            icon: const Icon(Icons.add),
                            label: const Text('Přidat řádek materiálu'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Card(
                    color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.more_horiz, color: Colors.purple),
                              SizedBox(width: 10),
                              Text(
                                'Doplňující informace',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          _buildTextField(
                            _popisController,
                            'Interní poznámka k úkonu',
                            isDark,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Fotodokumentace úkonu:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
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
                                    child: const Icon(
                                      Icons.add_a_photo,
                                      color: Colors.blue,
                                    ),
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
                                      border: Border.all(
                                        color: Colors.blueGrey,
                                      ),
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
                                          margin: const EdgeInsets.only(
                                            right: 10,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
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
                                            onTap: () => setState(
                                              () => _workImages.removeAt(i),
                                            ),
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF121212) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Celkem za položku',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        Text(
                          '${_celkovaCenaSDph.toStringAsFixed(2)} Kč',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveWork,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _isSaving ? 'UKLÁDÁM...' : 'ULOŽIT POLOŽKU',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 25,
                        vertical: 15,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    bool isDark, {
    bool isNumber = false,
    bool isBold = false,
    bool compact = false,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(
        fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        fontSize: isBold ? 16 : 14,
      ),
      decoration: InputDecoration(
        labelText: hint,
        filled: true,
        fillColor: isDark
            ? (compact ? const Color(0xFF1E1E1E) : const Color(0xFF2C2C2C))
            : Colors.white,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 15,
          vertical: compact ? 10 : 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );
  }
}