import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/materials/material_models.dart';
import '../../domain/repositories/material_repository.dart';
import '../../domain/repositories/product_repository.dart';

final class SqliteMaterialRepository implements MaterialRepository {
  SqliteMaterialRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<Material>> findAll({bool includeInactive = false}) async {
    final rows = await _appDatabase.database.query(
      'materials',
      where: includeInactive
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND is_active = 1',
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(_materialFromRow).toList(growable: false);
  }

  @override
  Future<Material?> findById(String id) async {
    final rows = await _appDatabase.database.query(
      'materials',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _materialFromRow(rows.single);
  }

  @override
  Future<List<MaterialVariant>> findVariants(String materialId) async {
    final rows = await _appDatabase.database.query(
      'material_variants',
      where: 'material_id = ? AND deleted_at IS NULL',
      whereArgs: [materialId],
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(_variantFromRow).toList(growable: false);
  }

  @override
  Future<void> saveAggregate(
    Material material,
    List<MaterialVariant> variants,
  ) async {
    await _appDatabase.database.transaction((transaction) async {
      await _upsert(
        transaction,
        table: 'materials',
        id: material.metadata.id,
        values: _materialToRow(material),
      );

      final existingRows = await transaction.query(
        'material_variants',
        columns: const ['id'],
        where: 'material_id = ? AND deleted_at IS NULL',
        whereArgs: [material.metadata.id],
      );
      final incomingIds = variants
          .map((variant) => variant.metadata.id)
          .toSet();
      final removedIds = existingRows
          .map((row) => row['id']! as String)
          .where((id) => !incomingIds.contains(id));
      for (final id in removedIds) {
        final usage = Sqflite.firstIntValue(
          await transaction.rawQuery(
            'SELECT COUNT(*) FROM product_material_usages WHERE material_variant_id = ? AND deleted_at IS NULL',
            [id],
          ),
        );
        if ((usage ?? 0) > 0) {
          throw const MaterialVariantInUseException();
        }
        await transaction.update(
          'material_variants',
          {
            'deleted_at': material.metadata.updatedAt.toUtc().toIso8601String(),
            'updated_at': material.metadata.updatedAt.toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      for (final variant in variants) {
        await _upsert(
          transaction,
          table: 'material_variants',
          id: variant.metadata.id,
          values: _variantToRow(variant),
        );
      }
    });
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await _appDatabase.database.transaction((transaction) async {
      final usage = Sqflite.firstIntValue(
        await transaction.rawQuery(
          'SELECT COUNT(*) FROM product_material_usages WHERE material_id = ? AND deleted_at IS NULL',
          [id],
        ),
      );
      if ((usage ?? 0) > 0) throw const MaterialInUseException();
      await transaction.update(
        'material_variants',
        {'deleted_at': timestamp, 'updated_at': timestamp},
        where: 'material_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      await transaction.update(
        'materials',
        {'deleted_at': timestamp, 'updated_at': timestamp},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> _upsert(
    DatabaseExecutor executor, {
    required String table,
    required String id,
    required Map<String, Object?> values,
  }) async {
    final updated = await executor.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) await executor.insert(table, values);
  }

  Material _materialFromRow(Map<String, Object?> row) => Material(
    metadata: _metadataFromRow(row),
    name: row['name']! as String,
    categoryId: row['category_id']! as String,
    description: row['description'] as String?,
    purchase: PurchasePresentation(
      quantity: MeasuredQuantity(
        amount: DecimalValue.scaled(row['purchase_quantity_scaled']! as int),
        unitId: row['purchase_unit_id']! as String,
      ),
      price: Money(
        minorUnits: row['purchase_price_minor']! as int,
        currency: row['currency']! as String,
      ),
    ),
    consumptionUnitId: row['consumption_unit_id']! as String,
    brandOrSupplier: row['brand_or_supplier'] as String?,
    notes: row['notes'] as String?,
    isActive: (row['is_active']! as int) == 1,
  );

  MaterialVariant _variantFromRow(Map<String, Object?> row) => MaterialVariant(
    metadata: _metadataFromRow(row),
    materialId: row['material_id']! as String,
    name: row['name']! as String,
    purchaseOverride: row['purchase_quantity_scaled'] == null
        ? null
        : PurchasePresentation(
            quantity: MeasuredQuantity(
              amount: DecimalValue.scaled(
                row['purchase_quantity_scaled']! as int,
              ),
              unitId: row['purchase_unit_id']! as String,
            ),
            price: Money(
              minorUnits: row['purchase_price_minor']! as int,
              currency: row['currency']! as String,
            ),
          ),
    notes: row['notes'] as String?,
    isActive: (row['is_active']! as int) == 1,
  );

  SyncMetadata _metadataFromRow(Map<String, Object?> row) => SyncMetadata(
    id: row['id']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: switch (row['deleted_at']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
  );

  Map<String, Object?> _materialToRow(Material material) => {
    'id': material.metadata.id,
    'category_id': material.categoryId,
    'name': material.name.trim(),
    'description': material.description?.trim(),
    'purchase_quantity_scaled': material.purchase.quantity.amount.scaledValue,
    'purchase_unit_id': material.purchase.quantity.unitId,
    'purchase_price_minor': material.purchase.price.minorUnits,
    'currency': material.purchase.price.currency,
    'consumption_unit_id': material.consumptionUnitId,
    'brand_or_supplier': material.brandOrSupplier?.trim(),
    'notes': material.notes?.trim(),
    'is_active': material.isActive ? 1 : 0,
    'created_at': material.metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': material.metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': material.metadata.deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> _variantToRow(MaterialVariant variant) => {
    'id': variant.metadata.id,
    'material_id': variant.materialId,
    'name': variant.name.trim(),
    'purchase_quantity_scaled':
        variant.purchaseOverride?.quantity.amount.scaledValue,
    'purchase_unit_id': variant.purchaseOverride?.quantity.unitId,
    'purchase_price_minor': variant.purchaseOverride?.price.minorUnits,
    'currency': variant.purchaseOverride?.price.currency,
    'notes': variant.notes?.trim(),
    'is_active': variant.isActive ? 1 : 0,
    'created_at': variant.metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': variant.metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': variant.metadata.deletedAt?.toUtc().toIso8601String(),
  };
}
