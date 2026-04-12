import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import 'zakaznici.dart';

class VozidlaPage extends StatefulWidget {
  const VozidlaPage({super.key});

  @override
  State<VozidlaPage> createState() => _VozidlaPageState();
}

class _VozidlaPageState extends State<VozidlaPage> {
  String _searchQuery = '';
  Map<String, String> _logaZnacek = {};

  @override
  void initState() {
    super.initState();
    _nactiLogaZnacek();
  }

  Future<void> _nactiLogaZnacek() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('znacka').get();
      final map = <String, String>{};
      for (var doc in snap.docs) {
        final data = doc.data();
        final nazev = (data['nazev']?.toString() ?? doc.id)
            .trim()
            .toLowerCase();
        final logoUrl =
            data['logo']?.toString() ?? data['logo_url']?.toString() ?? '';
        if (nazev.isNotEmpty && logoUrl.isNotEmpty) {
          map[nazev] = logoUrl;
        }
      }
      if (mounted) {
        setState(() {
          _logaZnacek = map;
        });
      }
    } catch (e) {
      debugPrint('Chyba při načítání log značek: $e');
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
          padding: const EdgeInsets.fromLTRB(30, 20, 30, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Databáze vozidel',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Přehled všech servisovaných aut.',
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
                    hintText: 'Hledat SPZ, Značku nebo VIN...',
                    prefixIcon: const Icon(Icons.search, color: Colors.teal),
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
                        color: Colors.teal,
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
                .collection('vozidla')
                .where('servis_id', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(child: Text("Chyba databáze: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final spz = data['spz']?.toString().toLowerCase() ?? '';
                final znacka = data['znacka']?.toString().toLowerCase() ?? '';
                final vin = data['vin']?.toString().toLowerCase() ?? '';
                return spz.contains(_searchQuery) ||
                    znacka.contains(_searchQuery) ||
                    vin.contains(_searchQuery);
              }).toList();

              docs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final spzA = dataA['spz']?.toString() ?? '';
                final spzB = dataB['spz']?.toString() ?? '';
                return spzA.compareTo(spzB);
              });

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'Zatím nemáte v databázi žádná vozidla.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;

                  final znackaNazev = (data['znacka']?.toString() ?? '')
                      .trim()
                      .toLowerCase();
                  final logoUrl = _logaZnacek[znackaNazev];

                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      leading: Container(
                        width: 50,
                        height: 50,
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.teal.withOpacity(0.3),
                          ),
                        ),
                        child: logoUrl != null && logoUrl.isNotEmpty
                            ? Image.network(
                                logoUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.directions_car,
                                      color: Colors.teal,
                                    ),
                              )
                            : const Icon(
                                Icons.directions_car,
                                color: Colors.teal,
                              ),
                      ),
                      title: Text(
                        '${data['spz']}',
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
                            Text(
                              '${data['znacka'] ?? ''} ${data['model'] ?? ''} ${data['motorizace'] != null && data['motorizace'].toString().isNotEmpty ? '(${data['motorizace']})' : ''}',
                            ),
                            if (data['vin'] != null &&
                                data['vin'].toString().isNotEmpty)
                              Text(
                                'VIN: ${data['vin']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                VozidloDetailScreen(vozidloDocId: docId),
                          ),
                        );
                      },
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

class VozidloDetailScreen extends StatelessWidget {
  final String vozidloDocId;

