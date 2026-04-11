import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'main_screen.dart'; // Ujisti se, že cesta k MainScreen je správná

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;
  bool _isLoadingAres = false;

  // KROK 1: Základní údaje servisu
  final _nazevController = TextEditingController();
  final _icoController = TextEditingController();
  final _registraceController = TextEditingController();

  // KROK 2: Fakturace a Ceny
  final _sazbaController = TextEditingController();
  final _bankaController = TextEditingController();
  final _dicController = TextEditingController();
  final _prefixController = TextEditingController(text: 'ZAK');
  bool _jePlatceDph = false;

  // KROK 3: Předpřipravené úkony
  final List<TextEditingController> _ukonyControllers = [];

  final List<String> _vychoziUkony = [
    'Výměna oleje a filtrů',
    'Kontrola brzd',
    'Servis klimatizace',
    'Příprava a provedení STK',
    'Geometrie kol',
    'Pneuservis (přezutí)',
    'Diagnostika závad'
  ];

  @override
  void initState() {
    super.initState();
    for (String ukon in _vychoziUkony) {
      _ukonyControllers.add(TextEditingController(text: ukon));
    }
  }

  @override
  void dispose() {
    _nazevController.dispose();
    _icoController.dispose();
    _registraceController.dispose();
    _sazbaController.dispose();
    _bankaController.dispose();
    _dicController.dispose();
    _prefixController.dispose();
    for (var c in _ukonyControllers) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _fetchAresData() async {
    final ico = _icoController.text.trim();
    if (ico.isEmpty || ico.length != 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zadejte platné 8místné IČO.'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isLoadingAres = true);
    try {
      final response = await http.get(Uri.parse('https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/$ico'));
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _nazevController.text = data['obchodniJmeno'] ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Údaje z ARES byly načteny.'), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zadané IČO nebylo v registru ARES nalezeno.'), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při komunikaci s ARES: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoadingAres = false);
    }
  }

  void _pridatPrazdnyUkon() {
    setState(() {
      _ukonyControllers.add(TextEditingController());
    });
  }

  void _odebratUkon(int index) {
    setState(() {
      _ukonyControllers[index].dispose();
      _ukonyControllers.removeAt(index);
    });
  }

  Future<void> _dokoncitNastaveni() async {
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        List<String> finalniUkony = _ukonyControllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();

        await FirebaseFirestore.instance.collection('nastaveni_servisu').doc(user.uid).set({
          'nazev_servisu': _nazevController.text.trim(),
          'ico_servisu': _icoController.text.trim(),
          'registrace_servisu': _registraceController.text.trim(),
          'hodinova_sazba': double.tryParse(_sazbaController.text.replaceAll(',', '.')) ?? 0.0,
          'platce_dph': _jePlatceDph,
          'dic_servisu': _dicController.text.trim(),
          'banka_servisu': _bankaController.text.trim(),
          'prefix_zakazky': _prefixController.text.trim().isEmpty ? 'ZAK' : _prefixController.text.trim().toUpperCase(),
          'rychle_ukony': finalniUkony,
          'prvni_spusteni_dokonceno': true,
          'vytvoreno': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chyba při ukládání: $e'), backgroundColor: Colors.red));
      setState(() => _isSaving = false);
    }
  }

  void _moveNext() {
    if (_currentPage == 0 && _nazevController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Název servisu je povinný pro pokračování.'), backgroundColor: Colors.orange));
      return;
    }
    
    if (_currentPage == 2) {
      _dokoncitNastaveni();
    } else {
      FocusScope.of(context).unfocus();
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _moveBack() {
    FocusScope.of(context).unfocus();
    _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              child: Row(
                children: [
                  Expanded(child: Container(height: 6, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 6, decoration: BoxDecoration(color: _currentPage >= 1 ? Colors.blue : Colors.grey[300], borderRadius: BorderRadius.circular(3)))),
                  const SizedBox(width: 10),
                  Expanded(child: Container(height: 6, decoration: BoxDecoration(color: _currentPage == 2 ? Colors.blue : Colors.grey[300], borderRadius: BorderRadius.circular(3)))),
                ],
              ),
            ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), 
                onPageChanged: (index) => setState(() => _currentPage = index),
                children: [
                  _buildStep1(isDark),
                  _buildStep2(isDark),
                  _buildStep3(isDark),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121212) : Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    IconButton.filledTonal(
                      onPressed: _moveBack,
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      padding: const EdgeInsets.all(15),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 15),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _moveNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_currentPage == 2 ? 'DOKONČIT NASTAVENÍ' : 'POKRAČOVAT', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildStep1(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.handshake, color: Colors.blue, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Vítejte ve VisTo!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Nejprve vyplníme základní informace o vašem servisu. Ty se pak budou automaticky propisovat do faktur a protokolů.', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 40),
          
          const Text('IČO (ARES vyhledávání)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _icoController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Např. 12345678',
              prefixIcon: const Icon(Icons.business, color: Colors.blue),
              suffixIcon: _isLoadingAres
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.search, color: Colors.blue), onPressed: _fetchAresData, tooltip: 'Načíst z ARES'),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          
          const SizedBox(height: 20),
          const Text('Název servisu / Jméno *', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _nazevController,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Zadejte název...',
              prefixIcon: const Icon(Icons.storefront, color: Colors.blue),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Zápis v rejstříku (nepovinné)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _registraceController,
            decoration: InputDecoration(
              hintText: 'Např. zapsán v ŽR u MÚ...',
              prefixIcon: const Icon(Icons.gavel, color: Colors.blueGrey),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.payments, color: Colors.green, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Fakturace a Ceny', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Nastavte si výchozí sazby a účetní údaje.', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 30),
          
          const Text('Základní hodinová sazba bez DPH (Kč)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _sazbaController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Např. 800',
              prefixIcon: const Icon(Icons.attach_money, color: Colors.green),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E1E) : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[300]!)),
            child: SwitchListTile(
              title: const Text('Jsem plátce DPH', style: TextStyle(fontWeight: FontWeight.bold)),
              value: _jePlatceDph,
              activeColor: Colors.blue,
              onChanged: (val) => setState(() => _jePlatceDph = val),
            ),
          ),
          
          if (_jePlatceDph) ...[
            const SizedBox(height: 20),
            const Text('DIČ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: _dicController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Např. CZ12345678',
                prefixIcon: const Icon(Icons.assignment_ind, color: Colors.blue),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Text('Bankovní účet', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _bankaController,
            decoration: InputDecoration(
              hintText: 'Číslo účtu / Kód banky',
              prefixIcon: const Icon(Icons.account_balance, color: Colors.blueGrey),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Prefix pro čísla zakázek', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          TextField(
            controller: _prefixController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'ZAK',
              prefixIcon: const Icon(Icons.tag, color: Colors.blue),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
          const SizedBox(height: 5),
          const Text('Zakázky se budou číslovat např. ZAK-240410-0001.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStep3(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.deepOrange.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.playlist_add_check_circle, color: Colors.deepOrange, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Nejčastější úkony', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('Připravili jsme pro vás seznam typických úkonů. Můžete je libovolně přepsat, smazat nebo si přidat další. Budou se vám nabízet pro rychlé přidání při příjmu vozu.', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 30),
          
          ...List.generate(_ukonyControllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ukonyControllers[index],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _odebratUkon(index),
                    tooltip: 'Smazat úkon',
                  )
                ],
              ),
            );
          }),
          
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _pridatPrazdnyUkon, 
            icon: const Icon(Icons.add), 
            label: const Text('Přidat další úkon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}