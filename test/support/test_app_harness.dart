import 'dart:typed_data';

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
import 'package:manos_chacabuco/features/price_lists/application/price_lists_controller.dart';
import 'package:manos_chacabuco/features/quotes/application/quotes_controller.dart';
import 'package:manos_chacabuco/features/settings/application/settings_controller.dart';
import 'package:manos_chacabuco/domain/repositories/product_photo_store.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';
import 'package:manos_chacabuco/domain/repositories/price_list_exporters.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_price_list_preferences_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class TestAppHarness {
  const TestAppHarness({
    required this.database,
    required this.app,
    required this.materialsController,
    required this.settingsController,
    required this.productsController,
    required this.quotesController,
    required this.priceListsController,
    required this.shareService,
  });

  final AppDatabase database;
  final ManosChacabucoApp app;
  final MaterialsController materialsController;
  final SettingsController settingsController;
  final ProductsController productsController;
  final QuotesController quotesController;
  final PriceListsController priceListsController;
  final TestShareService shareService;

  Future<void> close() => database.close();
}

Future<TestAppHarness> createTestAppHarness({
  DateTime Function()? quoteNow,
}) async {
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
  final shareService = TestShareService();
  final priceListsController = PriceListsController(
    productsController: productsController,
    settingsController: settingsController,
    preferencesRepository: SqlitePriceListPreferencesRepository(database),
    pdfExporter: const _TestPdfExporter(),
    imageExporter: const _TestImageExporter(),
    fileService: const _TestFileService(),
    shareService: shareService,
    now: () => DateTime(2026, 9, 3),
  );
  final quotesController = QuotesController(
    quoteRepository: SqliteQuoteRepository(database),
    productsController: productsController,
    settingsController: settingsController,
    now: quoteNow,
  );
  await quotesController.load();
  return TestAppHarness(
    database: database,
    materialsController: materialsController,
    settingsController: settingsController,
    productsController: productsController,
    quotesController: quotesController,
    priceListsController: priceListsController,
    shareService: shareService,
    app: ManosChacabucoApp(
      settingsController: settingsController,
      materialsController: materialsController,
      productsController: productsController,
      quotesController: quotesController,
      priceListsController: priceListsController,
    ),
  );
}

final class _TestPdfExporter implements PriceListPdfExporter {
  const _TestPdfExporter();

  @override
  Future<GeneratedPriceListFile> export(PriceListDocument document) async =>
      GeneratedPriceListFile(
        name: 'lista.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
        pageCount: 1,
      );
}

final class _TestImageExporter implements PriceListImageExporter {
  const _TestImageExporter();

  @override
  Future<List<GeneratedPriceListFile>> export(
    PriceListDocument document,
  ) async => [
    GeneratedPriceListFile(
      name: 'lista_01.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      pageCount: 1,
    ),
    GeneratedPriceListFile(
      name: 'lista_02.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([137, 80, 78, 71]),
      pageCount: 2,
    ),
  ];
}

final class _TestFileService implements PriceListFileService {
  const _TestFileService();

  @override
  Future<void> openContainingFolder(String path) async {}

  @override
  Future<void> openFile(String path) async {}

  @override
  Future<List<String>> save(
    List<GeneratedPriceListFile> files, {
    required bool askLocation,
  }) async => [for (final file in files) 'C:\\test\\${file.name}'];
}

final class TestShareService implements ShareService {
  List<GeneratedPriceListFile> lastFiles = const [];
  String? lastText;

  @override
  Future<void> share(List<GeneratedPriceListFile> files, {String? text}) async {
    lastFiles = List.unmodifiable(files);
    lastText = text;
  }
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
