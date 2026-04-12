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
import '../core/pdf_generator.dart'; // NÁŠ NOVÝ IMPORT

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
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            final docNast = await FirebaseFirestore.instance
                                .collection('nastaveni_servisu')
                                .doc(user!.uid)
                                .get();
                            final pdfBytes =
                                await GlobalPdfGenerator.generateDocument(
                                  data: data,
                                  servisNazev:
                                      docNast.data()?['nazev_servisu'] ??
                                      'Servis',
                                  servisIco:
                                      docNast.data()?['ico_servisu'] ?? '',
                                  typ: PdfTyp.faktura,
                                );

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
                          },
                          tooltip: 'Zobrazit fakturu',
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.picture_as_pdf,
                          color: Colors.redAccent,
                          size: 28,
                        ),
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          final docNast = await FirebaseFirestore.instance
                              .collection('nastaveni_servisu')
                              .doc(user!.uid)
                              .get();
                          final pdfBytes =
                              await GlobalPdfGenerator.generateDocument(
                                data: data,
                                servisNazev:
                                    docNast.data()?['nazev_servisu'] ??
                                    'Servis',
                                servisIco: docNast.data()?['ico_servisu'] ?? '',
                                typ: PdfTyp.protokol,
                              );

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Náhled protokolu'),
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
}
