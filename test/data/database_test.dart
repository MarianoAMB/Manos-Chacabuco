import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/database/database_migrations.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/repositories/material_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as paths;

void main() {
  setUpAll(sqfliteFfiInit);

  test('crea el esquema versionado y persiste configuración', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);

    expect(
      await database.database.getVersion(),
      DatabaseMigrations.currentVersion,
    );
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(
      tableNames,
      containsAll([
        'materials',
        'products',
        'quotes',
        'sync_outbox',
        'import_records',
        'import_reports',
        'price_list_preferences',
      ]),
    );
    final variantColumns = await database.database.rawQuery(
      'PRAGMA table_info(material_variants)',
    );
    expect(variantColumns.map((row) => row['name']), contains('notes'));
    final productColumns = await database.database.rawQuery(
      'PRAGMA table_info(products)',
    );
    expect(
      productColumns.map((row) => row['name']),
      containsAll(['thread_override_scaled', 'geometry_profile_json']),
    );
    final usageColumns = await database.database.rawQuery(
      'PRAGMA table_info(product_material_usages)',
    );
    expect(
      usageColumns.map((row) => row['name']),
      containsAll(['role', 'consumption_source', 'calibration_eligible']),
    );
    final quoteColumns = await database.database.rawQuery(
      'PRAGMA table_info(quotes)',
    );
    expect(
      quoteColumns.map((row) => row['name']),
      containsAll(['validity_days', 'price_type', 'total_minor']),
    );
    final quoteItemColumns = await database.database.rawQuery(
      'PRAGMA table_info(quote_items)',
    );
    final settingsColumns = await database.database.rawQuery(
      'PRAGMA table_info(app_settings)',
    );
    expect(
      settingsColumns.map((row) => row['name']),
      contains('business_logo_path'),
    );
    expect(
      quoteItemColumns.map((row) => row['name']),
      containsAll([
        'snapshot_json',
        'price_multiplier_scaled',
        'geometry_profile_json',
      ]),
    );

    final catalog = SqliteMaterialCatalogRepository(database);
    expect(await catalog.findUnits(), hasLength(7));
    expect(
      (await catalog.findCategories()).map((category) => category.name),
      containsAll([
        'Cordones',
        'Cueros y cuerinas',
        'Cierres',
        'Mosquetones',
        'Herrajes y avíos',
        'Cintas',
        'Hilos',
        'Otros',
      ]),
    );
    expect(
      await SqliteProductCatalogRepository(database).findCategories(),
      hasLength(8),
    );

    final repository = SqliteSettingsRepository(database);
    final defaults = await repository.getOrCreateDefaults();
    await repository.save(
      defaults.copyWith(
        businessName: 'Manos Chacabuco Taller',
        defaultWastePercentage: DecimalValue.percent('2'),
        defaultThreadPercentage: DecimalValue.percent('7.5'),
        defaultRetailPercentage: DecimalValue.percent('20'),
        defaultProductMultiplier: DecimalValue.parse('2.4'),
        minimumWholesaleAmount: const Money.ars(15000000),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );

    final restored = await repository.getOrCreateDefaults();
    expect(restored.businessName, 'Manos Chacabuco Taller');
    expect(restored.defaultWastePercentage.toPercentString(), '2.0');
    expect(restored.defaultThreadPercentage.toPercentString(), '7.5');
    expect(restored.defaultRetailPercentage?.toPercentString(), '20.0');
    expect(restored.defaultProductMultiplier, DecimalValue.parse('2.4'));
    expect(restored.minimumWholesaleAmount, const Money.ars(15000000));
    expect(restored.updatedAt, DateTime.utc(2026, 9, 1));
  });

  test(
    'crea, edita, recupera y elimina materias primas con variantes',
    () async {
      final database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = SqliteMaterialRepository(database);
      final catalog = SqliteMaterialCatalogRepository(database);
      final category = (await catalog.findCategories()).firstWhere(
        (value) => value.name == 'Cordones',
      );
      final meter = (await catalog.findUnits()).firstWhere(
        (value) => value.code == 'meter',
      );
      final createdAt = DateTime.utc(2026, 9, 1, 12);
      final material = Material(
        metadata: SyncMetadata(
          id: 'material-1',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        name: 'Cordón de algodón',
        categoryId: category.metadata.id,
        purchase: _presentation(
          unitId: meter.id,
          amount: '20',
          priceMinor: 1000000,
        ),
        consumptionUnitId: meter.id,
        brandOrSupplier: 'Proveedor local',
      );
      final variant = MaterialVariant(
        metadata: SyncMetadata(
          id: 'variant-1',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        materialId: material.metadata.id,
        name: 'Negro',
        purchaseOverride: _presentation(
          unitId: meter.id,
          amount: '20',
          priceMinor: 1100000,
        ),
        notes: 'Lote mate',
      );

      await repository.saveAggregate(material, [variant]);
      expect((await repository.findAll()).single.name, 'Cordón de algodón');
      expect(
        (await repository.findVariants(material.metadata.id)).single.notes,
        'Lote mate',
      );

      final editedAt = DateTime.utc(2026, 9, 2, 8);
      final edited = Material(
        metadata: SyncMetadata(
          id: material.metadata.id,
          createdAt: createdAt,
          updatedAt: editedAt,
        ),
        name: 'Cordón premium',
        categoryId: category.metadata.id,
        purchase: material.purchase,
        consumptionUnitId: meter.id,
        isActive: false,
      );
      final editedVariant = MaterialVariant(
        metadata: SyncMetadata(
          id: variant.metadata.id,
          createdAt: createdAt,
          updatedAt: editedAt,
        ),
        materialId: material.metadata.id,
        name: 'Negro azabache',
        purchaseOverride: variant.purchaseOverride,
        notes: 'Precio actualizado',
      );
      await repository.saveAggregate(edited, [editedVariant]);

      expect(await repository.findAll(), isEmpty);
      expect(
        (await repository.findAll(includeInactive: true)).single.name,
        'Cordón premium',
      );
      expect(
        (await repository.findAll(includeInactive: true)).single.isActive,
        isFalse,
      );
      expect(
        (await repository.findVariants(material.metadata.id)).single.name,
        'Negro azabache',
      );
      expect(
        () => catalog.deleteCategory(category.metadata.id),
        throwsA(isA<CategoryInUseException>()),
      );

      await repository.softDelete(
        material.metadata.id,
        DateTime.utc(2026, 9, 3),
      );
      expect(await repository.findById(material.metadata.id), isNull);
      expect(await repository.findVariants(material.metadata.id), isEmpty);
    },
  );

  test(
    'migra una base v3 a la versión actual sin perder datos previos',
    () async {
      final directory = await Directory.systemTemp.createTemp('manos-v3-');
      addTearDown(() => directory.delete(recursive: true));
      final path = paths.join(directory.path, 'manos.db');
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (database, version) =>
              DatabaseMigrations.migrate(database, 0, version),
        ),
      );
      final category = (await oldDatabase.query('material_categories')).first;
      final unit = (await oldDatabase.query(
        'measurement_units',
        where: 'code = ?',
        whereArgs: ['meter'],
      )).single;
      final now = DateTime.utc(2026, 9, 1).toIso8601String();
      await oldDatabase.insert('materials', {
        'id': 'retained-material',
        'category_id': category['id'],
        'name': 'Material conservado',
        'purchase_quantity_scaled': DecimalValue.parse('10').scaledValue,
        'purchase_unit_id': unit['id'],
        'purchase_price_minor': 123400,
        'currency': 'ARS',
        'consumption_unit_id': unit['id'],
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await oldDatabase.insert('quotes', {
        'id': 'retained-quote',
        'customer_name': 'Cliente conservado',
        'quote_date': DateTime.utc(2026, 9, 2).toIso8601String(),
        'valid_until': DateTime.utc(2026, 9, 17).toIso8601String(),
        'notes': 'Dato previo',
        'created_at': now,
        'updated_at': now,
      });
      await oldDatabase.close();

      final upgraded = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(upgraded.close);
      expect(
        await upgraded.database.getVersion(),
        DatabaseMigrations.currentVersion,
      );
      expect(
        (await SqliteMaterialRepository(upgraded).findAll()).single.name,
        'Material conservado',
      );
      expect(
        await SqliteProductCatalogRepository(upgraded).findCategories(),
        hasLength(8),
      );
      final quote = (await upgraded.database.query(
        'quotes',
        where: 'id = ?',
        whereArgs: ['retained-quote'],
      )).single;
      expect(quote['customer_name'], 'Cliente conservado');
      expect(quote['validity_days'], 15);
      expect(quote['price_type'], 'retail');
    },
  );

  test('migra realmente v5 a la versión actual y conserva todos los datos existentes', () async {
    final directory = await Directory.systemTemp.createTemp('manos-v5-');
    addTearDown(() => directory.delete(recursive: true));
    final path = paths.join(directory.path, 'manos.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (database, version) =>
            DatabaseMigrations.migrate(database, 0, version),
      ),
    );
    final materialCategory = (await oldDatabase.query('material_categories'))
        .first;
    final productCategory = (await oldDatabase.query('product_categories'))
        .first;
    final gram = (await oldDatabase.query(
      'measurement_units',
      where: 'code = ?',
      whereArgs: ['gram'],
    )).single;
    final now = DateTime.utc(2026, 9, 2).toIso8601String();
    await oldDatabase.insert('app_settings', {
      'singleton_id': 1,
      'business_name': 'Taller conservado',
      'currency': 'ARS',
      'default_waste_scaled': 15000,
      'default_thread_scaled': 60000,
      'updated_at': now,
    });
    await oldDatabase.insert('materials', {
      'id': 'material-v4',
      'category_id': materialCategory['id'],
      'name': 'Cordón conservado',
      'purchase_quantity_scaled': DecimalValue.parse('1000').scaledValue,
      'purchase_unit_id': gram['id'],
      'purchase_price_minor': 100000,
      'currency': 'ARS',
      'consumption_unit_id': gram['id'],
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('products', {
      'id': 'product-v4',
      'category_id': productCategory['id'],
      'name': 'Cesto conservado',
      'price_multiplier_scaled': DecimalValue.parse('2').scaledValue,
      'geometry_profile_json': '{"version":1,"shapeCode":"cylinder","components":["base","lateral"],"dimensionBindings":{"diameter":"Diámetro","height":"Alto"},"lidType":"none"}',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('product_material_usages', {
      'id': 'usage-v4',
      'product_id': 'product-v4',
      'material_id': 'material-v4',
      'amount_scaled': DecimalValue.parse('400').scaledValue,
      'unit_id': gram['id'],
      'role': 'primary',
      'consumption_source': 'confirmed',
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('quotes', {
      'id': 'quote-v4',
      'customer_name': 'Cliente conservado',
      'quote_date': now,
      'valid_until': DateTime.utc(2026, 9, 17).toIso8601String(),
      'validity_days': 15,
      'price_type': 'retail',
      'currency': 'ARS',
      'total_minor': 123456,
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('quote_items', {
      'id': 'item-v4',
      'quote_id': 'quote-v4',
      'source_product_id': 'product-v4',
      'description': 'Ítem conservado',
      'quantity_scaled': DecimalValue.scale,
      'unit_price_minor': 123456,
      'currency': 'ARS',
      'price_multiplier_scaled': DecimalValue.parse('2').scaledValue,
      'snapshot_json': '{"version":1,"dato":"snapshot conservado"}',
      'geometry_profile_json': '{"version":1,"shapeCode":"circle","components":["base"],"dimensionBindings":{"diameter":"Diámetro"},"lidType":"none"}',
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);

    expect(
      await upgraded.database.getVersion(),
      DatabaseMigrations.currentVersion,
    );
    expect(
      (await upgraded.database.query('app_settings')).single['business_name'],
      'Taller conservado',
    );
    expect(
      (await upgraded.database.query('materials')).single['name'],
      'Cordón conservado',
    );
    final product = (await upgraded.database.query('products')).single;
    expect(product['name'], 'Cesto conservado');
    expect(product['geometry_profile_json'], contains('cylinder'));
    final usage = (await upgraded.database.query('product_material_usages'))
        .single;
    expect(usage['consumption_source'], 'confirmed');
    expect(usage['calibration_eligible'], 1);
    final item = (await upgraded.database.query('quote_items')).single;
    expect(item['snapshot_json'], contains('snapshot conservado'));
    expect(item['geometry_profile_json'], contains('circle'));
    expect(await upgraded.database.query('import_records'), isEmpty);
  });

  test('migra v7 a v8 sin alterar productos, presupuestos, preferencias ni importaciones', () async {
    final directory = await Directory.systemTemp.createTemp('manos-v6-');
    addTearDown(() => directory.delete(recursive: true));
    final path = paths.join(directory.path, 'manos.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (database, version) =>
            DatabaseMigrations.migrate(database, 0, version),
      ),
    );
    final productCategory = (await oldDatabase.query('product_categories'))
        .first;
    final now = DateTime.utc(2026, 9, 3).toIso8601String();
    await oldDatabase.insert('app_settings', {
      'singleton_id': 1,
      'business_name': 'Manos conservado',
      'currency': 'ARS',
      'default_waste_scaled': 15000,
      'default_thread_scaled': 60000,
      'updated_at': now,
    });
    await oldDatabase.insert('products', {
      'id': 'product-v6',
      'category_id': productCategory['id'],
      'name': 'Producto que no se pierde',
      'price_multiplier_scaled': DecimalValue.parse('2.4').scaledValue,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('quotes', {
      'id': 'quote-v6',
      'customer_name': 'Cliente que no se pierde',
      'quote_date': now,
      'valid_until': DateTime.utc(2026, 9, 18).toIso8601String(),
      'validity_days': 15,
      'price_type': 'retail',
      'currency': 'ARS',
      'total_minor': 987654,
      'created_at': now,
      'updated_at': now,
    });
    await oldDatabase.insert('import_records', {
      'id': 'import-v6',
      'source_key': 'archivo|hoja|producto|1',
      'spreadsheet_id': 'archivo',
      'sheet_name': 'Productos',
      'source_row': 1,
      'section': 'Catálogo',
      'record_type': 'product',
      'target_id': 'product-v6',
      'original_name': 'Producto que no se pierde',
      'imported_at': now,
      'last_seen_at': now,
    });
    await oldDatabase.insert('price_list_preferences', {
      'price_type': 'retail',
      'config_json': '{"version":1,"showPhotos":false}',
      'updated_at': now,
    });
    await oldDatabase.close();

    final upgraded = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(upgraded.close);

    expect(await upgraded.database.getVersion(), 8);
    expect(
      (await upgraded.database.query('products')).single['name'],
      'Producto que no se pierde',
    );
    expect(
      (await upgraded.database.query('quotes')).single['customer_name'],
      'Cliente que no se pierde',
    );
    expect(
      (await upgraded.database.query('import_records')).single['target_id'],
      'product-v6',
    );
    final settingsColumns = await upgraded.database.rawQuery(
      'PRAGMA table_info(app_settings)',
    );
    expect(
      settingsColumns.map((row) => row['name']),
      contains('business_logo_path'),
    );
    expect(
      (await upgraded.database.query('price_list_preferences'))
          .single['config_json'],
      contains('showPhotos'),
    );
    expect(await upgraded.database.query('sync_outbox'), isNotEmpty);
    expect(await upgraded.database.query('sync_entity_state'), isEmpty);
  });
}

PurchasePresentation _presentation({
  required String unitId,
  required String amount,
  required int priceMinor,
}) => PurchasePresentation(
  quantity: MeasuredQuantity(
    amount: DecimalValue.parse(amount),
    unitId: unitId,
  ),
  price: Money.ars(priceMinor),
);
