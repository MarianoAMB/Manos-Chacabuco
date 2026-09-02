import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/design_system/app_theme.dart';
import '../core/design_system/components/app_empty_state.dart';
import '../features/materials/application/materials_controller.dart';
import '../features/importing/application/historical_import_controller.dart';
import '../features/products/application/products_controller.dart';
import '../features/quotes/application/quotes_controller.dart';
import '../features/settings/application/settings_controller.dart';
import 'shell/adaptive_app_shell.dart';

final class ManosChacabucoApp extends StatelessWidget {
  const ManosChacabucoApp({
    required this.settingsController,
    required this.materialsController,
    required this.productsController,
    required this.quotesController,
    this.importController,
    super.key,
  });

  final SettingsController settingsController;
  final MaterialsController materialsController;
  final ProductsController productsController;
  final QuotesController quotesController;
  final HistoricalImportController? importController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: settingsController,
    builder: (context, _) => MaterialApp(
      title: settingsController.settings.businessName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AdaptiveAppShell(
        settingsController: settingsController,
        materialsController: materialsController,
        productsController: productsController,
        quotesController: quotesController,
        importController: importController,
      ),
    ),
  );
}

final class BootstrapFailureApp extends StatelessWidget {
  const BootstrapFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Manos Chacabuco',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: AppEmptyState(
        icon: Icons.storage_rounded,
        title: 'No pudimos abrir tus datos locales',
        message:
            'Cerrá y volvé a abrir la aplicación. Tus datos no fueron borrados. '
            'Si el problema continúa, compartí este detalle: $error',
      ),
    ),
  );
}
