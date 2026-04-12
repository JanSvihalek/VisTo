import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'prubeh.dart';
import 'prijem_vozidla.dart';
import 'historie.dart';
import 'zakaznici.dart';
import 'vozidla.dart'; 
import 'ukony.dart'; // <--- NOVÝ IMPORT
import 'fakturace.dart';
import 'statistiky.dart';
import 'nastaveni.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const MainWizardPage(),
    const ServiceProgressPage(),
    const HistoryPage(),
    const MenuPage(), 
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.car_repair,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 4),
              Text(
  'Torkis',
  style: TextStyle(
// ...
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.amber : Colors.black54,
            ),
            onPressed: () =>
                themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow, 
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Příjem',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_circle_outlined),
            selectedIcon: Icon(Icons.build_circle),
            label: 'Zakázky',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historie',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Menu',
          ),
        ],
      ),
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 10, top: 10, bottom: 5),
            child: Text('Další moduly', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 10, bottom: 20),
            child: Text('Správa servisu a zákazníků.', style: TextStyle(color: Colors.grey)),
          ),
          
          GridView.count(
            crossAxisCount: 2, 
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 15,
            crossAxisSpacing: 15,
            childAspectRatio: 1.1, 
            children: [
              _buildMenuCard(context, 'Klienti', Icons.people_alt, Colors.blue, const ZakazniciPage(), isDark),
              _buildMenuCard(context, 'Vozidla', Icons.directions_car, Colors.teal, const VozidlaPage(), isDark),
              _buildMenuCard(context, 'Úkony', Icons.playlist_add_check_circle, Colors.deepOrange, const UkonyPage(), isDark), // <--- NOVÁ DLAŽDICE
              _buildMenuCard(context, 'Faktury', Icons.receipt_long, Colors.green, const FakturacePage(), isDark),
              _buildMenuCard(context, 'Statistiky', Icons.bar_chart, Colors.purple, const StatisticsPage(), isDark),
              _buildMenuCard(context, 'Nastavení', Icons.settings, Colors.blueGrey, const SettingsPage(), isDark),
              
              _buildMenuCard(context, 'Sklad dílů', Icons.inventory_2, Colors.orange, null, isDark, isLocked: true),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, IconData icon, Color color, Widget? page, bool isDark, {bool isLocked = false}) {
    return InkWell(
      onTap: isLocked ? () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tento modul připravujeme v další verzi!')));
      } : () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              elevation: 1,
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: page,
          )
        ));
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isLocked ? Colors.grey.withOpacity(0.2) : color.withOpacity(0.3), width: 2),
          boxShadow: [if (!isDark) BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: isLocked ? Colors.grey : color),
            const SizedBox(height: 15),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isLocked ? Colors.grey : (isDark ? Colors.white : Colors.black87))),
            if (isLocked) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                child: const Text('Připravujeme', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
              )
            ]
          ],
        ),
      ),
    );
  }
}