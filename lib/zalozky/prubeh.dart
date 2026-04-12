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

// --- IMPORTY PRO PROKLIKY ---
import 'zakaznici.dart';
import 'vozidla.dart';

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
                'Zakázky',
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

  Future<void> _odeslatNaceneni(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrls,
  ) async {
    final emailZakanika = zakaznik['email']?.toString().trim() ?? '';
    if (emailZakanika.isEmpty || !emailZakanika.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Zákazník nemá vyplněný platný e-mail! Vraťte se do úpravy zákazníka.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odeslat cenový odhad?'),
        content: Text(
          'Opravdu chcete odeslat aktuální rozpis prací a dílů na e-mail $emailZakanika jako cenový odhad?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ZRUŠIT'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ODESLAT',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 15),
            Text(
              'Generuji odhad a odesílám e-mail...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Nejste přihlášeni');

      final pdfBytes = await _exportToPdf(
        PdfPageFormat.a4,
        data,
        stav,
        zakaznik,
        imageUrls,
        titulekDokladu: 'Cenový odhad opravy',
      );

      String fileName =
          'cenovy_odhad_${DateTime.now().millisecondsSinceEpoch}.pdf';
      Reference pdfRef = FirebaseStorage.instance.ref().child(
        'servisy/${user.uid}/zakazky/$zakazkaId/$fileName',
      );
      await pdfRef.putData(
        pdfBytes,
        SettableMetadata(contentType: 'application/pdf'),
      );
      String pdfUrl = await pdfRef.getDownloadURL();

      String odesilatelJmeno = 'Servis';
      final docNastaveni = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (docNastaveni.exists) {
        odesilatelJmeno = docNastaveni.data()?['nazev_servisu'] ?? 'Servis';
      }

      await FirebaseFirestore.instance.collection('maily').add({
        'to': emailZakanika,
        'from': '$odesilatelJmeno (přes Torkis) <jan.svihalek00@gmail.com>',
        'replyTo': user.email,
        'message': {
          'subject': 'Cenový odhad opravy vozidla $spz - $odesilatelJmeno',
          'html':
              '''
            <div style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; border: 1px solid #eee; padding: 20px; border-radius: 10px;">
              <h2 style="color: #2196F3; border-bottom: 2px solid #2196F3; padding-bottom: 10px;">Dobrý den,</h2>
              <p>k Vašemu vozidlu <b>$spz</b> jsme zpracovali předběžný rozpočet plánovaných oprav a materiálu.</p>
              <p>V příloze Vám zasíláme odkaz na cenový odhad. Dovolujeme si upozornit, že se nejedná o finální vyúčtování a konečná cena se může po předchozí dohodě ještě měnit.</p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="$pdfUrl" style="background-color: #2196F3; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px; display: inline-block;">Zobrazit cenový odhad</a>
              </div>
              <p>V případě schválení tohoto odhadu nebo jakýchkoliv dotazů na tento e-mail jednoduše odpovězte.</p>
              <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
              <p style="font-size: 12px; color: #777;">Tento e-mail byl vygenerován automaticky systémem <b>Torkis.cz</b> pro servis <b>$odesilatelJmeno</b>.</p>
            </div>
          ''',
        },
      });

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cenový odhad byl úspěšně odeslán zákazníkovi na e-mail.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při odesílání odhadu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _ukoncitZakazkuDialog(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrls,
  ) {
    String vybranaPlatba = 'Převodem';
    final moznostiPlatby = ['Převodem', 'Hotově', 'Kartou'];
    bool isFinishing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Ukončení a vyúčtování',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isFinishing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 15),
                        Text(
                          'Generuji PDF a odesílám e-mail...',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
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
                          .map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => vybranaPlatba = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Zakázka se přesune do Historie. Zákazníkovi se automaticky vygeneruje a odešle PDF vyúčtování.',
                ),
                const SizedBox(height: 15),
                ElevatedButton.icon(
                  onPressed: () async {
                    setState(() => isFinishing = true);
                    await _zpracovatUkonceni(
                      context,
                      'faktura',
                      vybranaPlatba,
                      data,
                      stav,
                      zakaznik,
                      imageUrls,
                    );
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Dokončit a předat k platbě'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    setState(() => isFinishing = true);
                    await _zpracovatUkonceni(
                      context,
                      'zruseno',
                      '',
                      data,
                      stav,
                      zakaznik,
                      imageUrls,
                      zruseno: true,
                    );
                  },
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
            ],
          ),
          actions: [
            if (!isFinishing)
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
    Map<String, dynamic> data,
    Map<String, dynamic> stav,
    Map<String, dynamic> zakaznik,
    Map<String, dynamic> imageUrls, {
    bool zruseno = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String pdfUrl = '';

      if (!zruseno) {
        final pdfBytes = await _exportToPdf(
          PdfPageFormat.a4,
          data,
          stav,
          zakaznik,
          imageUrls,
          titulekDokladu: 'Finální vyúčtování zakázky',
        );

        Reference pdfRef = FirebaseStorage.instance.ref().child(
          'servisy/${user.uid}/zakazky/$zakazkaId/finalni_vyuctovani_$zakazkaId.pdf',
        );
        await pdfRef.putData(
          pdfBytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
        pdfUrl = await pdfRef.getDownloadURL();

        final emailZakanika = zakaznik['email']?.toString().trim() ?? '';
        if (emailZakanika.isNotEmpty && emailZakanika.contains('@')) {
          String odesilatelJmeno = 'Servis';
          final docNastaveni = await FirebaseFirestore.instance
              .collection('nastaveni_servisu')
              .doc(user.uid)
              .get();
          if (docNastaveni.exists) {
            odesilatelJmeno = docNastaveni.data()?['nazev_servisu'] ?? 'Servis';
          }

          await FirebaseFirestore.instance.collection('maily').add({
            'to': emailZakanika,
            'from': '$odesilatelJmeno (přes Torkis) <jan.svihalek00@gmail.com>',
            'replyTo': user.email,
            'message': {
              'subject':
                  'Vozidlo $spz je připraveno k vyzvednutí - $odesilatelJmeno',
              'html':
                  '''
                <div style="font-family: Arial, sans-serif; color: #333; max-width: 600px; margin: 0 auto; border: 1px solid #eee; padding: 20px; border-radius: 10px;">
                  <h2 style="color: #2196F3; border-bottom: 2px solid #2196F3; padding-bottom: 10px;">Dobrý den,</h2>
                  <p>Vaše vozidlo <b>$spz</b> je připraveno k vyzvednutí!</p>
                  <p>V příloze Vám zasíláme odkaz na finální vyúčtování a předávací protokol k Vaší zakázce.</p>
                  <div style="text-align: center; margin: 30px 0;">
                    <a href="$pdfUrl" style="background-color: #2196F3; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-weight: bold; font-size: 16px; display: inline-block;">Zobrazit a stáhnout vyúčtování</a>
                  </div>
                  <p>Těšíme se na Vaši návštěvu a přejeme spoustu šťastných kilometrů.</p>
                  <hr style="border: 0; border-top: 1px solid #eee; margin: 20px 0;">
                  <p style="font-size: 12px; color: #777;">Tento e-mail byl vygenerován automaticky systémem <b>Torkis.cz</b> pro servis <b>$odesilatelJmeno</b>.</p>
                </div>
              ''',
            },
          });
        }
      }

      await FirebaseFirestore.instance
          .collection('zakazky')
          .doc(documentId)
          .update({
            'stav_zakazky': 'Dokončeno',
            'zpusob_ukonceni': zpusob,
            'forma_uhrady': platba,
            'cas_ukonceni': FieldValue.serverTimestamp(),
            if (pdfUrl.isNotEmpty) 'vystupni_protokol_url': pdfUrl,
          });

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zakázka úspěšně ukončena. E-mail odeslán.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při ukončování: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
    Map<String, dynamic> imageUrlsByCategory, {
    String titulekDokladu = 'Protokol o příjmu a vyúčtování',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    String hlavickaNazev = 'VISTO';
    String hlavickaIco = '';
    if (user != null) {
      final nastaveniDoc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (nastaveniDoc.exists) {
        hlavickaNazev = nastaveniDoc.data()?['nazev_servisu'] ?? 'Servis';
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

    double celkovaSumaZakazky = 0.0;
    final pdf = pw.Document();
    final fontRegular = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

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
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start, // OPRAVENO pw.
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
                    titulekDokladu,
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 18,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 15),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start, // OPRAVENO pw.
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
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start, // OPRAVENO pw.
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
                ],
              ),
            ),

            pw.SizedBox(height: 20),
            pw.Text(
              'Rozpis provedených prací a materiálu',
              style: pw.TextStyle(font: fontBold, fontSize: 14),
            ),
            pw.SizedBox(height: 10),

            // Tabulka vyúčtování
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'Položka',
                        style: pw.TextStyle(font: fontBold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'Množství',
                        style: pw.TextStyle(font: fontBold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'Cena/j',
                        style: pw.TextStyle(font: fontBold, fontSize: 10),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                        'Celkem',
                        style: pw.TextStyle(font: fontBold, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                ...provedenePrace.expand((prace) {
                  List<pw.TableRow> rows = [];
                  double cenaPrace = (prace['cena_s_dph'] ?? 0.0).toDouble();
                  celkovaSumaZakazky += cenaPrace;

                  rows.add(
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            prace['nazev'],
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            '${prace['delka_prace'] ?? 1} h',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            '-',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            '${cenaPrace.toStringAsFixed(2)} Kč',
                            style: pw.TextStyle(
                              font: fontRegular,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );

                  final dily = prace['pouzite_dily'] as List<dynamic>? ?? [];
                  for (var dil in dily) {
                    double pocet = (dil['pocet'] ?? 1.0).toDouble();
                    double cenaKs = (dil['cena_s_dph'] ?? 0.0).toDouble();
                    double dilCelkem = pocet * cenaKs;
                    celkovaSumaZakazky += dilCelkem;

                    rows.add(
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '  - ${dil['nazev']}',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '$pocet ks',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${cenaKs.toStringAsFixed(2)} Kč',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                              ),
                            ),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              '${dilCelkem.toStringAsFixed(2)} Kč',
                              style: pw.TextStyle(
                                font: fontRegular,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return rows;
                }),
              ],
            ),

            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        'CELKEM K ÚHRADĚ: ',
                        style: pw.TextStyle(font: fontBold, fontSize: 14),
                      ),
                      pw.Text(
                        '${celkovaSumaZakazky.toStringAsFixed(2)} Kč',
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
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start, // OPRAVENO pw.
                    children: [
                      pw.Text(
                        'Podpis zákazníka při převzetí:',
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
                    'Vygenerováno systémem Torkis.cz',
                    style: pw.TextStyle(
                      font: fontRegular,
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
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
          final pozadavky = data['pozadavky_zakaznika'] as List<dynamic>? ?? [];
          final aktualniStav = data['stav_zakazky'] ?? 'Přijato';
          final stav = data['stav_vozidla'] as Map<String, dynamic>? ?? {};
          final zakaznik = data['zakaznik'] as Map<String, dynamic>? ?? {};
          final znackaNazev = (data['znacka']?.toString() ?? '').trim();

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
                        Icons.send_and_archive,
                        color: Colors.blue,
                      ),
                      onPressed: () => _odeslatNaceneni(
                        context,
                        data,
                        stav,
                        zakaznik,
                        imageUrlsByCategoryRaw,
                      ),
                      tooltip: 'Odeslat cenový odhad',
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

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // --- HLAVIČKA S LOGEM A SPZ ---
                    Column(
                      children: [
                        if (znackaNazev.isNotEmpty)
                          FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('znacka')
                                .get(),
                            builder: (context, snap) {
                              if (snap.hasData) {
                                String nalezeneLogo = '';
                                for (var doc in snap.data!.docs) {
                                  final d = doc.data() as Map<String, dynamic>;
                                  final dbNazev =
                                      (d['nazev']?.toString() ?? doc.id)
                                          .trim()
                                          .toLowerCase();
                                  if (dbNazev == znackaNazev.toLowerCase()) {
                                    nalezeneLogo =
                                        d['logo']?.toString() ??
                                        d['logo_url']?.toString() ??
                                        '';
                                    break;
                                  }
                                }
                                if (nalezeneLogo.isNotEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 15),
                                    child: Image.network(
                                      nalezeneLogo,
                                      height: 80,
                                      fit: BoxFit.contain,
                                    ),
                                  );
                                }
                              }
                              return const SizedBox(height: 10);
                            },
                          ),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.black87,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            spz.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25),

                    Card(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              child: Text(
                                'Informace o zakázce',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                            const Divider(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ZakaznikDetailScreen(
                                                  zakaznikData: zakaznik,
                                                ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.person,
                                                  size: 16,
                                                  color: isDark
                                                      ? Colors.grey[400]
                                                      : Colors.grey[700],
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'Zákazník',
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[700],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              zakaznik['jmeno']
                                                          ?.toString()
                                                          .isNotEmpty ==
                                                      true
                                                  ? zakaznik['jmeno']
                                                  : 'Neuvedeno',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            if (zakaznik['telefon']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true)
                                              Text(zakaznik['telefon']),
                                            if (zakaznik['email']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true)
                                              Text(zakaznik['email']),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 80,
                                  color: Colors.grey.withOpacity(0.3),
                                  margin: const EdgeInsets.only(top: 10),
                                ),
                                Expanded(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        final user =
                                            FirebaseAuth.instance.currentUser;
                                        if (user != null &&
                                            data['spz'] != null) {
                                          final vozidloDocId =
                                              '${user.uid}_${data['spz']}';
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  VozidloDetailScreen(
                                                    vozidloDocId: vozidloDocId,
                                                  ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.directions_car,
                                                  size: 16,
                                                  color: isDark
                                                      ? Colors.grey[400]
                                                      : Colors.grey[700],
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'Vozidlo',
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[700],
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.grey[600]!
                                                      : Colors.black87,
                                                  width: 1.5,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                data['spz']
                                                        ?.toString()
                                                        .toUpperCase() ??
                                                    '---',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${data['znacka'] ?? ''} ${data['model'] ?? ''}'
                                                      .trim()
                                                      .isEmpty
                                                  ? 'Neznámé vozidlo'
                                                  : '${data['znacka']} ${data['model']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              'VIN: ${data['vin']?.toString().isNotEmpty == true ? data['vin'] : '-'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

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
                                        fontWeight: FontWeight.bold,
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
                                              height: 80,
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
                          onPressed: () => _ukoncitZakazkuDialog(
                            context,
                            data,
                            stav,
                            zakaznik,
                            imageUrlsByCategoryRaw,
                          ),
                          icon: const Icon(Icons.flag),
                          label: const Text(
                            'UKONČIT A VYDAT',
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

    if (widget.initialTitle != null) {
      _nazevController.text = widget.initialTitle!;
    }

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
        'cas': widget.existingWork?['cas'] ?? Timestamp.now(),
        'fotografie_urls': finalFotky,
      };

      if (widget.editIndex != null) {
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
        Map<String, dynamic> updates = {
          'provedene_prace': FieldValue.arrayUnion([novyUkon]),
        };

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
