import 'dart:async';

import 'package:flutter/material.dart';

import 'app/manos_chacabuco_app.dart';
import 'core/database/app_database.dart';
import 'data/repositories/sqlite_material_catalog_repository.dart';
import 'data/repositories/sqlite_historical_import_repository.dart';
import 'data/repositories/sqlite_material_repository.dart';
import 'data/repositories/sqlite_product_catalog_repository.dart';
import 'data/repositories/sqlite_product_repository.dart';
import 'data/repositories/sqlite_price_list_preferences_repository.dart';
import 'data/repositories/sqlite_quote_repository.dart';
import 'data/repositories/sqlite_settings_repository.dart';
import 'data/storage/local_product_photo_store.dart';
import 'data/storage/local_business_logo_store.dart';
import 'data/exporting/local_price_list_file_service.dart';
import 'data/exporting/pdf_price_list_exporter.dart';
import 'data/exporting/png_price_list_exporter.dart';
import 'data/sharing/native_share_service.dart';
import 'data/sync/google_sync_authenticator.dart';
import 'data/sync/sqlite_sync_store.dart';
import 'data/importing/xlsx_workbook_reader.dart';
import 'features/importing/application/historical_import_controller.dart';
import 'features/materials/application/materials_controller.dart';
import 'features/products/application/products_controller.dart';
import 'features/price_lists/application/price_lists_controller.dart';
import 'features/quotes/application/quotes_controller.dart';
import 'features/settings/application/settings_controller.dart';
import 'features/sync/application/sync_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapLoadingApp());

  try {
    final database = await AppDatabase.openDefault();
    final settingsRepository = SqliteSettingsRepository(database);
    final settings = await settingsRepository.getOrCreateDefaults();
    final logoStore = await LocalBusinessLogoStore.openDefault();
    final settingsController = SettingsController(
      repository: settingsRepository,
      initialSettings: settings,
      logoStore: logoStore,
    );
    final materialsController = MaterialsController(
      materialRepository: SqliteMaterialRepository(database),
      catalogRepository: SqliteMaterialCatalogRepository(database),
    );
    await materialsController.load();
    final productsController = ProductsController(
      productRepository: SqliteProductRepository(database),
      catalogRepository: SqliteProductCatalogRepository(database),
      photoStore: await LocalProductPhotoStore.openDefault(),
      materialsController: materialsController,
      settingsController: settingsController,
    );
    await productsController.load();
    final priceListsController = PriceListsController(
      productsController: productsController,
      settingsController: settingsController,
      preferencesRepository: SqlitePriceListPreferencesRepository(database),
      pdfExporter: const PdfPriceListExporter(),
      imageExporter: const PngPriceListExporter(),
      fileService: const LocalPriceListFileService(),
      shareService: const NativeShareService(),
    );
    final quotesController = QuotesController(
      quoteRepository: SqliteQuoteRepository(database),
      productsController: productsController,
      settingsController: settingsController,
    );
    await quotesController.load();
    final importController = HistoricalImportController(
      repository: SqliteHistoricalImportRepository(database),
      workbookLoader: const XlsxWorkbookReader(),
      materialsController: materialsController,
      productsController: productsController,
      settingsController: settingsController,
    );
    await importController.load();
    final syncStore = await SqliteSyncStore.openDefault(database);
    final syncAuthenticator = await GoogleSyncAuthenticator.openDefault();
    final syncController = SyncController(
      localStore: syncStore,
      accountStore: syncStore,
      authenticator: syncAuthenticator,
      onDataApplied: () async {
        await settingsController.reload();
        await materialsController.load();
        await productsController.load();
        await quotesController.load();
        await importController.load();
      },
    );
    for (final controller in [
      settingsController,
      materialsController,
      productsController,
      quotesController,
      priceListsController,
      importController,
    ]) {
      controller.addListener(syncController.localDataChanged);
    }

    runApp(
      ManosChacabucoApp(
        settingsController: settingsController,
        materialsController: materialsController,
        productsController: productsController,
        priceListsController: priceListsController,
        quotesController: quotesController,
        importController: importController,
        syncController: syncController,
      ),
    );
    unawaited(syncController.initialize());
  } catch (error, stackTrace) {
    debugPrint('No se pudo iniciar la base local: $error\n$stackTrace');
    runApp(const BootstrapFailureApp());
  }
}
