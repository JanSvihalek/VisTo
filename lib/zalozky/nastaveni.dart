import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _nazevController = TextEditingController();
  final _icoController = TextEditingController();
  final _sazbaController = TextEditingController();
  final _prefixController = TextEditingController();
  final _dicController = TextEditingController();
  final _bankaController = TextEditingController();
  final _registraceController = TextEditingController();

  bool _jePlatceDph = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;

  String? _logoUrl;
  final ImagePicker _picker = ImagePicker();

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
        _prefixController.text = data['prefix_zakazky'] ?? 'ZAK';
        _dicController.text = data['dic_servisu'] ?? '';
        _bankaController.text = data['banka_servisu'] ?? '';
        _registraceController.text = data['registrace_servisu'] ?? '';
        _jePlatceDph = data['platce_dph'] ?? false;
        _logoUrl = data['logo_url']; // Načtení případného loga
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // --- NOVÉ: Funkce pro nahrání loga ---
  Future<void> _uploadLogo() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
      );
      if (image == null) return;

      setState(() => _isUploadingLogo = true);

      final user = FirebaseAuth.instance.currentUser!;
      Reference ref = FirebaseStorage.instance.ref().child(
        'servisy/${user.uid}/nastaveni/logo.png',
      );

      await ref.putData(await image.readAsBytes());
      String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('nastaveni_servisu')
          .doc(user.uid)
          .update({'logo_url': downloadUrl});

      setState(() => _logoUrl = downloadUrl);

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Logo úspěšně nahráno.'),
            backgroundColor: Colors.green,
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chyba při nahrávání loga: $e'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
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
              'prefix_zakazky': _prefixController.text.trim().isEmpty
                  ? 'ZAK'
                  : _prefixController.text.trim().toUpperCase(),
              'dic_servisu': _dicController.text.trim(),
              'banka_servisu': _bankaController.text.trim(),
              'registrace_servisu': _registraceController.text.trim(),
              'platce_dph': _jePlatceDph,
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
          // --- NOVÉ: Správa loga ---
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isUploadingLogo ? null : _uploadLogo,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.5),
                        width: 2,
                      ),
                      image: _logoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_logoUrl!),
                              fit: BoxFit.contain,
                            )
                          : null,
                    ),
                    child: _isUploadingLogo
                        ? const Center(child: CircularProgressIndicator())
                        : (_logoUrl == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate,
                                      color: Colors.blue,
                                      size: 40,
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      'Logo',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                )
                              : null),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Kliknutím nahrajete logo na PDF',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[300]!,
              ),
            ),
            child: SwitchListTile(
              title: const Text(
                'Plátce DPH',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              value: _jePlatceDph,
              activeColor: Colors.blue,
              onChanged: (val) => setState(() => _jePlatceDph = val),
            ),
          ),
          if (_jePlatceDph) ...[
            const SizedBox(height: 20),
            _buildSettingsInput(
              'DIČ (např. CZ12345678)',
              Icons.assignment_ind,
              _dicController,
              isDark,
              caps: true,
            ),
          ],

          const SizedBox(height: 20),
          _buildSettingsInput(
            'Bankovní účet',
            Icons.account_balance,
            _bankaController,
            isDark,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'Zápis v rejstříku (ŽÚ/OR)',
            Icons.gavel,
            _registraceController,
            isDark,
          ),

          const Divider(height: 40),
          _buildSettingsInput(
            'Hodinová sazba bez DPH (Kč)',
            Icons.attach_money,
            _sazbaController,
            isDark,
            isNumber: true,
          ),
          const SizedBox(height: 20),
          _buildSettingsInput(
            'Vlastní text čísla zakázky (předpona)',
            Icons.abc,
            _prefixController,
            isDark,
            caps: true,
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
    bool caps = false,
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
            textCapitalization: caps
                ? TextCapitalization.characters
                : TextCapitalization.none,
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
