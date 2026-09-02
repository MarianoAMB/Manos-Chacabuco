import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_historical_import_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/importing/import_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/geometry_engine.dart';
import 'package:manos_chacabuco/domain/services/historical_sheet_analyzer.dart';
import 'package:manos_chacabuco/domain/services/material_estimation_engine.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/historical_import_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'crea backup, importa una vez y la reimportación conserva la edición local',
    () async {
      final fixture = await _databaseFixture('idempotent');
      final database = fixture.database;
      final repository = SqliteHistoricalImportRepository(database);
      final now = DateTime.utc(2026, 9, 2);
      await database.database.insert('quotes', {
        'id': 'quote-before-import',
        'customer_name': 'Cliente existente',
        'quote_date': now.toIso8601String(),
        'valid_until': DateTime.utc(2026, 9, 17).toIso8601String(),
        'validity_days': 15,
        'price_type': 'retail',
        'currency': 'ARS',
        'total_minor': 123456,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final firstPreview = await _analyze(database, repository);
      final backup = await repository.createBackup();
      expect(File(backup).existsSync(), isTrue);
      final firstReport = await repository.importPreview(
        firstPreview,
        backupPath: backup,
      );
      expect(firstReport.importedMaterials, firstPreview.newMaterialCount);
      expect(firstReport.importedProducts, firstPreview.newProductCount);
      expect(firstReport.requiresReview, firstPreview.reviewCount);

      final materialCount = _count(
        await database.database.rawQuery('SELECT COUNT(*) FROM materials'),
      );
      final productCount = _count(
        await database.database.rawQuery('SELECT COUNT(*) FROM products'),
      );
      final usageCount = _count(
        await database.database.rawQuery(
          'SELECT COUNT(*) FROM product_material_usages',
        ),
      );
      final productRepository = SqliteProductRepository(database);
      final imported = (await productRepository.findAll()).firstWhere(
        (product) => product.name == 'Macetero 20x20',
      );
      final importedUsages = await productRepository.findUsages(
        imported.metadata.id,
      );
      final edited = Product(
        metadata: SyncMetadata(
          id: imported.metadata.id,
          createdAt: imported.metadata.createdAt,
          updatedAt: DateTime.utc(2026, 9, 3),
        ),
        name: 'Macetero corregido por la usuaria',
        categoryId: imported.categoryId,
        priceMultiplier: imported.priceMultiplier,
        description: imported.description,
        photoPath: imported.photoPath,
        dimensions: imported.dimensions,
        geometryProfile: imported.geometryProfile,
        pricingOverrides: imported.pricingOverrides,
        notes: imported.notes,
      );
      await productRepository.saveAggregate(edited, importedUsages);

      final secondPreview = await _analyze(database, repository);
      expect(
        secondPreview.products
            .where(
              (candidate) =>
                  candidate.decision == ImportDecision.alreadyImported,
            )
            .length,
        firstPreview.products.length,
      );
      final secondBackup = await repository.createBackup();
      final secondReport = await repository.importPreview(
        secondPreview,
        backupPath: secondBackup,
      );

      expect(secondReport.importedMaterials, 0);
      expect(secondReport.importedProducts, 0);
      expect(
        _count(
          await database.database.rawQuery('SELECT COUNT(*) FROM materials'),
        ),
        materialCount,
      );
      expect(
        _count(
          await database.database.rawQuery('SELECT COUNT(*) FROM products'),
        ),
        productCount,
      );
      expect(
        _count(
          await database.database.rawQuery(
            'SELECT COUNT(*) FROM product_material_usages',
          ),
        ),
        usageCount,
      );
      expect(
        (await productRepository.findById(imported.metadata.id))?.name,
        'Macetero corregido por la usuaria',
      );
      expect(
        (await database.database.query(
          'quotes',
          where: 'id = ?',
          whereArgs: ['quote-before-import'],
        )).single['total_minor'],
        123456,
      );

      await _verifyImportedCalibration(productRepository);
    },
  );

  test('un registro manual no se borra ni se fusiona en silencio', () async {
    final fixture = await _databaseFixture('manual');
    final database = fixture.database;
    final now = DateTime.utc(2026, 9, 2);
    final materialCatalog = SqliteMaterialCatalogRepository(database);
    final gram = (await materialCatalog.findUnits()).firstWhere(
      (unit) => unit.code == 'gram',
    );
    final cordCategory = (await materialCatalog.findCategories()).firstWhere(
      (category) => category.name == 'Cordones',
    );
    final manualMaterial = Material(
      metadata: SyncMetadata(
        id: 'manual-material',
        createdAt: now,
        updatedAt: now,
      ),
      name: 'Cordón X',
      categoryId: cordCategory.metadata.id,
      purchase: PurchasePresentation(
        quantity: MeasuredQuantity(
          amount: DecimalValue.parse('999'),
          unitId: gram.id,
        ),
        price: const Money.ars(99900),
      ),
      consumptionUnitId: gram.id,
    );
    await SqliteMaterialRepository(database)
        .saveAggregate(manualMaterial, const []);
    final productCategory = (await SqliteProductCatalogRepository(
      database,
    ).findCategories()).firstWhere((category) => category.name == 'Maceteros');
    final manualProduct = Product(
      metadata: SyncMetadata(
        id: 'manual-product',
        createdAt: now,
        updatedAt: now,
      ),
      name: 'Macetero 20x20',
      categoryId: productCategory.metadata.id,
      priceMultiplier: DecimalValue.parse('9'),
    );
    await SqliteProductRepository(database)
        .saveAggregate(manualProduct, const []);
    final repository = SqliteHistoricalImportRepository(database);

    final preview = await _analyze(database, repository);
    expect(
      preview.materials
          .firstWhere((item) => item.source.originalName == 'Cordón X')
          .decision,
      ImportDecision.useExisting,
    );
    expect(
      preview.products
          .firstWhere((item) => item.source.originalName == 'Macetero 20x20')
          .decision,
      ImportDecision.review,
    );
    await repository.importPreview(preview, backupPath: 'test-backup.db');

    expect(
      (await SqliteMaterialRepository(database).findById('manual-material'))
          ?.purchase
          .quantity
          .amount,
      DecimalValue.parse('999'),
    );
    expect(
      (await SqliteProductRepository(database).findById('manual-product'))
          ?.priceMultiplier,
      DecimalValue.parse('9'),
    );
  });

  test('un error crítico revierte toda la transacción', () async {
    final fixture = await _databaseFixture('rollback');
    final database = fixture.database;
    final repository = SqliteHistoricalImportRepository(
      database,
      beforeCommitForTesting: () async => throw StateError('falla simulada'),
    );
    final preview = await _analyze(database, repository);

    await expectLater(
      repository.importPreview(preview, backupPath: 'test-backup.db'),
      throwsStateError,
    );

    for (final table in [
      'materials',
      'products',
      'product_material_usages',
      'import_records',
      'import_reports',
    ]) {
      expect(
        _count(await database.database.rawQuery('SELECT COUNT(*) FROM $table')),
        0,
        reason: '$table debe quedar vacío tras el rollback',
      );
    }
  });
}

