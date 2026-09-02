import 'package:manos_chacabuco/app/manos_chacabuco_app.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_quote_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/features/materials/application/materials_controller.dart';
import 'package:manos_chacabuco/features/products/application/products_controller.dart';
import 'package:manos_chacabuco/features/quotes/application/quotes_controller.dart';
import 'package:manos_chacabuco/features/settings/application/settings_controller.dart';
import 'package:manos_chacabuco/domain/repositories/product_photo_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class TestAppHarness {
  const TestAppHarness({
    required this.database,
    required this.app,
    required this.materialsController,
    required this.settingsController,
    required this.productsController,
    required this.quotesController,
  });

  final AppDatabase database;
  final ManosChacabucoApp app;
  final MaterialsController materialsController;
  final SettingsController settingsController;
  final ProductsController productsController;
  final QuotesController quotesController;

  Future<void> close() => database.close();
}

Future<TestAppHarness> createTestAppHarness() async {
  sqfliteFfiInit();
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );
  final settingsRepository = SqliteSettingsRepository(database);
  final settingsController = SettingsController(
    repository: settingsRepository,
    initialSettings: await settingsRepository.getOrCreateDefaults(),
  );
  final materialsController = MaterialsController(
    materialRepository: SqliteMaterialRepository(database),
    catalogRepository: SqliteMaterialCatalogRepository(database),
  );
  await materialsController.load();
  final productsController = ProductsController(
    productRepository: SqliteProductRepository(database),
    catalogRepository: SqliteProductCatalogRepository(database),
    photoStore: _TestPhotoStore(),
    materialsController: materialsController,
    settingsController: settingsController,
  );
  await productsController.load();
  final quotesController = QuotesController(
    quoteRepository: SqliteQuoteRepository(database),
    productsController: productsController,
    settingsController: settingsController,
  );
  await quotesController.load();
  return TestAppHarness(
    database: database,
    materialsController: materialsController,
    settingsController: settingsController,
    productsController: productsController,
    quotesController: quotesController,
    app: ManosChacabucoApp(
      settingsController: settingsController,
      materialsController: materialsController,
      productsController: productsController,
      quotesController: quotesController,
    ),
  );
}

final class _TestPhotoStore implements ProductPhotoStore {
  @override
  String absolutePath(String reference) => reference;

  @override
  Future<void> delete(String reference) async {}

  @override
  Future<String?> duplicate(String? reference) async => reference;

  @override
  Future<String> importFile(String sourcePath) async => sourcePath;
}
