import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/money/decimal_value.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/materials/material_models.dart';
import '../../domain/repositories/material_catalog_repository.dart';

final class SqliteMaterialCatalogRepository
    implements MaterialCatalogRepository {
  SqliteMaterialCatalogRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<MeasurementUnit>> findUnits() async {
    final rows = await _appDatabase.database.query(
      'measurement_units',
      where: 'deleted_at IS NULL',
      orderBy: 'dimension, base_unit_factor_scaled',
    );
    return rows.map(_unitFromRow).toList(growable: false);
  }

  @override
  Future<List<MaterialCategory>> findCategories() async {
    final rows = await _appDatabase.database.query(
      'material_categories',
      where: 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(_categoryFromRow).toList(growable: false);
  }

  @override
  Future<void> saveCategory(MaterialCategory category) async {
    final row = _categoryToRow(category);
    try {
      final updated = await _appDatabase.database.update(
        'material_categories',
        row,
        where: 'id = ?',
        whereArgs: [category.metadata.id],
      );
      if (updated == 0) {
        await _appDatabase.database.insert('material_categories', row);
      }
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const DuplicateCategoryException();
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteCategory(String id) async {
    final usage = Sqflite.firstIntValue(
      await _appDatabase.database.rawQuery(
        'SELECT COUNT(*) FROM materials WHERE category_id = ?',
        [id],
      ),
    );
    if ((usage ?? 0) > 0) throw const CategoryInUseException();
    await _appDatabase.database.delete(
      'material_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  MeasurementUnit _unitFromRow(Map<String, Object?> row) => MeasurementUnit(
    id: row['id']! as String,
    code: row['code']! as String,
    name: row['name']! as String,
    symbol: row['symbol']! as String,
    dimension: MeasurementDimension.values.byName(row['dimension']! as String),
    baseUnitFactor: DecimalValue.scaled(row['base_unit_factor_scaled']! as int),
  );

  MaterialCategory _categoryFromRow(Map<String, Object?> row) =>
      MaterialCategory(
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
      );

  Map<String, Object?> _categoryToRow(MaterialCategory category) => {
    'id': category.metadata.id,
    'name': category.name.trim(),
    'is_active': category.isActive ? 1 : 0,
    'created_at': category.metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': category.metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': category.metadata.deletedAt?.toUtc().toIso8601String(),
  };
}