Future<({AppDatabase database, Directory directory})> _databaseFixture(
  String name,
) async {
  final directory = await Directory.systemTemp.createTemp('import-$name-');
  addTearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });
  final database = await AppDatabase.open(
    factory: databaseFactoryFfi,
    path: paths.join(directory.path, 'manos.db'),
  );
  addTearDown(database.close);
  return (database: database, directory: directory);
}

Future<ImportPreview> _analyze(
  AppDatabase database,
  HistoricalImportRepository importRepository,
) async {
  final materialCatalog = SqliteMaterialCatalogRepository(database);
  final materials = await SqliteMaterialRepository(database)
      .findAll(includeInactive: true);
  final products = await SqliteProductRepository(database)
      .findAll(includeInactive: true);
  var nextId = 0;
  return const HistoricalSheetAnalyzer().analyze(
    workbook: historicalImportFixture(),
    spreadsheetId: 'sheet-id',
    sheetName: 'Hoja 1',
    units: await materialCatalog.findUnits(),
    materialCategories: await materialCatalog.findCategories(),
    productCategories: await SqliteProductCatalogRepository(database)
        .findCategories(),
    existingMaterials: materials,
    existingProducts: products,
    sourceLinks: await importRepository.findSourceLinks('sheet-id'),
    settings: await SqliteSettingsRepository(database).getOrCreateDefaults(),
    idFactory: () =>
        'generated-${DateTime.now().microsecondsSinceEpoch}-${nextId++}',
    analyzedAt: DateTime.utc(2026, 9, 2),
  );
}

Future<void> _verifyImportedCalibration(
  SqliteProductRepository repository,
) async {
  final geometry = GeometryEngine.standard();
  final references = <MaterialCalibrationReference>[];
  String? materialId;
  String? compatibilityKey;
  for (final product in (await repository.findAll()).where(
    (product) => product.name.startsWith('Macetero'),
  )) {
    final profile = product.geometryProfile!;
    final dimensions = product.dimensions!;
    final usage = (await repository.findUsages(product.metadata.id)).firstWhere(
      (usage) =>
          usage.role == ProductMaterialRole.primary &&
          usage.calibrationEligible,
    );
    final area = geometry.calculate(
      GeometryInput(
        profile: profile,
        valuesCm: {
          for (final binding in profile.dimensionBindings.entries)
            binding.key:
                dimensions.values[binding.value]!.amount.scaledValue /
                DecimalValue.scale,
        },
      ),
    );
    materialId ??= usage.materialId;
    compatibilityKey ??= profile.compatibilityKey;
    references.add(
      MaterialCalibrationReference(
        productId: product.metadata.id,
        productName: product.name,
        materialId: usage.materialId,
        compatibilityKey: profile.compatibilityKey,
        effectiveArea: area.totalEffectiveArea,
        consumptionBaseUnits:
            usage.consumption.amount.scaledValue / DecimalValue.scale,
        consumptionSource: usage.consumptionSource,
      ),
    );
  }

  final estimate = const MaterialEstimationEngine().estimate(
    materialId: materialId!,
    compatibilityKey: compatibilityKey!,
    targetArea: 2000,
    references: references,
  );
  expect(estimate.hasEstimate, isTrue);
  expect(estimate.references, hasLength(3));
  expect(estimate.confidence, EstimationConfidence.good);
}

int _count(List<Map<String, Object?>> rows) =>
    rows.single.values.single! as int;
