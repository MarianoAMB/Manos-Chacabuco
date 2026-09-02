import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/geometry/geometry_models.dart';
import '../../domain/materials/material_models.dart';
import '../../domain/pricing/pricing_models.dart';
import '../../domain/products/product_models.dart';
import '../../domain/quotes/quote_models.dart';
import '../../domain/repositories/quote_repository.dart';

final class SqliteQuoteRepository implements QuoteRepository {
  SqliteQuoteRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<QuoteAggregate>> findAll() async {
    final rows = await _appDatabase.database.query(
      'quotes',
      where: 'deleted_at IS NULL',
      orderBy: 'quote_date DESC, updated_at DESC',
    );
    return Future.wait(rows.map((row) => _aggregateFromQuoteRow(row)));
  }

  @override
  Future<QuoteAggregate?> findById(String id) async {
    final rows = await _appDatabase.database.query(
      'quotes',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _aggregateFromQuoteRow(rows.single);
  }

  Future<QuoteAggregate> _aggregateFromQuoteRow(
    Map<String, Object?> row,
  ) async {
    final quote = _quoteFromRow(row);
    final results = await Future.wait([
      _appDatabase.database.query(
        'quote_items',
        where: 'quote_id = ? AND deleted_at IS NULL',
        whereArgs: [quote.metadata.id],
        orderBy: 'created_at, id',
      ),
      _appDatabase.database.query(
        'quote_adjustments',
        where: 'quote_id = ? AND deleted_at IS NULL',
        whereArgs: [quote.metadata.id],
        orderBy: 'created_at, id',
      ),
    ]);
    return QuoteAggregate(
      quote: quote,
      items: results[0].map(_itemFromRow).toList(growable: false),
      adjustments: results[1].map(_adjustmentFromRow).toList(growable: false),
    );
  }

  @override
  Future<void> saveAggregate(QuoteAggregate aggregate) async {
    await _appDatabase.database.transaction((transaction) async {
      await _upsert(
        transaction,
        table: 'quotes',
        id: aggregate.quote.metadata.id,
        values: _quoteToRow(aggregate.quote),
      );
      await _softDeleteMissing(
        transaction,
        table: 'quote_items',
        quoteId: aggregate.quote.metadata.id,
        incomingIds: aggregate.items.map((item) => item.metadata.id).toSet(),
        timestamp: aggregate.quote.metadata.updatedAt,
      );
      await _softDeleteMissing(
        transaction,
        table: 'quote_adjustments',
        quoteId: aggregate.quote.metadata.id,
        incomingIds: aggregate.adjustments
            .map((item) => item.metadata.id)
            .toSet(),
        timestamp: aggregate.quote.metadata.updatedAt,
      );
      for (final item in aggregate.items) {
        await _upsert(
          transaction,
          table: 'quote_items',
          id: item.metadata.id,
          values: _itemToRow(item),
        );
      }
      for (final adjustment in aggregate.adjustments) {
        await _upsert(
          transaction,
          table: 'quote_adjustments',
          id: adjustment.metadata.id,
          values: _adjustmentToRow(adjustment),
        );
      }
    });
  }

  @override
  Future<void> softDelete(String id, DateTime deletedAt) async {
    final timestamp = deletedAt.toUtc().toIso8601String();
    await _appDatabase.database.transaction((transaction) async {
      for (final table in ['quote_adjustments', 'quote_items', 'quotes']) {
        await transaction.update(
          table,
          {'deleted_at': timestamp, 'updated_at': timestamp},
          where: table == 'quotes'
              ? 'id = ? AND deleted_at IS NULL'
              : 'quote_id = ? AND deleted_at IS NULL',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> _softDeleteMissing(
    DatabaseExecutor executor, {
    required String table,
    required String quoteId,
    required Set<String> incomingIds,
    required DateTime timestamp,
  }) async {
    final existing = await executor.query(
      table,
      columns: const ['id'],
      where: 'quote_id = ? AND deleted_at IS NULL',
      whereArgs: [quoteId],
    );
    final value = timestamp.toUtc().toIso8601String();
    for (final row in existing) {
      final id = row['id']! as String;
      if (!incomingIds.contains(id)) {
        await executor.update(
          table,
          {'deleted_at': value, 'updated_at': value},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
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

  Quote _quoteFromRow(Map<String, Object?> row) => Quote(
    metadata: _metadataFromRow(row),
    customerName: row['customer_name']! as String,
    date: DateTime.parse(row['quote_date']! as String),
    validityDays: row['validity_days']! as int,
    validUntil: DateTime.parse(row['valid_until']! as String),
    priceType: QuotePriceType.values.byName(row['price_type']! as String),
    total: Money(
      minorUnits: row['total_minor']! as int,
      currency: row['currency']! as String,
    ),
    notes: row['notes'] as String?,
  );

  QuoteItem _itemFromRow(Map<String, Object?> row) {
    final currency = row['currency']! as String;
    final customization = _decodeMap(row['customization_json'] as String?);
    final usagesJson = customization?['usages'] as List<Object?>? ?? const [];
    final dimensionsJson = _decodeMap(row['dimensions_json'] as String?);
    final snapshotJson = _decodeMap(row['snapshot_json'] as String?);
    final unitPrice = Money(
      minorUnits: row['unit_price_minor']! as int,
      currency: currency,
    );
    return QuoteItem(
      metadata: _metadataFromRow(row),
      quoteId: row['quote_id']! as String,
      sourceProductId: row['source_product_id'] as String?,
      name: row['description']! as String,
      categoryId: row['category_id'] as String?,
      description: customization?['description'] as String?,
      personalizationDescription: row['personalization_description'] as String?,
      dimensions: _dimensionsFromJson(dimensionsJson),
      geometryProfile: switch (row['geometry_profile_json']) {
        final String value => GeometryProfile.fromJson(
          Map<String, Object?>.from(jsonDecode(value) as Map),
        ),
        _ => null,
      },
      quantity: (row['quantity_scaled']! as int) ~/ DecimalValue.scale,
      priceMultiplier: DecimalValue.scaled(
        row['price_multiplier_scaled']! as int,
      ),
      pricingOverrides: PricingOverrides(
        wastePercentage: _decimalOrNull(row['waste_override_scaled']),
        threadPercentage: _decimalOrNull(row['thread_override_scaled']),
        retailPercentage: _decimalOrNull(row['retail_override_scaled']),
      ),
      usages: [
        for (final entry in usagesJson)
          _usageFromJson(
            Map<String, Object?>.from(entry! as Map),
            row['id']! as String,
          ),
      ],
      snapshot: snapshotJson == null
          ? _legacySnapshot(unitPrice, _metadataFromRow(row).createdAt)
          : QuoteItemSnapshot.fromJson(snapshotJson),
      unitPrice: unitPrice,
    );
  }

  QuoteAdjustment _adjustmentFromRow(Map<String, Object?> row) =>
      QuoteAdjustment(
        metadata: _metadataFromRow(row),
        quoteId: row['quote_id']! as String,
        quoteItemId: row['quote_item_id'] as String?,
        description: row['description']! as String,
        amount: Money(
          minorUnits: row['amount_minor']! as int,
          currency: row['currency']! as String,
        ),
      );

  Map<String, Object?> _quoteToRow(Quote quote) => {
    'id': quote.metadata.id,
    'customer_name': quote.customerName.trim(),
    'quote_date': quote.date.toUtc().toIso8601String(),
    'validity_days': quote.validityDays,
    'valid_until': quote.validUntil.toUtc().toIso8601String(),
    'price_type': quote.priceType.name,
    'currency': quote.total.currency,
    'total_minor': quote.total.minorUnits,
    'waste_override_scaled': null,
    'retail_override_scaled': null,
    'multiplier_override_scaled': null,
    'notes': quote.notes?.trim(),
    ..._metadataToRow(quote.metadata),
  };

  Map<String, Object?> _itemToRow(QuoteItem item) => {
    'id': item.metadata.id,
    'quote_id': item.quoteId,
    'source_product_id': item.sourceProductId,
    'description': item.name.trim(),
    'category_id': item.categoryId,
    'personalization_description': item.personalizationDescription?.trim(),
    'quantity_scaled': item.quantity * DecimalValue.scale,
    'unit_price_minor': item.unitPrice.minorUnits,
    'currency': item.unitPrice.currency,
    'customization_json': jsonEncode({
      'description': item.description?.trim(),
      'usages': item.usages.map(_usageToJson).toList(),
    }),
    'dimensions_json': item.dimensions == null
        ? null
        : jsonEncode({
            'shapeCode': item.dimensions!.shapeCode,
            'values': {
              for (final entry in item.dimensions!.values.entries)
                entry.key: {
                  'amountScaled': entry.value.amount.scaledValue,
                  'unitId': entry.value.unitId,
                },
            },
          }),
    'geometry_profile_json': item.geometryProfile == null
        ? null
        : jsonEncode(item.geometryProfile!.toJson()),
    'waste_override_scaled': item.pricingOverrides.wastePercentage?.scaledValue,
    'thread_override_scaled':
        item.pricingOverrides.threadPercentage?.scaledValue,
    'retail_override_scaled':
        item.pricingOverrides.retailPercentage?.scaledValue,
    'price_multiplier_scaled': item.priceMultiplier.scaledValue,
    'snapshot_json': jsonEncode(item.snapshot.toJson()),
    ..._metadataToRow(item.metadata),
  };

  Map<String, Object?> _adjustmentToRow(QuoteAdjustment adjustment) => {
    'id': adjustment.metadata.id,
    'quote_id': adjustment.quoteId,
    'quote_item_id': adjustment.quoteItemId,
    'description': adjustment.description.trim(),
    'amount_minor': adjustment.amount.minorUnits,
    'currency': adjustment.amount.currency,
    ..._metadataToRow(adjustment.metadata),
  };

  ProductMaterialUsage _usageFromJson(
    Map<String, Object?> json,
    String itemId,
  ) => ProductMaterialUsage(
    metadata: SyncMetadata(
      id: json['id']! as String,
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
    ),
    productId: itemId,
    materialId: json['materialId']! as String,
    materialVariantId: json['variantId'] as String?,
    consumption: MeasuredQuantity(
      amount: DecimalValue.scaled(json['amountScaled']! as int),
      unitId: json['unitId']! as String,
    ),
    role: ProductMaterialRole.values.byName(json['role']! as String),
    consumptionSource: ConsumptionSource.values.byName(
      (json['consumptionSource'] as String?) ?? ConsumptionSource.manual.name,
    ),
    calibrationEligible: (json['calibrationEligible'] as bool?) ?? true,
    notes: json['notes'] as String?,
  );

  Map<String, Object?> _usageToJson(ProductMaterialUsage usage) => {
    'id': usage.metadata.id,
    'materialId': usage.materialId,
    'variantId': usage.materialVariantId,
    'amountScaled': usage.consumption.amount.scaledValue,
    'unitId': usage.consumption.unitId,
    'role': usage.role.name,
    'consumptionSource': usage.consumptionSource.name,
    'calibrationEligible': usage.calibrationEligible,
    'notes': usage.notes,
    'createdAt': usage.metadata.createdAt.toUtc().toIso8601String(),
    'updatedAt': usage.metadata.updatedAt.toUtc().toIso8601String(),
  };

  ProductDimensions? _dimensionsFromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final values = Map<String, Object?>.from(json['values']! as Map);
    return ProductDimensions(
      shapeCode: json['shapeCode']! as String,
      values: {
        for (final entry in values.entries)
          entry.key: MeasuredQuantity(
            amount: DecimalValue.scaled(
              (entry.value! as Map)['amountScaled']! as int,
            ),
            unitId: (entry.value! as Map)['unitId']! as String,
          ),
      },
    );
  }

  QuoteItemSnapshot _legacySnapshot(Money price, DateTime capturedAt) =>
      QuoteItemSnapshot(
        materials: const [],
        primaryMaterials: Money(minorUnits: 0, currency: price.currency),
        thread: Money(minorUnits: 0, currency: price.currency),
        waste: Money(minorUnits: 0, currency: price.currency),
        complementaryMaterials: Money(minorUnits: 0, currency: price.currency),
        totalCost: Money(minorUnits: 0, currency: price.currency),
        threadPercentage: DecimalValue.zero,
        wastePercentage: DecimalValue.zero,
        multiplier: DecimalValue.one,
        wholesalePrice: price,
        retailPercentage: DecimalValue.zero,
        retailPrice: price,
        capturedAt: capturedAt,
      );

  Map<String, Object?>? _decodeMap(String? source) => source == null
      ? null
      : Map<String, Object?>.from(jsonDecode(source) as Map);

  DecimalValue? _decimalOrNull(Object? value) =>
      value == null ? null : DecimalValue.scaled(value as int);

  SyncMetadata _metadataFromRow(Map<String, Object?> row) => SyncMetadata(
    id: row['id']! as String,
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
    deletedAt: switch (row['deleted_at']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
  );

  Map<String, Object?> _metadataToRow(SyncMetadata metadata) => {
    'created_at': metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': metadata.deletedAt?.toUtc().toIso8601String(),
  };
}
