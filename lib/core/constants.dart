import 'package:flutter/material.dart';

// Globální ThemeNotifier pro přepínání světlého a tmavého režimu
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

// Seznam dostupných stavů zakázky
const List<String> stavyZakazky = [
  'Přijato',
  'V řešení',
  'Čeká na díly',
  'Dokončeno'
];

// Přiřazení barev k jednotlivým stavům
Color getStatusColor(String stav) {
  switch (stav) {
    case 'Přijato':
      return Colors.blue;
    case 'V řešení':
      return Colors.orange;
    case 'Čeká na díly':
      return Colors.red;
    case 'Dokončeno':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

// Kategorie fotografií pro Příjem a Průběh
// LOGICKÉ POŘADÍ (Obchůzka zvenku -> Sednutí dovnitř)
final Map<String, Map<String, dynamic>> photoCategories = {
  'zvenku': {'label': 'Pohled zvenku (kolem vozu)', 'icon': Icons.directions_car},
  'poskozeni': {'label': 'Zjištěná poškození', 'icon': Icons.car_crash},
  'disky': {'label': 'Disky a kola', 'icon': Icons.tire_repair},
  'stk': {'label': 'Nálepka STK', 'icon': Icons.calendar_month},
  'interier': {'label': 'Interiér vozu', 'icon': Icons.airline_seat_recline_normal},
  'tachometr': {'label': 'Tachometr a palubní deska', 'icon': Icons.speed},
  'vin': {'label': 'VIN kód', 'icon': Icons.confirmation_number},
  'ostatni': {'label': 'Ostatní dokumentace', 'icon': Icons.camera_alt},
};

// Třída pro dynamické zadávání použitých dílů (používá se v prubeh.dart)
class DilInput {
  final TextEditingController cislo = TextEditingController();
  final TextEditingController nazev = TextEditingController();
  final TextEditingController pocet = TextEditingController(text: '1');
  final TextEditingController cenaBezDph = TextEditingController();
  final TextEditingController cenaSDph = TextEditingController();

  void dispose() {
    cislo.dispose();
    nazev.dispose();
    pocet.dispose();
    cenaBezDph.dispose();
    cenaSDph.dispose();
  }
}