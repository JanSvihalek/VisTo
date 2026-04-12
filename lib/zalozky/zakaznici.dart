import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import 'vozidla.dart'; // --- NOVÝ IMPORT PRO PROPOJENÍ NA KARTU VOZU ---

class ZakazniciPage extends StatefulWidget {
  const ZakazniciPage({super.key});

  @override
  State<ZakazniciPage> createState() => _ZakazniciPageState();
}

class _ZakazniciPageState extends State<ZakazniciPage> {
  String _searchQuery = '';

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
                'Zákazníci',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Adresář vašich klientů a jejich vozidel.',
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
                    hintText: 'Hledat jméno, telefon nebo IČO...',
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
                .collection('zakaznici')
                .where('servis_id', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final jmeno = data['jmeno']?.toString().toLowerCase() ?? '';
                final telefon = data['telefon']?.toString().toLowerCase() ?? '';
                final ico = data['ico']?.toString().toLowerCase() ?? '';
                return jmeno.contains(_searchQuery) ||
                    telefon.contains(_searchQuery) ||
                    ico.contains(_searchQuery);
              }).toList();

              // Řazení lokálně
              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final jmenoA = dataA['jmeno']?.toString().toLowerCase() ?? '';
                final jmenoB = dataB['jmeno']?.toString().toLowerCase() ?? '';
                return jmenoA.compareTo(jmenoB);
              });

              if (docs.isEmpty)
                return const Center(
                  child: Text('Zatím nemáte žádné zákazníky.'),
                );

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;

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
                        backgroundColor: Colors.blue.withOpacity(0.1),
                        foregroundColor: Colors.blue,
                        radius: 25,
                        child: const Icon(Icons.person),
                      ),
                      title: Text(
                        '${data['jmeno']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data['telefon'] != null &&
                                data['telefon'].toString().isNotEmpty)
                              Text('📞 ${data['telefon']}'),
                            if (data['email'] != null &&
                                data['email'].toString().isNotEmpty)
                              Text('✉️ ${data['email']}'),
                            if (data['ico'] != null &&
                                data['ico'].toString().isNotEmpty)
                              Text('🏢 IČO: ${data['ico']}'),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ZakaznikDetailScreen(zakaznikData: data),
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

class ZakaznikDetailScreen extends StatelessWidget {
  final Map<String, dynamic> zakaznikData;

  const ZakaznikDetailScreen({super.key, required this.zakaznikData});

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Zpracovává se...";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zakaznikId = zakaznikData['id_zakaznika'];
    final servisId = zakaznikData['servis_id'];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Karta zákazníka',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        elevation: 1,
      ),
      body: SingleChildScrollView(
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
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blue.withOpacity(0.1),
                          foregroundColor: Colors.blue,
                          radius: 30,
                          child: const Icon(Icons.person, size: 30),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                zakaznikData['jmeno'] ?? 'Neznámý',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (zakaznikData['ico'] != null &&
                                  zakaznikData['ico'].toString().isNotEmpty)
                                Text(
                                  'IČO: ${zakaznikData['ico']}',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 30),
                    _buildInfoRow(
                      Icons.phone,
                      'Telefon',
                      zakaznikData['telefon'],
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow(Icons.email, 'E-mail', zakaznikData['email']),
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      Icons.location_on,
                      'Adresa',
                      zakaznikData['adresa'],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            const Text(
              'Vozidla zákazníka',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('vozidla')
                  .where('servis_id', isEqualTo: servisId)
                  .where('zakaznik_id', isEqualTo: zakaznikId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const CircularProgressIndicator();
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const Text(
                    'Zákazník nemá v systému uložena žádná vozidla.',
                    style: TextStyle(color: Colors.grey),
                  );

                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final vozidlo = doc.data() as Map<String, dynamic>;
                    return Card(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
                      margin: const EdgeInsets.only(bottom: 10),
                      // --- ZDE JE PŘIDÁN PROKLIK NA DETAIL VOZIDLA ---
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  VozidloDetailScreen(vozidloDocId: doc.id),
                            ),
                          );
                        },
                        child: ListTile(
                          leading: const Icon(
                            Icons.directions_car,
                            color: Colors.blue,
                          ),
                          title: Text(
                            '${vozidlo['spz']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${vozidlo['znacka'] ?? ''} ${vozidlo['model'] ?? ''} ${vozidlo['motorizace'] != null && vozidlo['motorizace'].toString().isNotEmpty ? '(${vozidlo['motorizace']})' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                vozidlo['rok_vyroby']?.toString() ?? '',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 25),

            const Text(
              'Historie servisů',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('zakazky')
                  .where('servis_id', isEqualTo: servisId)
                  .where('zakaznik.id_zakaznika', isEqualTo: zakaznikId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const CircularProgressIndicator();
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const Text(
                    'Zákazník zatím nemá žádné servisní záznamy.',
                    style: TextStyle(color: Colors.grey),
                  );

                final docs = snapshot.data!.docs.toList();
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

                return Column(
                  children: docs.map((doc) {
                    final zakazka = doc.data() as Map<String, dynamic>;
                    final stav = zakazka['stav_zakazky'] ?? 'Přijato';

                    double celkovaCenaSDph = 0.0;
                    final prace =
                        zakazka['provedene_prace'] as List<dynamic>? ?? [];
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
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(
                          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${zakazka['cislo_zakazky']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: getStatusColor(
                                      stav,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: getStatusColor(stav),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    stav,
                                    style: TextStyle(
                                      color: getStatusColor(stav),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${zakazka['spz']} • ${_formatDate(zakazka['cas_prijeti'])}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${prace.length} úkonů',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '${celkovaCenaSDph.toStringAsFixed(2)} Kč',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, dynamic value) {
    final valStr = value?.toString() ?? '';
    if (valStr.isEmpty) return const SizedBox();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                valStr,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
