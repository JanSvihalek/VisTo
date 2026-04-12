import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import '../core/pdf_generator.dart';

class FakturacePage extends StatefulWidget {
  const FakturacePage({super.key});

  @override
  State<FakturacePage> createState() => _FakturacePageState();
}

class _FakturacePageState extends State<FakturacePage> {
  String _searchQuery = '';

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "-";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy').format(dt);
  }

  Future<void> _oznacitJakoUhrazene(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('faktury').doc(docId).update({
        'stav_platby': 'Uhrazeno',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faktura byla označena jako uhrazená.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při aktualizaci: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _zobrazitPdfFaktury(
    BuildContext context,
    Map<String, dynamic> fakturaData,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Nejste přihlášeni');

      // Načtení původní zakázky pro vygenerování PDF
      final zakazkaDoc = await FirebaseFirestore.instance
          .collection('zakazky')
          .doc('${user.uid}_${fakturaData['cislo_zakazky']}')
          .get();

      if (!zakazkaDoc.exists)
        throw Exception('Původní data zakázky nebyla nalezena.');
      final zakazkaData = zakazkaDoc.data()!;

      // Načtení detailů servisu
      String sNazev = 'Servis';
      String sIco = '';
      final docNast = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (docNast.exists) {
        sNazev = docNast.data()?['nazev_servisu'] ?? 'Servis';
        sIco = docNast.data()?['ico_servisu'] ?? '';
      }

      // Vygenerování PDF
      final pdfBytes = await GlobalPdfGenerator.generateDocument(
        data: zakazkaData,
        servisNazev: sNazev,
        servisIco: sIco,
        typ: PdfTyp.faktura,
      );

      if (context.mounted) {
        Navigator.pop(context); // Zavření načítacího kolečka
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text('Faktura ${fakturaData['cislo_faktury']}'),
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
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Zavření načítacího kolečka
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nepodařilo se načíst PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                'Přehled vystavených faktur a sledování plateb.',
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
                    hintText: 'Hledat číslo faktury, SPZ nebo jméno...',
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
            // Načítáme rovnou z nové kolekce faktury
            stream: FirebaseFirestore.instance
                .collection('faktury')
                .where('servis_id', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                final cislo =
                    data['cislo_faktury']?.toString().toLowerCase() ?? '';
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final zakaznik =
                    data['zakaznik_jmeno']?.toString().toLowerCase() ?? '';

                return cislo.contains(_searchQuery) ||
                    spz.contains(_searchQuery) ||
                    zakaznik.contains(_searchQuery);
              }).toList();

              // Řazení od nejnovějších
              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final timeA = dataA['datum_vystaveni'] as Timestamp?;
                final timeB = dataB['datum_vystaveni'] as Timestamp?;

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
                            ? 'Zatím nebyly vystaveny žádné faktury.'
                            : 'Nic nenalezeno.',
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
                  final docId = docs[index].id;

                  final stavPlatby = data['stav_platby'] ?? 'Neznámý';
                  final jeUhrazeno = stavPlatby == 'Uhrazeno';
                  final barvaStavu = jeUhrazeno
                      ? Colors.green
                      : Colors.redAccent;

                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 15),
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${data['cislo_faktury']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              Text(
                                '${(data['celkova_castka'] ?? 0.0).toStringAsFixed(2)} Kč',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.blue[900],
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Zákazník: ${data['zakaznik_jmeno']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Vozidlo (SPZ): ${data['spz']}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'K zakázce: ${data['cislo_zakazky']}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Vystaveno: ${_formatDate(data['datum_vystaveni'])}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Splatnost: ${_formatDate(data['datum_splatnosti'])}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: jeUhrazeno
                                            ? Colors.grey
                                            : Colors.red,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: barvaStavu.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: barvaStavu,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  stavPlatby,
                                  style: TextStyle(
                                    color: barvaStavu,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (!jeUhrazeno)
                                TextButton.icon(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'ZAPLACENO',
                                    style: TextStyle(color: Colors.green),
                                  ),
                                  onPressed: () => _oznacitJakoUhrazene(docId),
                                ),
                              IconButton(
                                icon: const Icon(
                                  Icons.picture_as_pdf,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                                tooltip: 'Zobrazit fakturu',
                                onPressed: () =>
                                    _zobrazitPdfFaktury(context, data),
                              ),
                            ],
                          ),
                        ],
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
