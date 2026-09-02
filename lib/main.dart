import 'package:flutter/material.dart';

import 'app/manos_chacabuco_app.dart';
import 'core/database/app_database.dart';
import 'data/repositories/sqlite_material_catalog_repository.dart';
import 'data/repositories/sqlite_historical_import_repository.dart';
import 'data/repositories/sqlite_material_repository.dart';
import 'data/repositories/sqlite_product_catalog_repository.dart';
import 'data/repositories/sqlite_product_repository.dart';
import 'data/repositories/sqlite_quote_repository.dart';
import 'data/repositories/sqlite_settings_repository.dart';
import 'data/storage/local_product_photo_store.dart';
import 'data/importing/xlsx_workbook_reader.dart';
import 'features/importing/application/historical_import_controller.dart';
import 'features/materials/application/materials_controller.dart';
import 'features/products/application/products_controller.dart';
import 'features/quotes/application/quotes_controller.dart';
import 'features/settings/application/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('Inicio: abriendo base local.');
    final database = await AppDatabase.openDefault();
    debugPrint('Inicio: base local lista.');
    final settingsRepository = SqliteSettingsRepository(database);
    final settings = await settingsRepository.getOrCreateDefaults();
    debugPrint('Inicio: configuración lista.');
    final settingsController = SettingsController(
      repository: settingsRepository,
      initialSettings: settings,
    );
    final materialsController = MaterialsController(
      materialRepository: SqliteMaterialRepository(database),
      catalogRepository: SqliteMaterialCatalogRepository(database),
    );
    await materialsController.load();
    debugPrint('Inicio: catálogo de materias primas listo.');
    final productsController = ProductsController(
      productRepository: SqliteProductRepository(database),
      catalogRepository: SqliteProductCatalogRepository(database),
      photoStore: await LocalProductPhotoStore.openDefault(),
      materialsController: materialsController,
      settingsController: settingsController,
    );
    await productsController.load();
    debugPrint('Inicio: catálogo de productos listo.');
    final quotesController = QuotesController(
      quoteRepository: SqliteQuoteRepository(database),
      productsController: productsController,
      settingsController: settingsController,
    );
    await quotesController.load();
    debugPrint('Inicio: presupuestos listos.');
    final importController = HistoricalImportController(
      repository: SqliteHistoricalImportRepository(database),
      workbookLoader: const XlsxWorkbookReader(),
      materialsController: materialsController,
      productsController: productsController,
      settingsController: settingsController,
    );
    await importController.load();

    runApp(
      ManosChacabucoApp(
        settingsController: settingsController,
        materialsController: materialsController,
        productsController: productsController,
        quotesController: quotesController,
        importController: importController,
      ),
    );
    debugPrint('Inicio: interfaz montada.');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('Inicio: primer cuadro dibujado.');
    });
  } catch (error, stackTrace) {
    debugPrint('No se pudo iniciar la base local: $error\n$stackTrace');
    runApp(BootstrapFailureApp(error: error));
  }
}
