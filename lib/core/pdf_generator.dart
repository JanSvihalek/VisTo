import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';

enum PdfTyp { protokol, naceneni, faktura }

class GlobalPdfGenerator {
  static String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "-";
    if (timestamp is Timestamp) {
      return DateFormat('dd.MM.yyyy HH:mm').format(timestamp.toDate());
    }
    return "-";
  }

  static Future<Uint8List> generateDocument({
    required Map<String, dynamic> data,
    required String servisNazev,
    required String servisIco,
    required PdfTyp typ,
  }) async {
    final pdf = pw.Document();

    // Načtení fontů pro lepší typografii
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontMedium = await PdfGoogleFonts.robotoMedium();

    final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
    final stavVozidla = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
    final provedenePrace = data['provedene_prace'] as List<dynamic>? ?? [];
    final pozadavky = data['pozadavky_zakaznika'] as List<dynamic>? ?? [];

    // Logika typu dokumentu
    String titulek = "FAKTURA - DAŇOVÝ DOKLAD";
    String cisloDokladu = data['cislo_zakazky']?.toString() ?? '-';
    bool zobrazitCeny = true;

    if (typ == PdfTyp.protokol) {
      titulek = "PROTOKOL O PŘÍJMU";
      zobrazitCeny = false;
    } else if (typ == PdfTyp.naceneni) {
      titulek = "CENOVÁ NABÍDKA";
      zobrazitCeny = true;
    }

    double celkovaSuma = 0.0;

    // --- NAČTENÍ DODATEČNÝCH ÚDAJŮ O SERVISU (DODAVATEL) ---
    String sAdresa = '';
    String sMesto = '';
    String sPsc = '';
    String sTelefon = '';
    String sEmail = '';
    String sDic = '';
    String sBanka = '';
    String sRegistrace = '';

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final docNast = await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(user.uid)
            .get();
        if (docNast.exists) {
          final nd = docNast.data()!;
          servisNazev = nd['nazev_servisu'] ?? servisNazev;
          servisIco = nd['ico_servisu'] ?? servisIco;
          sAdresa = nd['adresa_servisu'] ?? '';
          sMesto = nd['mesto_servisu'] ?? '';
          sPsc = nd['psc_servisu'] ?? '';
          sTelefon = nd['telefon_servisu'] ?? '';
          sEmail = nd['email_servisu'] ?? '';
          sDic = nd['dic_servisu'] ?? '';
          sBanka = nd['banka_servisu'] ?? '';
          sRegistrace = nd['registrace_servisu'] ?? '';
        }
      } catch (e) {
        debugPrint("Chyba načítání detailů servisu: $e");
      }
    }

    // --- NAČTENÍ LOGA ZNAČKY VOZIDLA ---
    pw.MemoryImage? logoImage;
    final znackaNazev = (data['znacka']?.toString() ?? '').trim();
    if (znackaNazev.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('znacka')
            .get();
        String foundLogoUrl = '';
        for (var doc in snap.docs) {
          final d = doc.data();
          final dbNazev = (d['nazev']?.toString() ?? doc.id)
              .trim()
              .toLowerCase();
          if (dbNazev == znackaNazev.toLowerCase()) {
            foundLogoUrl =
                d['logo']?.toString() ?? d['logo_url']?.toString() ?? '';
            break;
          }
        }
        if (foundLogoUrl.isNotEmpty) {
          final resp = await http.get(Uri.parse(foundLogoUrl));
          if (resp.statusCode == 200)
            logoImage = pw.MemoryImage(resp.bodyBytes);
        }
      } catch (e) {
        debugPrint("Chyba načítání loga do PDF: $e");
      }
    }

    // --- NAČTENÍ PODPISU ZÁKAZNÍKA (Pouze pro protokol) ---
    pw.MemoryImage? podpisImage;
    if (typ == PdfTyp.protokol) {
      final podpisUrl = data['podpis_url']?.toString();
      if (podpisUrl != null && podpisUrl.isNotEmpty) {
        try {
          final resp = await http.get(Uri.parse(podpisUrl));
          if (resp.statusCode == 200)
            podpisImage = pw.MemoryImage(resp.bodyBytes);
        } catch (e) {
          debugPrint("Chyba načítání podpisu do PDF: $e");
        }
      }
    }

    // Pomocná funkce pro informační řádky u vozidla
    pw.Widget _buildInfoRow(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 60,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value,
                style: pw.TextStyle(
                  font: fontMedium,
                  fontSize: 10,
                  color: PdfColors.grey900,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
        build: (pw.Context context) => [
          // --- HLAVIČKA (Typ dokumentu a Číslo) ---
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                titulek,
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 22,
                  color: PdfColors.blue800,
                  letterSpacing: 1.0,
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Číslo: $cisloDokladu',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 14,
                      color: PdfColors.grey800,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Vystaveno: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                    style: pw.TextStyle(
                      font: fontMedium,
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 30),

          // --- MODERNÍ INFORMAČNÍ KARTY (Dodavatel vs Odběratel) ---
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // DODAVATEL (Tento Servis)
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey200),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DODAVATEL',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 10,
                          color: PdfColors.blue700,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        servisNazev,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        sAdresa,
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        '$sPsc $sMesto',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'IČO: $servisIco',
                        style: pw.TextStyle(
                          font: fontMedium,
                          fontSize: 10,
                          color: PdfColors.grey800,
                        ),
                      ),
                      if (sDic.isNotEmpty)
                        pw.Text(
                          'DIČ: $sDic',
                          style: pw.TextStyle(
                            font: fontMedium,
                            fontSize: 10,
                            color: PdfColors.grey800,
                          ),
                        ),
                      pw.SizedBox(height: 6),
                      if (sTelefon.isNotEmpty)
                        pw.Text(
                          'Tel: $sTelefon',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                      if (sEmail.isNotEmpty)
                        pw.Text(
                          'E-mail: $sEmail',
                          style: pw.TextStyle(
                            font: fontRegular,
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 20),

              // ODBĚRATEL (Zákazník)
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey200),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ODBĚRATEL',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 10,
                          color: PdfColors.blue700,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        zakaznik['jmeno'] ?? 'Neuvedeno',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        '${zakaznik['ulice'] ?? ''}',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.Text(
                        '${zakaznik['psc'] ?? ''} ${zakaznik['mesto'] ?? ''}',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      if (zakaznik['ico'] != null &&
                          zakaznik['ico'].toString().isNotEmpty)
                        pw.Text(
                          'IČO: ${zakaznik['ico']}',
                          style: pw.TextStyle(
                            font: fontMedium,
                            fontSize: 10,
                            color: PdfColors.grey800,
                          ),
                        ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        zakaznik['telefon'] ?? '',
                        style: pw.TextStyle(
                          font: fontMedium,
                          fontSize: 10,
                          color: PdfColors.grey800,
                        ),
                      ),
                      pw.Text(
                        zakaznik['email'] ?? '',
                        style: pw.TextStyle(
                          font: fontRegular,
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // --- KARTA VOZIDLA ---
          pw.Container(
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F8FAFC'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey200),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VOZIDLO & ZAKÁZKA',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 10,
                          color: PdfColors.blue700,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        '${data['znacka'] ?? ''} ${data['model'] ?? ''}',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 13,
                          color: PdfColors.grey900,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      _buildInfoRow('SPZ:', data['spz'] ?? ''),
                      _buildInfoRow('VIN:', data['vin'] ?? '-'),
                      _buildInfoRow(
                        'Přijato:',
                        _formatDate(data['cas_prijeti']),
                      ),
                    ],
                  ),
                ),
                // Zobrazení loga značky
                if (logoImage != null) ...[
                  pw.SizedBox(width: 10),
                  pw.Container(
                    width: 50,
                    height: 50,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // --- DETAILNÍ STAV VOZIDLA (Jen pro protokol) ---
          if (typ == PdfTyp.protokol) ...[
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'STAV PŘI PŘÍJMU',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 10,
                      color: PdfColors.grey600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Tachometr: ${stavVozidla['tachometr'] ?? "-"} km',
                        style: pw.TextStyle(font: fontMedium, fontSize: 10),
                      ),
                      pw.Text(
                        'Palivo: ${stavVozidla['nadrz'] ?? "-"} %',
                        style: pw.TextStyle(font: fontMedium, fontSize: 10),
                      ),
                      pw.Text(
                        'STK do: ${stavVozidla['stk_mesic'] ?? "-"}/${stavVozidla['stk_rok'] ?? "-"}',
                        style: pw.TextStyle(font: fontMedium, fontSize: 10),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Hloubka pneu (mm): LP: ${stavVozidla['pneu_lp'] ?? "-"} | PP: ${stavVozidla['pneu_pp'] ?? "-"} | LZ: ${stavVozidla['pneu_lz'] ?? "-"} | PZ: ${stavVozidla['pneu_pz'] ?? "-"}',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),

                  if (stavVozidla['poskozeni'] != null) ...[
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Zaznamenaná poškození: ${stavVozidla['poskozeni'] is List ? (stavVozidla['poskozeni'] as List).join(", ") : stavVozidla['poskozeni']}',
                      style: pw.TextStyle(
                        font: fontMedium,
                        fontSize: 9,
                        color: PdfColors.red700,
                      ),
                    ),
                  ],
                  if (data['poznamky'] != null &&
                      data['poznamky'].toString().isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Poznámka: ${data['poznamky']}',
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: 9,
                        color: PdfColors.grey800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 25),
          ],

          // --- MODERNÍ TABULKA ÚKONŮ ---
          pw.Text(
            zobrazitCeny ? 'ROZPIS POLOŽEK' : 'POŽADOVANÉ ÚKONY',
            style: pw.TextStyle(
              font: fontBold,
              fontSize: 12,
              color: PdfColors.grey800,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: 10),

          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              if (zobrazitCeny) 1: const pw.FlexColumnWidth(1),
              if (zobrazitCeny) 2: const pw.FlexColumnWidth(1.5),
            },
            children: [
              // Záhlaví tabulky
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 1),
                  ),
                ),
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: pw.Text(
                      'Popis',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                  if (zobrazitCeny) ...[
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        'Množství',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: pw.Text(
                        'Celkem s DPH',
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Řádky pro Protokol
              if (!zobrazitCeny)
                ...pozadavky.map(
                  (p) => pw.TableRow(
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColor.fromHex('#F1F5F9'),
                          width: 1,
                        ),
                      ),
                    ),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              '• ',
                              style: pw.TextStyle(
                                font: fontBold,
                                fontSize: 12,
                                color: PdfColors.blue600,
                              ),
                            ),
                            pw.Expanded(
                              child: pw.Text(
                                p.toString(),
                                style: pw.TextStyle(
                                  font: fontMedium,
                                  fontSize: 11,
                                  color: PdfColors.grey900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Řádky pro Fakturu/Nacenění
              if (zobrazitCeny)
                ...provedenePrace.expand((prace) {
                  double cPrace = (prace['cena_s_dph'] ?? 0.0).toDouble();
                  celkovaSuma += cPrace;
                  final dily = prace['pouzite_dily'] as List<dynamic>? ?? [];

                  return [
                    // Hlavní úkon (Práce)
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(
                            top: 10,
                            bottom: 4,
                            left: 4,
                            right: 4,
                          ),
                          child: pw.Text(
                            prace['nazev'],
                            style: pw.TextStyle(font: fontBold, fontSize: 10),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(
                            top: 10,
                            bottom: 4,
                            left: 4,
                            right: 4,
                          ),
                          child: pw.Text(
                            '${prace['delka_prace'] ?? 1} h',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(
                            top: 10,
                            bottom: 4,
                            left: 4,
                            right: 4,
                          ),
                          child: pw.Text(
                            '${cPrace.toStringAsFixed(2)} Kč',
                            textAlign: pw.TextAlign.right,
                            style: pw.TextStyle(font: fontMedium, fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                    // Podpoložky (Díly pod prací)
                    ...dily.map((dil) {
                      double p =
                          (double.tryParse(dil['pocet'].toString()) ?? 1.0);
                      double c =
                          (double.tryParse(dil['cena_s_dph'].toString()) ??
                          0.0);
                      double s = p * c;
                      celkovaSuma += s;

                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: pw.Row(
                              children: [
                                pw.SizedBox(width: 10),
                                pw.Text(
                                  '• ${dil['nazev']}',
                                  style: pw.TextStyle(
                                    font: fontRegular,
                                    fontSize: 9,
                                    color: PdfColors.grey700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: pw.Text(
                              '$p ks',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: pw.Text(
                              '${s.toStringAsFixed(2)} Kč',
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    // Jemná oddělovací linka za každým celým úkonem
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            color: PdfColor.fromHex('#F1F5F9'),
                            width: 1,
                          ),
                        ),
                      ),
                      children: [
                        pw.SizedBox(height: 4),
                        pw.SizedBox(height: 4),
                        pw.SizedBox(height: 4),
                      ],
                    ),
                  ];
                }),
            ],
          ),

          // --- PLATEBNÍ ÚDAJE A VÝRAZNÁ SUMA ---
          if (zobrazitCeny) ...[
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Platební údaje (Pokud je to faktura a máme banku)
                if (typ == PdfTyp.faktura && sBanka.isNotEmpty)
                  pw.Container(
                    width: 220,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F8FAFC'),
                      borderRadius: pw.BorderRadius.circular(8),
                      border: pw.Border.all(color: PdfColors.grey200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'PLATEBNÍ ÚDAJE',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 9,
                            color: PdfColors.grey600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Bankovní účet: $sBanka',
                          style: pw.TextStyle(font: fontBold, fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Variabilní symbol: ${cisloDokladu.replaceAll(RegExp(r'[^0-9]'), '')}',
                          style: pw.TextStyle(font: fontMedium, fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Forma úhrady: ${data['forma_uhrady'] ?? 'Převodem'}',
                          style: pw.TextStyle(font: fontRegular, fontSize: 10),
                        ),
                      ],
                    ),
                  )
                else
                  pw.SizedBox(), // Prázdné místo pro zarovnání doprava
                // Suma
                pw.Container(
                  width: 250,
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 15,
                  ),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#EFF6FF'),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE')),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Celkem k úhradě:',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 12,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Text(
                        '${celkovaSuma.toStringAsFixed(2)} Kč',
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: 16,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          pw.Spacer(),

          // --- PATIČKA ---
          pw.Divider(color: PdfColors.grey300, thickness: 0.5),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Datum vystavení: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                  if (sRegistrace.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      sRegistrace,
                      style: pw.TextStyle(
                        font: fontRegular,
                        fontSize: 8,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ],
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Vygenerováno v systému Torkis.cz',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 8,
                      color: PdfColors.grey400,
                    ),
                  ),
                ],
              ),
              // Zobrazení podpisu (POUZE PRO PROTOKOL)
              if (typ == PdfTyp.protokol)
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Podpis zákazníka (převzetí do servisu):',
                      style: pw.TextStyle(
                        font: fontMedium,
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                    if (podpisImage != null) ...[
                      pw.SizedBox(height: 5),
                      pw.Container(
                        height: 40,
                        width: 120,
                        alignment: pw.Alignment.bottomRight,
                        child: pw.Image(podpisImage, fit: pw.BoxFit.contain),
                      ),
                      pw.Container(
                        width: 120,
                        height: 0.5,
                        color: PdfColors.grey400,
                      ),
                    ] else ...[
                      pw.SizedBox(height: 30),
                      pw.Container(
                        width: 120,
                        height: 0.5,
                        color: PdfColors.grey400,
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
