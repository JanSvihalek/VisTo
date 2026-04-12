import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../core/pdf_generator.dart'; // IMPORT NAŠEHO GENERÁTORU

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
                        onPressed: () async {
                          // Načtení nastavení servisu
                          final docNast = await FirebaseFirestore.instance
                              .collection('nastaveni_servisu')
                              .doc(user.uid)
                              .get();
                          final sNazev =
                              docNast.data()?['nazev_servisu'] ?? 'Servis';
                          final sIco = docNast.data()?['ico_servisu'] ?? '';

                          // Vygenerování PDF Faktury
                          final pdfBytes =
                              await GlobalPdfGenerator.generateDocument(
                                data: data,
                                servisNazev: sNazev,
                                servisIco: sIco,
                                typ: PdfTyp.faktura,
                              );

                          // Zobrazení v náhledu
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Náhled faktury'),
                                  ),
                                  body: PdfPreview(
                                    build: (format) => pdfBytes,
                                    allowSharing: true,
                                    allowPrinting: true,
                                    canChangeOrientation: false,
                                    canChangePageFormat: false,
                                  ),
                                ),
                              ),
                            );
                          }
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
}
