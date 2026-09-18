import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/products/product_models.dart';
import '../../domain/repositories/product_catalog_repository.dart';

final class SqliteProductCatalogRepository implements ProductCatalogRepository {
  SqliteProductCatalogRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<ProductCategory>> findCategories() async {
    final rows = await _appDatabase.database.query(
      'product_categories',
      where: 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => ProductCategory(
            metadata: SyncMetadata(
              id: row['id']! as String,
              createdAt: DateTime.parse(row['created_at']! as String),
              updatedAt: DateTime.parse(row['updated_at']! as String),
              deletedAt: switch (row['deleted_at']) {
                final String value => DateTime.parse(value),
                _ => null,
              },
            ),
            name: row['name']! as String,
            isActive: (row['is_active']! as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveCategory(ProductCategory category) async {
    final row = {
      'id': category.metadata.id,
      'name': category.name.trim(),
      'is_active': category.isActive ? 1 : 0,
      'created_at': category.metadata.createdAt.toUtc().toIso8601String(),
      'updated_at': category.metadata.updatedAt.toUtc().toIso8601String(),
      'deleted_at': category.metadata.deletedAt?.toUtc().toIso8601String(),
    };
    try {
      await _appDatabase.database.transaction((transaction) async {
        if (category.metadata.deletedAt == null) {
          // Sync may leave same-name IDs on this device. An unchanged name
          // must remain editable; creating or restoring a duplicate must not.
          final alreadyHasName = await transaction.query(
            'product_categories',
            columns: ['id'],
            where: 'id = ? AND name = ? COLLATE NOCASE AND deleted_at IS NULL',
            whereArgs: [category.metadata.id, row['name']],
            limit: 1,
          );
          if (alreadyHasName.isEmpty) {
            final duplicate = await transaction.query(
              'product_categories',
              columns: ['id'],
              where:
                  'id <> ? AND name = ? COLLATE NOCASE AND deleted_at IS NULL',
              whereArgs: [category.metadata.id, row['name']],
              limit: 1,
            );
            if (duplicate.isNotEmpty) {
              throw const DuplicateProductCategoryException();
            }
          }
        }

        final updated = await transaction.update(
          'product_categories',
          row,
          where: 'id = ?',
          whereArgs: [category.metadata.id],
        );
        if (updated == 0) {
          await transaction.insert('product_categories', row);
        }
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateProductCategoryException();
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    final usage = Sqflite.firstIntValue(
      await _appDatabase.database.rawQuery(
        'SELECT COUNT(*) FROM products WHERE category_id = ? AND deleted_at IS NULL',
        [id],
      ),
    );
    if ((usage ?? 0) > 0) throw const ProductCategoryInUseException();
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await _appDatabase.database.update(
      'product_categories',
      {'deleted_at': timestamp, 'updated_at': timestamp},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
