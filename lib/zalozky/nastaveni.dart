import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nazevController = TextEditingController();
  final _icoController = TextEditingController();
  final _sazbaController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _nazevController.text = data['nazev_servisu'] ?? '';
        _icoController.text = data['ico_servisu'] ?? '';
        _sazbaController.text = (data['hodinova_sazba'] ?? 0.0).toString();
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('nastaveni_servisu')
            .doc(user.uid)
            .set({
              'nazev_servisu': _nazevController.text.trim(),
              'ico_servisu': _icoController.text.trim(),
              'hodinova_sazba':
                  double.tryParse(_sazbaController.text.replaceAll(',', '.')) ??
                  0.0,
            }, SetOptions(merge: true));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nastavení úspěšně uloženo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chyba při ukládání: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseAuth.instance.currentUser;

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nastavení servisu',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Přihlášen jako: ${user?.email ?? "Neznámý uživatel"}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          _buildSettingsInput(
            'Název servisu (Zobrazí se v PDF)',
            Icons.business,
            _nazevController,
            isDark,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'IČO servisu (Zobrazí se v PDF)',
            Icons.numbers,
            _icoController,
            isDark,
            isNumber: true,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'Hodinová sazba bez DPH (Kč)',
            Icons.attach_money,
            _sazbaController,
            isDark,
            isNumber: true,
          ),

          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ULOŽIT NASTAVENÍ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Odhlásit se',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsInput(
    String label,
    IconData icon,
    TextEditingController controller,
    bool isDark, {
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
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
            controller: controller,
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: Colors.blue),
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
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
