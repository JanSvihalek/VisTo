import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UkonyPage extends StatefulWidget {
  const UkonyPage({super.key});

  @override
  State<UkonyPage> createState() => _UkonyPageState();
}

class _UkonyPageState extends State<UkonyPage> {
  final _novyUkonController = TextEditingController();
  bool _isSaving = false;

  final List<String> _vychoziUkony = [
    'Výměna oleje a filtrů',
    'Kontrola brzd',
    'Servis klimatizace',
    'Příprava a provedení STK',
    'Geometrie kol',
    'Pneuservis (přezutí)',
    'Diagnostika závad'
  ];

  Future<void> _pridatUkon() async {
    final nazev = _novyUkonController.text.trim();
    if (nazev.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).set({
          'rychle_ukony': FieldValue.arrayUnion([nazev])
        }, SetOptions(merge: true));
        _novyUkonController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _smazatUkon(String nazev) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).update({
          'rychle_ukony': FieldValue.arrayRemove([nazev])
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při mazání: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    _novyUkonController.dispose();
    super.dispose();
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
              const Text('Rychlé úkony', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 5),
              const Text('Spravujte si seznam úkonů, které se vám budou nabízet pro rychlé kliknutí při příjmu vozidla.', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                        borderRadius: BorderRadius.circular(15)
                      ),
                      child: TextField(
                        controller: _novyUkonController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Napište nový úkon (např. Výměna rozvodů)...',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!, width: 1)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.deepOrange, width: 2)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15)
                        ),
                        onSubmitted: (_) => _pridatUkon(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(color: Colors.deepOrange, borderRadius: BorderRadius.circular(15)),
                    child: IconButton(
                      icon: _isSaving 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Icon(Icons.add, color: Colors.white),
                      onPressed: _isSaving ? null : _pridatUkon,
                      tooltip: 'Přidat úkon',
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 30),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Chyba: ${snapshot.error}"));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              List<String> ulozeneUkony = [];
              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>;
                if (data.containsKey('rychle_ukony')) {
                  ulozeneUkony = List<String>.from(data['rychle_ukony']);
                } else {
                  ulozeneUkony = _vychoziUkony; 
                }
              } else {
                ulozeneUkony = _vychoziUkony;
              }

              if (ulozeneUkony.isEmpty) return const Center(child: Text('Zatím nemáte definované žádné úkony.'));

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: ulozeneUkony.length,
                itemBuilder: (context, index) {
                  final ukon = ulozeneUkony[index];
                  return Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!)),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                      title: Text(ukon, style: const TextStyle(fontWeight: FontWeight.w500)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _smazatUkon(ukon),
                        tooltip: 'Smazat úkon ze seznamu',
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