import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VozidlaPage extends StatefulWidget {
  const VozidlaPage({super.key});

  @override
  State<VozidlaPage> createState() => _VozidlaPageState();
}

class _VozidlaPageState extends State<VozidlaPage> {
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
          padding: const EdgeInsets.fromLTRB(30, 20, 30, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Databáze vozidel',
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

              if (docs.isEmpty)
                return const Center(
                  child: Text('Zatím nemáte v databázi žádná vozidla.'),
                );

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final docId = docs[index].id;

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
                      leading: CircleAvatar(
                        backgroundColor: Colors.teal.withOpacity(0.1),
                        foregroundColor: Colors.teal,
                        radius: 25,
                        child: const Icon(Icons.directions_car),
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
                              '${data['znacka'] ?? ''} ${data['model'] ?? ''} ${data['motorizace'] != null ? '(${data['motorizace']})' : ''}',
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
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        tooltip: 'Upravit údaje',
                        onPressed: () => _otevritEditaci(context, docId, data),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
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
              TextField(
                controller: znackaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Značka',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: modelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(),
                ),
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
  }
}
