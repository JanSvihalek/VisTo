import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import '../core/constants.dart';
import '../core/pdf_generator.dart';

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

              final allDocs = snapshot.data!.docs;
              final filteredDocs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (data['stav_zakazky'] != 'Dokončeno') return false;

                final cislo =
                    data['cislo_zakazky']?.toString().toLowerCase() ?? '';
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final vin = data['vin']?.toString().toLowerCase() ?? '';
                return cislo.contains(_searchQuery) ||
                    spz.contains(_searchQuery) ||
                    vin.contains(_searchQuery);
              }).toList();

              // Řazení lokálně
              filteredDocs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['cas_prijeti'] as Timestamp?;
                final timeB = dataB['cas_prijeti'] as Timestamp?;
                if (timeA == null && timeB == null) return 0;
                if (timeA == null) return 1;
                if (timeB == null) return -1;
                return timeB.compareTo(timeA);
              });

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
                            ? 'Zatím žádné zakázky v historii'
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
                  final zpusobUkonceni = data['zpusob_ukonceni'] ?? '';
                  String stavText = 'Dokončeno';
                  Color stavBarva = Colors.green;

                  if (zpusobUkonceni == 'zruseno') {
                    stavText = 'Zrušeno';
                    stavBarva = Colors.red;
                  } else if (zpusobUkonceni == 'bez_faktury') {
                    stavText = 'Bez faktury';
                    stavBarva = Colors.grey;
                  }

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
                              color: stavBarva.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: stavBarva, width: 0.5),
                            ),
                            child: Text(
                              stavText,
                              style: TextStyle(
                                color: stavBarva,
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

    final zpusobUkonceni = data['zpusob_ukonceni'] ?? '';
    final bool maFakturu = zpusobUkonceni == 'faktura';

    double celkovaCenaSDph = 0.0;
    if (maFakturu) {
      final praceForCalc = data['provedene_prace'] as List<dynamic>? ?? [];
      for (var p in praceForCalc) {
        celkovaCenaSDph += (p['cena_s_dph'] ?? 0.0).toDouble();
        final dily = p['pouzite_dily'] as List<dynamic>? ?? [];
        for (var dil in dily) {
          double pocet = (dil['pocet'] ?? 1.0).toDouble();
          double cenaSDph = (dil['cena_s_dph'] ?? 0.0).toDouble();
          celkovaCenaSDph += (pocet * cenaSDph);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 30,
            right: 30,
            top: 30,
            bottom: MediaQuery.of(context).viewInsets.bottom + 30,
          ),
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
                  Expanded(
                    child: Text(
                      'Zakázka ${data['cislo_zakazky']}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (maFakturu)
                        IconButton(
                          icon: const Icon(
                            Icons.receipt_long,
                            color: Colors.green,
                            size: 28,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Náhled faktury'),
                                  ),
                                  body: PdfPreview(
                                    build: (format) => _generateInvoicePdf(
                                      format,
                                      data,
                                      celkovaCenaSDph,
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
                          tooltip: 'Zobrazit fakturu',
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.picture_as_pdf,
                          color: Colors.redAccent,
                          size: 28,
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
                                  build: (format) =>
                                      _exportHistoryToPdf(format, data),
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
                        tooltip: 'Protokol o opravě',
                      ),
                    ],
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
              if (data['znacka'] != null &&
                  data['znacka'].toString().isNotEmpty)
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

  Future<Uint8List> _exportHistoryToPdf(
    PdfPageFormat format,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    String hlavickaNazev = 'Torkis';
    String hlavickaIco = '';
    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists) {
        hlavickaNazev = nastaveniDoc.data()?['nazev_servisu'] ?? 'Torkis';
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
        if (response.statusCode == 200)
          podpisImage = pw.MemoryImage(response.bodyBytes);
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
                    'Vygenerováno aplikací Torkis',
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
                  'Vygenerováno aplikací Torkis',
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

  Future<Uint8List> _generateInvoicePdf(
    PdfPageFormat format,
    Map<String, dynamic> data,
    double celkovaCastka,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    String dodavatelNazev = 'Neznámý servis';
    String dodavatelIco = '';
    String dodavatelDic = '';
    String dodavatelAdresa = '';
    String dodavatelMesto = '';
    String dodavatelTelefon = '';
    String dodavatelEmail = '';
    String dodavatelBanka = '';
    String dodavatelRegistrace = '';
    bool jePlatceDph = false;

    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists) {
        final nd = nastaveniDoc.data()!;
        dodavatelNazev = nd['nazev_servisu'] ?? dodavatelNazev;
        dodavatelIco = nd['ico_servisu'] ?? '';
        dodavatelDic = nd['dic_servisu'] ?? '';
        dodavatelAdresa = nd['adresa_servisu'] ?? '';
        dodavatelMesto = nd['mesto_servisu'] ?? '';
        dodavatelTelefon = nd['telefon_servisu'] ?? '';
        dodavatelEmail = nd['email_servisu'] ?? '';
        dodavatelBanka = nd['banka_servisu'] ?? '';
        dodavatelRegistrace = nd['registrace_servisu'] ?? '';
        jePlatceDph = nd['platce_dph'] ?? false;
      }
    }

    final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
    final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];

    final cisloFaktury =
        'FAK-${data['cislo_zakazky']?.toString().replaceAll(RegExp(r'^[A-Z]+-'), '') ?? DateTime.now().millisecondsSinceEpoch}';

    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final formaUhrady = data['forma_uhrady']?.toString() ?? 'Převodem';
    final now = DateTime.now();
    final splatnost = (formaUhrady == 'Hotově' || formaUhrady == 'Kartou')
        ? now
        : now.add(const Duration(days: 14));

    final String nadpisDokladu = jePlatceDph
        ? 'FAKTURA - DAŇOVÝ DOKLAD'
        : 'FAKTURA';
    final String dodavatelOznSleva = jePlatceDph ? '' : 'Neplátce DPH';

    final tableHeaders = jePlatceDph
        ? ['Popis položky', 'Množství', 'Cena/mj. bez DPH', 'Celkem s DPH']
        : ['Popis položky', 'Množství', 'Cena/mj.', 'Celkem'];

    final List<List<String>> tableData = [];

    double celkemBezDph = 0;
    double celkemDph = 0;

    for (var prace in provedenePrace) {
      double pCenaSDph = (prace['cena_s_dph'] ?? 0.0).toDouble();
      double pCenaBezDph = (prace['cena_bez_dph'] ?? 0.0).toDouble();

      celkemBezDph += pCenaBezDph;
      celkemDph += (pCenaSDph - pCenaBezDph);

      tableData.add([
        'Práce: ${prace['nazev']}',
        '1 ks',
        jePlatceDph
            ? '${pCenaBezDph.toStringAsFixed(2)} Kč'
            : '${pCenaSDph.toStringAsFixed(2)} Kč',
        '${pCenaSDph.toStringAsFixed(2)} Kč',
      ]);

      final dily = prace['pouzite_dily'] as List<dynamic>? ?? [];
      for (var dil in dily) {
        double dPocet = (dil['pocet'] ?? 1.0).toDouble();
        double dCenaSDph = (dil['cena_s_dph'] ?? 0.0).toDouble();
        double dCenaBezDph = (dil['cena_bez_dph'] ?? 0.0).toDouble();
        double dRadkaCelkemSDph = dPocet * dCenaSDph;
        double dRadkaCelkemBezDph = dPocet * dCenaBezDph;

        celkemBezDph += dRadkaCelkemBezDph;
        celkemDph += (dRadkaCelkemSDph - dRadkaCelkemBezDph);

        tableData.add([
          'Materiál: ${dil['nazev']} ${dil['cislo'].toString().isNotEmpty ? '(${dil['cislo']})' : ''}',
          '$dPocet ks',
          jePlatceDph
              ? '${dCenaBezDph.toStringAsFixed(2)} Kč'
              : '${dCenaSDph.toStringAsFixed(2)} Kč',
          '${dRadkaCelkemSDph.toStringAsFixed(2)} Kč',
        ]);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nadpisDokladu,
                  style: pw.TextStyle(
                    font: fontBold,
                    fontSize: 24,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.Text(
                  'Číslo: $cisloFaktury',
                  style: pw.TextStyle(font: fontBold, fontSize: 16),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'DODAVATEL:',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 10,
                                color: PdfColors.grey600,
                              ),
                            ),
                            if (!jePlatceDph)
                              pw.Text(
                                dodavatelOznSleva,
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 10,
                                  color: PdfColors.blue800,
                                ),
                              ),
                          ],
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          dodavatelNazev,
                          style: pw.TextStyle(font: fontBold, fontSize: 14),
                        ),
                        pw.Text(
                          dodavatelAdresa,
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        pw.Text(
                          dodavatelMesto,
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'IČO: $dodavatelIco',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        if (jePlatceDph && dodavatelDic.isNotEmpty)
                          pw.Text(
                            'DIČ: $dodavatelDic',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 11,
                            ),
                          ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Tel: $dodavatelTelefon',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        pw.Text(
                          'E-mail: $dodavatelEmail',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ODBĚRATEL:',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 10,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          zakaznik['jmeno']?.toString() ?? 'Neznámý zákazník',
                          style: pw.TextStyle(font: fontBold, fontSize: 14),
                        ),
                        pw.Text(
                          zakaznik['adresa']?.toString() ?? '',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        pw.SizedBox(height: 5),
                        if (zakaznik['ico'] != null &&
                            zakaznik['ico'].toString().isNotEmpty)
                          pw.Text(
                            'IČO: ${zakaznik['ico']}',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 11,
                            ),
                          ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Tel: ${zakaznik['telefon'] ?? ''}',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                        pw.Text(
                          'E-mail: ${zakaznik['email'] ?? ''}',
                          style: pw.TextStyle(font: fontRegular, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Bankovní účet:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        dodavatelBanka.isNotEmpty
                            ? dodavatelBanka
                            : 'Není vyplněn',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Variabilní symbol:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        cisloFaktury.replaceAll(RegExp(r'[^0-9]'), ''),
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Vztahuje se k zakázce:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        '${data['cislo_zakazky']} (SPZ: ${data['spz']})',
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        jePlatceDph
                            ? 'Datum vystavení / DUZP:'
                            : 'Datum vystavení:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        DateFormat('dd.MM.yyyy').format(now),
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Datum splatnosti:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.red,
                        ),
                      ),
                      pw.Text(
                        DateFormat('dd.MM.yyyy').format(splatnost),
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: PdfColors.red,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Forma úhrady:',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                      pw.Text(
                        formaUhrady,
                        style: pw.TextStyle(font: fontBold, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableData,
              headerStyle: pw.TextStyle(
                font: fontBold,
                fontSize: 11,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue800,
              ),
              cellStyle: pw.TextStyle(font: fontRegular, fontSize: 10),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            ),
            pw.SizedBox(height: 30),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 250,
                  child: pw.Column(
                    children: [
                      if (jePlatceDph) ...[
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Celkem bez DPH:',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 11,
                              ),
                            ),
                            pw.Text(
                              '${celkemBezDph.toStringAsFixed(2)} Kč',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        pw.Divider(color: PdfColors.grey300),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'DPH (21%):',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 11,
                              ),
                            ),
                            pw.Text(
                              '${celkemDph.toStringAsFixed(2)} Kč',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                      pw.Divider(color: PdfColors.black, thickness: 1.5),
                      pw.SizedBox(height: 5),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'CELKEM K ÚHRADĚ:',
                            style: pw.TextStyle(font: fontBold, fontSize: 14),
                          ),
                          pw.Text(
                            '${celkovaCastka.toStringAsFixed(2)} Kč',
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 16,
                              color: PdfColors.blue800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),

            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'Děkujeme Vám za využití našich služeb.',
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 10,
                  color: PdfColors.grey600,
                ),
              ),
            ),
            if (dodavatelRegistrace.isNotEmpty) ...[
              pw.SizedBox(height: 5),
              pw.Center(
                child: pw.Text(
                  dodavatelRegistrace,
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 8,
                    color: PdfColors.grey500,
                  ),
                ),
              ),
            ],
            pw.SizedBox(height: 5),
            pw.Center(
              child: pw.Text(
                'Vygenerováno systémem Torkis.',
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 8,
                  color: PdfColors.grey400,
                ),
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
