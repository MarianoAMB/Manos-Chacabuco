import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/money/decimal_value.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/materials/material_models.dart';
import '../../domain/pricing/pricing_models.dart';
import '../../domain/products/product_models.dart';
import '../../domain/repositories/product_repository.dart';

final class SqliteProductRepository implements ProductRepository {
  SqliteProductRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<Product>> findAll({bool includeInactive = false}) async {
    final rows = await _appDatabase.database.query(
      'products',
      where: includeInactive
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND is_active = 1',
      orderBy: 'is_active DESC, name COLLATE NOCASE',
    );
    return rows.map(_productFromRow).toList(growable: false);
  }

  @override
  Future<Product?> findById(String id) async {
    final rows = await _appDatabase.database.query(
      'products',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _productFromRow(rows.single);
  }

  @override
  Future<List<ProductMaterialUsage>> findUsages(String productId) async {
    final rows = await _appDatabase.database.query(
      'product_material_usages',
      where: 'product_id = ? AND deleted_at IS NULL',
      whereArgs: [productId],
      orderBy: 'created_at, id',
    );
    return rows.map(_usageFromRow).toList(growable: false);
  }

  @override
  Future<void> saveAggregate(
    Product product,
    List<ProductMaterialUsage> usages,
  ) async {
    await _appDatabase.database.transaction((transaction) async {
      await _upsert(
        transaction,
        table: 'products',
        id: product.metadata.id,
        values: _productToRow(product),
      );
      final existing = await transaction.query(
        'product_material_usages',
        columns: const ['id'],
        where: 'product_id = ? AND deleted_at IS NULL',
        whereArgs: [product.metadata.id],
      );
      final incomingIds = usages.map((usage) => usage.metadata.id).toSet();
      final timestamp = product.metadata.updatedAt.toUtc().toIso8601String();
      for (final row in existing) {
        final id = row['id']! as String;
        if (!incomingIds.contains(id)) {
          await transaction.update(
            'product_material_usages',
            {'deleted_at': timestamp, 'updated_at': timestamp},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      for (final usage in usages) {
        await _upsert(
          transaction,
          table: 'product_material_usages',
          id: usage.metadata.id,
          values: _usageToRow(usage),
        );
      }
    });
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await _appDatabase.database.transaction((transaction) async {
      await transaction.update(
        'product_material_usages',
        {'deleted_at': timestamp, 'updated_at': timestamp},
        where: 'product_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
      await transaction.update(
        'products',
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

  Product _productFromRow(Map<String, Object?> row) {
    final dimensionsJson = row['dimensions_json'] as String?;
    final decoded = dimensionsJson == null
        ? null
        : jsonDecode(dimensionsJson) as Map<String, dynamic>;
    final dimensions = decoded == null
        ? null
        : ProductDimensions(
            shapeCode: (row['shape_code'] as String?) ?? 'custom',
            values: {
              for (final entry in decoded.entries)
                entry.key: MeasuredQuantity(
                  amount: DecimalValue.scaled(
                    (entry.value as Map<String, dynamic>)['amount'] as int,
                  ),
                  unitId:
                      (entry.value as Map<String, dynamic>)['unit'] as String,
                ),
            },
          );
    return Product(
      metadata: _metadataFromRow(row),
      name: row['name']! as String,
      categoryId: row['category_id']! as String,
      priceMultiplier: DecimalValue.scaled(
        row['price_multiplier_scaled']! as int,
      ),
      description: row['description'] as String?,
      photoPath: row['photo_path'] as String?,
      dimensions: dimensions,
      geometryProfile: switch (row['geometry_profile_json']) {
        final String value => GeometryProfile.fromJson(
          Map<String, Object?>.from(jsonDecode(value) as Map),
        ),
        _ => null,
      },
      pricingOverrides: PricingOverrides(
        wastePercentage: _decimalOrNull(row['waste_override_scaled']),
        threadPercentage: _decimalOrNull(row['thread_override_scaled']),
        retailPercentage: _decimalOrNull(row['retail_override_scaled']),
      ),
      notes: row['notes'] as String?,
      isActive: (row['is_active']! as int) == 1,
    );
  }

  ProductMaterialUsage _usageFromRow(Map<String, Object?> row) =>
      ProductMaterialUsage(
        metadata: _metadataFromRow(row),
        productId: row['product_id']! as String,
        materialId: row['material_id']! as String,
        materialVariantId: row['material_variant_id'] as String?,
        consumption: MeasuredQuantity(
          amount: DecimalValue.scaled(row['amount_scaled']! as int),
          unitId: row['unit_id']! as String,
        ),
        role: ProductMaterialRole.values.byName(row['role']! as String),
        consumptionSource: ConsumptionSource.values.byName(
          (row['consumption_source'] as String?) ??
              ConsumptionSource.manual.name,
        ),
        calibrationEligible: ((row['calibration_eligible'] as int?) ?? 1) == 1,
        notes: row['notes'] as String?,
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

  DecimalValue? _decimalOrNull(Object? value) =>
      value == null ? null : DecimalValue.scaled(value as int);

  Map<String, Object?> _productToRow(Product product) => {
    'id': product.metadata.id,
    'category_id': product.categoryId,
    'name': product.name.trim(),
    'description': product.description?.trim(),
    'photo_path': product.photoPath,
    'shape_code': product.dimensions?.shapeCode,
    'dimensions_json': product.dimensions == null
        ? null
        : jsonEncode({
            for (final entry in product.dimensions!.values.entries)
              entry.key: {
                'amount': entry.value.amount.scaledValue,
                'unit': entry.value.unitId,
              },
          }),
    'geometry_profile_json': product.geometryProfile == null
        ? null
        : jsonEncode(product.geometryProfile!.toJson()),
    'waste_override_scaled':
        product.pricingOverrides.wastePercentage?.scaledValue,
    'thread_override_scaled':
        product.pricingOverrides.threadPercentage?.scaledValue,
    'retail_override_scaled':
        product.pricingOverrides.retailPercentage?.scaledValue,
    'price_multiplier_scaled': product.priceMultiplier.scaledValue,
    'notes': product.notes?.trim(),
    'is_active': product.isActive ? 1 : 0,
    'created_at': product.metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': product.metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': product.metadata.deletedAt?.toUtc().toIso8601String(),
  };

  Map<String, Object?> _usageToRow(ProductMaterialUsage usage) => {
    'id': usage.metadata.id,
    'product_id': usage.productId,
    'material_id': usage.materialId,
    'material_variant_id': usage.materialVariantId,
    'amount_scaled': usage.consumption.amount.scaledValue,
    'unit_id': usage.consumption.unitId,
    'role': usage.role.name,
    'consumption_source': usage.consumptionSource.name,
    'calibration_eligible': usage.calibrationEligible ? 1 : 0,
    'notes': usage.notes?.trim(),
    'created_at': usage.metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': usage.metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': usage.metadata.deletedAt?.toUtc().toIso8601String(),
  };
}
