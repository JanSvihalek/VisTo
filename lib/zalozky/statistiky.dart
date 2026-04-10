import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({super.key});

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
                'Statistiky',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Celkový přehled výkonu vašeho servisu.',
                style: TextStyle(color: Colors.grey),
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
                return Center(child: Text("Chyba: ${snapshot.error}"));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              int aktivniZakazky = 0;
              int dokonceneZakazky = 0;
              double celkoveTrzbyBezDph = 0;
              double celkoveTrzbySDph = 0;
              double celkemHodin = 0;

              for (var doc in snapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;

                if (data['stav_zakazky'] == 'Dokončeno') {
                  dokonceneZakazky++;
                } else {
                  aktivniZakazky++;
                }

                final prace = data['provedene_prace'] as List<dynamic>? ?? [];
                for (var p in prace) {
                  celkoveTrzbyBezDph += (p['cena_bez_dph'] ?? 0.0).toDouble();
                  celkoveTrzbySDph += (p['cena_s_dph'] ?? 0.0).toDouble();
                  final delkaStr =
                      p['delka_prace']?.toString().replaceAll(',', '.') ?? '0';
                  celkemHodin += double.tryParse(delkaStr) ?? 0.0;
                  final dily = p['pouzite_dily'] as List<dynamic>? ?? [];
                  for (var dil in dily) {
                    double pocet = (dil['pocet'] ?? 1.0).toDouble();
                    double cenaSDph = (dil['cena_s_dph'] ?? 0.0).toDouble();
                    double cenaBezDph = (dil['cena_bez_dph'] ?? 0.0).toDouble();
                    celkoveTrzbySDph += (cenaSDph * pocet);
                    celkoveTrzbyBezDph += (cenaBezDph * pocet);
                  }
                }
              }

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildStatCard(
                    'Celkové tržby (s DPH)',
                    '${celkoveTrzbySDph.toStringAsFixed(2)} Kč',
                    Icons.account_balance_wallet,
                    Colors.green,
                    isDark,
                    subtitle:
                        'Bez DPH: ${celkoveTrzbyBezDph.toStringAsFixed(2)} Kč',
                  ),
                  const SizedBox(height: 15),
                  _buildStatCard(
                    'Odpracované hodiny',
                    '${celkemHodin.toStringAsFixed(1)} h',
                    Icons.timer,
                    Colors.blue,
                    isDark,
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Aktivní zakázky',
                          '$aktivniZakazky',
                          Icons.build_circle,
                          Colors.orange,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: _buildStatCard(
                          'Dokončené',
                          '$dokonceneZakazky',
                          Icons.check_circle,
                          Colors.purple,
                          isDark,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark, {
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
