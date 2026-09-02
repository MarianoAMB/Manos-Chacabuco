import 'package:flutter/material.dart';

enum AppDestination {
  home('Inicio', Icons.home_rounded),
  products('Productos', Icons.inventory_2_rounded),
  materials('Materias primas', Icons.spa_rounded),
  quotes('Presupuestos', Icons.request_quote_rounded),
  calculator('Calculadora', Icons.calculate_rounded),
  priceLists('Listas de precios', Icons.list_alt_rounded),
  settings('Configuración', Icons.tune_rounded);

  const AppDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

const mobilePrimaryDestinations = [
  AppDestination.home,
  AppDestination.products,
  AppDestination.materials,
  AppDestination.quotes,
];