  const VozidloDetailScreen({super.key, required this.vozidloDocId});

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return "Neznámé datum";
    DateTime dt = (timestamp as Timestamp).toDate();
    return DateFormat('dd.MM.yyyy').format(dt);
  }

  void _otevritEditaci(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    final znackaCtrl = TextEditingController(
      text: data['znacka']?.toString() ?? '',
    );
    final modelCtrl = TextEditingController(
      text: data['model']?.toString() ?? '',
    );
    final vinCtrl = TextEditingController(text: data['vin']?.toString() ?? '');
    final rokCtrl = TextEditingController(
      text: data['rok_vyroby']?.toString() ?? '',
    );
    final motorCtrl = TextEditingController(
      text: data['motorizace']?.toString() ?? '',
    );

    String vybranaZnacka = znackaCtrl.text;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance.collection('znacka').get(),
              builder: (context, snapshot) {
                Map<String, List<String>> databazeZnacek = {};
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    final docData = doc.data() as Map<String, dynamic>;
                    final nazev = docData['nazev']?.toString() ?? doc.id;
                    final modely = List<String>.from(docData['model'] ?? []);
                    databazeZnacek[nazev] = modely;
                  }
                }

                List<String> dostupneZnacky = databazeZnacek.keys.toList();
                dostupneZnacky.sort();

                List<String> dostupneModely = [];
                if (vybranaZnacka.isNotEmpty &&
                    databazeZnacek.containsKey(vybranaZnacka)) {
                  dostupneModely = databazeZnacek[vybranaZnacka]!;
                  dostupneModely.sort();
                }

                return SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        alignment: Alignment.center,
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
                      Text(
                        'Úprava vozidla: ${data['spz']}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          return DropdownMenu<String>(
                            width: constraints.maxWidth,
                            controller: znackaCtrl,
                            enableFilter: true,
                            enableSearch: true,
                            label: const Text('Značka'),
                            inputDecorationTheme: const InputDecorationTheme(
                              border: OutlineInputBorder(),
                            ),
                            dropdownMenuEntries: dostupneZnacky
                                .map(
                                  (z) => DropdownMenuEntry(value: z, label: z),
                                )
                                .toList(),
                            onSelected: (val) {
                              setState(() {
                                vybranaZnacka = val ?? znackaCtrl.text;
                                modelCtrl.clear();
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 15),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          return DropdownMenu<String>(
                            width: constraints.maxWidth,
                            controller: modelCtrl,
                            enableFilter: true,
                            enableSearch: true,
                            label: const Text('Model'),
                            inputDecorationTheme: const InputDecorationTheme(
                              border: OutlineInputBorder(),
                            ),
                            dropdownMenuEntries: dostupneModely
                                .map(
                                  (m) => DropdownMenuEntry(value: m, label: m),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 15),

                      TextField(
                        controller: vinCtrl,
                        decoration: const InputDecoration(
                          labelText: 'VIN',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: rokCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Rok výroby',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: TextField(
                              controller: motorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Motorizace',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                          ),
                          onPressed: () async {
                            await FirebaseFirestore.instance
                                .collection('vozidla')
                                .doc(docId)
                                .update({
                                  'znacka': znackaCtrl.text.trim(),
                                  'model': modelCtrl.text.trim(),
                                  'vin': vinCtrl.text.trim(),
                                  'rok_vyroby': rokCtrl.text.trim(),
                                  'motorizace': motorCtrl.text.trim(),
                                });
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text(
                            'ULOŽIT ZMĚNY',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null)
      return const Scaffold(body: Center(child: Text('Nejste přihlášeni')));

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vozidla')
          .doc(vozidloDocId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text("Chyba: ${snapshot.error}")),
          );
        if (!snapshot.hasData)
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );

        final autoData = snapshot.data!.data() as Map<String, dynamic>?;
        if (autoData == null)
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text("Vozidlo nenalezeno.")),
          );

        final spz = autoData['spz']?.toString() ?? 'Neznámá SPZ';
        final zakaznikId = autoData['zakaznik_id']?.toString() ?? '';
        final znackaNazev = (autoData['znacka']?.toString() ?? '').trim();

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text(
              'Karta vozidla',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            elevation: 1,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.teal),
                tooltip: 'Upravit údaje',
                onPressed: () =>
                    _otevritEditaci(context, vozidloDocId, autoData),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.center, // Vycentrování celého sloupce
              children: [
                // --- NOVÁ VELKÁ HLAVIČKA S LOGEM NAD SPZ ---
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
                              final dbNazev = (d['nazev']?.toString() ?? doc.id)
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
                                child: Container(
                                  height: 80, // Větší logo
                                  constraints: const BoxConstraints(
                                    maxWidth: 150,
                                  ),
                                  child: Image.network(
                                    nalezeneLogo,
                                    fit: BoxFit.contain,
                                    errorBuilder: (c, e, s) => const SizedBox(),
                                  ),
                                ),
                              );
                            }
                          }
                          return const SizedBox(height: 20);
                        },
                      ),

                    // SPZ Rámeček
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 25,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.grey[600]! : Colors.black87,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 24,
                            color: Colors.blue[700],
                            margin: const EdgeInsets.only(right: 12),
                          ),
                          Text(
                            spz.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 32,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // --- DATA O VOZIDLE ---
                Card(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(
                      color: Colors.teal.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoColumn(
                                'Značka a Model',
                                '${autoData['znacka'] ?? ''} ${autoData['model'] ?? ''}'
                                    .trim(),
                              ),
                            ),
                            Expanded(
                              child: _buildInfoColumn(
                                'Motorizace',
                                autoData['motorizace'],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoColumn('VIN', autoData['vin']),
                            ),
                            Expanded(
                              child: _buildInfoColumn(
                                'Rok výroby',
                                autoData['rok_vyroby'],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 25),

                // --- MAJITEL ---
                if (zakaznikId.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'Majitel vozidla',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('zakaznici')
                        .where('servis_id', isEqualTo: user.uid)
                        .where('id_zakaznika', isEqualTo: zakaznikId)
                        .limit(1)
                        .get(),
                    builder: (context, zakaznikSnap) {
                      if (zakaznikSnap.connectionState ==
                          ConnectionState.waiting)
                        return const Center(child: CircularProgressIndicator());
                      if (!zakaznikSnap.hasData ||
                          zakaznikSnap.data!.docs.isEmpty)
                        return const Text(
                          'Zákazník nenalezen.',
                          style: TextStyle(color: Colors.grey),
                        );

                      final zakaznikData =
                          zakaznikSnap.data!.docs.first.data()
                              as Map<String, dynamic>;

                      return Card(
                        color: isDark
                            ? const Color(0xFF1E1E1E)
                            : Colors.blueGrey[50],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: Colors.blueGrey.withOpacity(0.3),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ZakaznikDetailScreen(
                                  zakaznikData: zakaznikData,
                                ),
                              ),
                            );
                          },
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(15),
                            leading: CircleAvatar(
                              backgroundColor: Colors.blueGrey.withOpacity(0.2),
                              foregroundColor: Colors.blueGrey,
                              child: const Icon(Icons.person),
                            ),
                            title: Text(
                              zakaznikData['jmeno'] ?? 'Neznámý zákazník',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              '${zakaznikData['telefon'] ?? ''}\n${zakaznikData['email'] ?? ''}'
                                  .trim(),
                            ),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 25),
                ],

                // --- HISTORIE SERVISŮ ---
                Align(
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    'Historie servisů tohoto vozidla',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('zakazky')
                      .where('servis_id', isEqualTo: user.uid)
                      .where('spz', isEqualTo: spz)
                      .snapshots(),
                  builder: (context, historySnap) {
                    if (historySnap.connectionState == ConnectionState.waiting)
                      return const Center(child: CircularProgressIndicator());
                    if (!historySnap.hasData ||
                        historySnap.data!.docs.isEmpty) {
                      return const Text(
                        'Vozidlo zatím nemá žádné servisní záznamy.',
                        style: TextStyle(color: Colors.grey),
                      );
                    }

                    final docs = historySnap.data!.docs.toList();
                    docs.sort((a, b) {
                      final dA = a.data() as Map<String, dynamic>;
                      final dB = b.data() as Map<String, dynamic>;
                      final tA = dA['cas_prijeti'] as Timestamp?;
                      final tB = dB['cas_prijeti'] as Timestamp?;
                      if (tA == null && tB == null) return 0;
                      if (tA == null) return 1;
                      if (tB == null) return -1;
                      return tB.compareTo(tA);
                    });

                    return Column(
                      children: docs.map((doc) {
                        final zakazka = doc.data() as Map<String, dynamic>;
                        final stav = zakazka['stav_zakazky'] ?? 'Přijato';

                        double celkovaCena = 0.0;
                        final prace =
                            zakazka['provedene_prace'] as List<dynamic>? ?? [];
                        for (var p in prace) {
                          celkovaCena += (p['cena_s_dph'] ?? 0.0).toDouble();
                          final dily =
                              p['pouzite_dily'] as List<dynamic>? ?? [];
                          for (var dil in dily) {
                            double pocet = (dil['pocet'] ?? 1.0).toDouble();
                            double cenaSDph = (dil['cena_s_dph'] ?? 0.0)
                                .toDouble();
                            celkovaCena += (pocet * cenaSDph);
                          }
                        }

                        Color barvaStavu;
                        switch (stav) {
                          case 'Přijato':
                            barvaStavu = Colors.blue;
                            break;
                          case 'V řešení':
                            barvaStavu = Colors.orange;
                            break;
                          case 'Čeká na díly':
                            barvaStavu = Colors.purple;
                            break;
                          case 'Dokončeno':
                            barvaStavu = Colors.green;
                            break;
                          default:
                            barvaStavu = Colors.grey;
                        }

                        return Card(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : Colors.white,
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                        color: barvaStavu.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: barvaStavu,
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        stav,
                                        style: TextStyle(
                                          color: barvaStavu,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _formatDate(zakazka['cas_prijeti']),
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${prace.length} úkonů',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    Text(
                                      '${celkovaCena.toStringAsFixed(2)} Kč',
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
      },
    );
  }

  Widget _buildInfoColumn(String label, dynamic value) {
    final valStr = value?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          valStr.isNotEmpty ? valStr : '-',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
