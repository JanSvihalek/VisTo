import 'package:flutter/material.dart';

// --- GLOBÁLNÍ KONSTANTY ---
const Map<String, dynamic> photoCategories = {
  'karoserie': {
    'label': 'Karoserie (celkový pohled)',
    'icon': Icons.directions_car_rounded,
  },
  'disky': {'label': 'Disky a kola', 'icon': Icons.tire_repair_rounded},
  'sklo': {'label': 'Čelní sklo', 'icon': Icons.branding_watermark_rounded},
  'nadrz': {'label': 'Stav nádrže', 'icon': Icons.local_gas_station_rounded},
  'tachometr': {
    'label': 'Tachometr (ujetá vzdálenost)',
    'icon': Icons.speed_rounded,
  },
  'stk': {'label': 'Nálepka STK', 'icon': Icons.check_circle_outline_rounded},
};

// --- STAVY ZAKÁZKY ---
const List<String> stavyZakazky = [
  'Přijato',
  'V opravě',
  'Čeká na díly',
  'K vyzvednutí',
  'Dokončeno',
];

Color getStatusColor(String stav) {
  switch (stav) {
    case 'Přijato':
      return Colors.blue;
    case 'V opravě':
      return Colors.orange;
    case 'Čeká na díly':
      return Colors.redAccent;
    case 'K vyzvednutí':
      return Colors.purple;
    case 'Dokončeno':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// --- TŘÍDA PRO DÍLY ---
class DilInput {
  final cislo = TextEditingController();
  final nazev = TextEditingController();
  final pocet = TextEditingController(text: '1');
  final cenaBezDph = TextEditingController();
  final cenaSDph = TextEditingController();

  void dispose() {
    cislo.dispose();
    nazev.dispose();
    pocet.dispose();
    cenaBezDph.dispose();
    cenaSDph.dispose();
  }
}

// --- GLOBÁLNÍ STAV PRO TMÁVÝ/SVĚTLÝ REŽIM ---
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
