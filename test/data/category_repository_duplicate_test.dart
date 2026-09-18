import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/repositories/material_catalog_repository.dart';
import 'package:manos_chacabuco/domain/repositories/product_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('material categories reject new collisions but stay editable', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteMaterialCatalogRepository(database);
    final original = (await repository.findCategories()).first;
    final now = DateTime.utc(2026, 9, 18);

    await expectLater(
      repository.saveCategory(
        MaterialCategory(
          metadata: SyncMetadata(
            id: 'new-material-category',
            createdAt: now,
            updatedAt: now,
          ),
          name: original.name.toUpperCase(),
          isActive: false,
        ),
      ),
      throwsA(isA<DuplicateCategoryException>()),
    );

    final distinct = MaterialCategory(
      metadata: SyncMetadata(
        id: 'distinct-material-category',
        createdAt: now,
        updatedAt: now,
      ),
      name: 'Categoría propia de materiales',
    );
    await repository.saveCategory(distinct);
    await expectLater(
      repository.saveCategory(
        MaterialCategory(metadata: distinct.metadata, name: original.name),
      ),
      throwsA(isA<DuplicateCategoryException>()),
    );

    // Two devices may have created separate IDs before synchronizing.
    await database.database.insert('material_categories', {
      'id': 'synced-material-category',
      'name': original.name,
      'is_active': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
    });
    await repository.saveCategory(
      MaterialCategory(
        metadata: SyncMetadata(
          id: original.metadata.id,
          createdAt: original.metadata.createdAt,
          updatedAt: now,
        ),
        name: original.name,
        isActive: false,
      ),
    );
    expect(
      (await repository.findCategories())
          .firstWhere(
            (category) => category.metadata.id == original.metadata.id,
          )
          .isActive,
      isFalse,
    );

    final deleted = MaterialCategory(
      metadata: SyncMetadata(
        id: 'restored-material-category',
        createdAt: now,
        updatedAt: now,
        deletedAt: now,
      ),
      name: original.name,
    );
    await repository.saveCategory(deleted);
    await expectLater(
      repository.saveCategory(
        MaterialCategory(
          metadata: SyncMetadata(
            id: deleted.metadata.id,
            createdAt: now,
            updatedAt: now,
          ),
          name: original.name,
        ),
      ),
      throwsA(isA<DuplicateCategoryException>()),
    );
  });

  test('product categories reject new collisions but stay editable', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteProductCatalogRepository(database);
    final original = (await repository.findCategories()).first;
    final now = DateTime.utc(2026, 9, 18);

    await expectLater(
      repository.saveCategory(
        ProductCategory(
          metadata: SyncMetadata(
            id: 'new-product-category',
            createdAt: now,
            updatedAt: now,
          ),
          name: original.name.toUpperCase(),
          isActive: false,
        ),
      ),
      throwsA(isA<DuplicateProductCategoryException>()),
    );

    final distinct = ProductCategory(
      metadata: SyncMetadata(
        id: 'distinct-product-category',
        createdAt: now,
        updatedAt: now,
      ),
      name: 'Categoría propia de productos',
    );
    await repository.saveCategory(distinct);
    await expectLater(
      repository.saveCategory(
        ProductCategory(metadata: distinct.metadata, name: original.name),
      ),
      throwsA(isA<DuplicateProductCategoryException>()),
    );

    await database.database.insert('product_categories', {
      'id': 'synced-product-category',
      'name': original.name,
      'is_active': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
    });
    await repository.saveCategory(
      ProductCategory(
        metadata: SyncMetadata(
          id: original.metadata.id,
          createdAt: original.metadata.createdAt,
          updatedAt: now,
        ),
        name: original.name,
        isActive: false,
      ),
    );
    expect(
      (await repository.findCategories())
          .firstWhere(
            (category) => category.metadata.id == original.metadata.id,
          )
          .isActive,
      isFalse,
    );

    final deleted = ProductCategory(
      metadata: SyncMetadata(
        id: 'restored-product-category',
        createdAt: now,
        updatedAt: now,
        deletedAt: now,
      ),
      name: original.name,
    );
    await repository.saveCategory(deleted);
    await expectLater(
      repository.saveCategory(
        ProductCategory(
          metadata: SyncMetadata(
            id: deleted.metadata.id,
            createdAt: now,
            updatedAt: now,
          ),
          name: original.name,
        ),
      ),
      throwsA(isA<DuplicateProductCategoryException>()),
    );
  });
}
