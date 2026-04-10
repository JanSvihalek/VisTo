import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';

class FakturacePage extends StatefulWidget {
  const FakturacePage({super.key});

  @override
  State<FakturacePage> createState() => _FakturacePageState();
}

class _FakturacePageState extends State<FakturacePage> {
  String _searchQuery = '';

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy').format(dt);
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
                'Fakturace',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Vystavování faktur k dokončeným zakázkám.',
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
                    hintText: 'Hledat SPZ, zákazníka nebo číslo zakázky...',
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
                .where('stav_zakazky', isEqualTo: 'Dokončeno')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                final zpusob = data['zpusob_ukonceni'];
                if (zpusob == 'bez_faktury' || zpusob == 'zruseno')
                  return false;

                final cislo =
                    data['cislo_zakazky']?.toString().toLowerCase() ?? '';
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final zakaznikJmeno = (data['zakaznik']?['jmeno'] ?? '')
                    .toString()
                    .toLowerCase();
                return cislo.contains(_searchQuery) ||
                    spz.contains(_searchQuery) ||
                    zakaznikJmeno.contains(_searchQuery);
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

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 80,
                        color: Colors.grey.withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Žádné dokončené zakázky k fakturaci.'
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
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final zakaznik =
                      data['zakaznik'] as Map<String, dynamic>? ?? {};

                  double celkovaCenaSDph = 0.0;
                  final prace = data['provedene_prace'] as List<dynamic>? ?? [];
                  for (var p in prace) {
                    celkovaCenaSDph += (p['cena_s_dph'] ?? 0.0).toDouble();
                    final dily = p['pouzite_dily'] as List<dynamic>? ?? [];
                    for (var dil in dily) {
                      double pocet = (dil['pocet'] ?? 1.0).toDouble();
                      double cenaSDph = (dil['cena_s_dph'] ?? 0.0).toDouble();
                      celkovaCenaSDph += (pocet * cenaSDph);
                    }
                  }

                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 15),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withOpacity(0.1),
                        foregroundColor: Colors.green,
                        radius: 25,
                        child: const Icon(Icons.check_circle_outline),
                      ),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${data['cislo_zakazky']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Text(
                            '${celkovaCenaSDph.toStringAsFixed(2)} Kč',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Zákazník: ${zakaznik['jmeno'] ?? 'Neznámý'}'),
                            Text(
                              'Vozidlo: ${data['spz']} ${data['znacka'] != null ? '(${data['znacka']})' : ''}',
                            ),
                            Text(
                              'Dokončeno: ${_formatDate(data['cas_prijeti'])}',
                            ),
                          ],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.picture_as_pdf,
                          color: Colors.redAccent,
                          size: 30,
                        ),
                        tooltip: 'Vystavit fakturu',
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
                                ),
                              ),
                            ),
                          );
                        },
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
                'Vygenerováno systémem VisTo.',
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
