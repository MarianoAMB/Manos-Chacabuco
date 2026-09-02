// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../domain/common/sync_metadata.dart';
import '../../domain/importing/import_models.dart';
import '../../domain/materials/material_models.dart';
import '../../domain/products/product_models.dart';

final class SqliteHistoricalImportRepository
    implements HistoricalImportRepository {
  SqliteHistoricalImportRepository(
    this._appDatabase, {
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
    this.beforeCommitForTesting,
  }) : _uuid = uuid,
       _now = now ?? DateTime.now;

  final AppDatabase _appDatabase;
  final Uuid _uuid;
  final DateTime Function() _now;
  final Future<void> Function()? beforeCommitForTesting;

  @override
  Future<Map<String, ImportSourceLink>> findSourceLinks(
    String spreadsheetId,
  ) async {
    final rows = await _appDatabase.database.query(
      'import_records',
      where: 'spreadsheet_id = ?',
      whereArgs: [spreadsheetId],
    );
    return {
      for (final row in rows)
        row['source_key']! as String: ImportSourceLink(
          sourceKey: row['source_key']! as String,
          targetId: row['target_id']! as String,
        ),
    };
  }

  @override
  Future<String> createBackup() async {
    final timestamp = _now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final databasePath = _appDatabase.database.path;
    final directory = databasePath == ':memory:'
        ? Directory.systemTemp.path
        : paths.dirname(databasePath);
    final backupPath = paths.join(
      directory,
      'backup_before_sheet_import_$timestamp.db',
    );
    await Directory(directory).create(recursive: true);
    await _appDatabase.database.execute('VACUUM INTO ?', [backupPath]);
    return backupPath;
  }

  @override
  Future<ImportReport> importPreview(
    ImportPreview preview, {
    required String backupPath,
  }) async {
    final now = _now().toUtc();
    var importedMaterials = 0;
    var importedProducts = 0;
    var linkedExisting = 0;
    var skipped = 0;
    await _appDatabase.database.transaction((transaction) async {
      for (final candidate in preview.materials) {
        switch (candidate.decision) {
          case ImportDecision.create:
            await transaction.insert(
              'materials',
              _materialToRow(candidate.material),
            );
            importedMaterials++;
            await _link(transaction, candidate.source, candidate.targetId, now);
          case ImportDecision.useExisting:
            linkedExisting++;
            await _link(transaction, candidate.source, candidate.targetId, now);
          case ImportDecision.alreadyImported:
            skipped++;
            await _touch(transaction, candidate.source, now);
          case ImportDecision.review:
          case ImportDecision.skip:
            skipped++;
        }
      }
      if (beforeCommitForTesting != null) await beforeCommitForTesting!();
      for (final candidate in preview.products) {
        final targetId = candidate.targetId;
        switch (candidate.decision) {
          case ImportDecision.create:
            final product = candidate.product;
            if (product == null || targetId == null) {
              skipped++;
              continue;
            }
            await transaction.insert('products', _productToRow(product));
            for (final usage in candidate.usages) {
              await transaction.insert(
                'product_material_usages',
                _usageToRow(usage),
              );
            }
            importedProducts++;
            await _link(transaction, candidate.source, targetId, now);
          case ImportDecision.useExisting:
            if (targetId == null) {
              skipped++;
              continue;
            }
            linkedExisting++;
            await _link(transaction, candidate.source, targetId, now);
          case ImportDecision.alreadyImported:
            skipped++;
            await _touch(transaction, candidate.source, now);
          case ImportDecision.review:
          case ImportDecision.skip:
            skipped++;
        }
      }
      final report = ImportReport(
        id: _uuid.v4(),
        finishedAt: now,
        importedMaterials: importedMaterials,
        importedProducts: importedProducts,
        linkedExisting: linkedExisting,
        skipped: skipped,
        warnings: preview.issues.length,
        requiresReview: preview.reviewCount,
        calibrationReady: preview.products
            .where(
              (item) =>
                  item.calibrationReady &&
                  item.decision == ImportDecision.create,
            )
            .length,
        backupPath: backupPath,
      );
      await transaction.insert('import_reports', {
        'id': report.id,
        'spreadsheet_id': preview.spreadsheetId,
        'sheet_name': preview.sheetName,
        'finished_at': now.toIso8601String(),
        'imported_materials': importedMaterials,
        'imported_products': importedProducts,
        'linked_existing': linkedExisting,
        'skipped': skipped,
        'warnings': report.warnings,
        'requires_review': report.requiresReview,
        'calibration_ready': report.calibrationReady,
        'backup_path': backupPath,
        'payload_json': jsonEncode({
          'omittedRows': preview.omittedRows,
          'issues': [
            for (final issue in preview.issues)
              {
                'row': issue.source.row,
                'section': issue.source.section,
                'kind': issue.kind.name,
                'message': issue.message,
                'details': issue.details,
              },
          ],
          'comparisons': [
            for (final item in preview.products)
              {
                'row': item.source.row,
                'name': item.source.originalName,
                'sheetCost': item.priceComparison.sheetCost?.minorUnits,
                'appCost': item.priceComparison.appCost?.minorUnits,
                'sheetWholesale':
                    item.priceComparison.sheetWholesale?.minorUnits,
                'appWholesale': item.priceComparison.appWholesale?.minorUnits,
                'sheetRetail': item.priceComparison.sheetRetail?.minorUnits,
                'appRetail': item.priceComparison.appRetail?.minorUnits,
              },
          ],
        }),
      });
    });
    return ImportReport(
      id:
          (await _appDatabase.database.query(
                'import_reports',
                columns: const ['id'],
                orderBy: 'finished_at DESC',
                limit: 1,
              )).single['id']!
              as String,
      finishedAt: now,
      importedMaterials: importedMaterials,
      importedProducts: importedProducts,
      linkedExisting: linkedExisting,
      skipped: skipped,
      warnings: preview.issues.length,
      requiresReview: preview.reviewCount,
      calibrationReady: preview.products
          .where(
            (item) =>
                item.calibrationReady && item.decision == ImportDecision.create,
          )
          .length,
      backupPath: backupPath,
    );
  }

  @override
  Future<ImportReport?> latestReport() async {
    final rows = await _appDatabase.database.query(
      'import_reports',
      orderBy: 'finished_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ImportReport(
      id: row['id']! as String,
      finishedAt: DateTime.parse(row['finished_at']! as String),
      importedMaterials: row['imported_materials']! as int,
      importedProducts: row['imported_products']! as int,
      linkedExisting: row['linked_existing']! as int,
      skipped: row['skipped']! as int,
      warnings: row['warnings']! as int,
      requiresReview: row['requires_review']! as int,
      calibrationReady: row['calibration_ready']! as int,
      backupPath: row['backup_path']! as String,
    );
  }

  Future<void> _link(
    DatabaseExecutor transaction,
    ImportSourceMetadata source,
    String targetId,
    DateTime now,
  ) async {
    await transaction.insert('import_records', {
      'id': _uuid.v4(),
      'source_key': source.stableKey,
      'spreadsheet_id': source.spreadsheetId,
      'sheet_name': source.sheetName,
      'source_row': source.row,
      'section': source.section,
      'record_type': source.recordType.name,
      'target_id': targetId,
      'original_name': source.originalName,
      'imported_at': now.toIso8601String(),
      'last_seen_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _touch(
    DatabaseExecutor transaction,
    ImportSourceMetadata source,
    DateTime now,
  ) => transaction.update(
    'import_records',
    {'last_seen_at': now.toIso8601String()},
    where: 'source_key = ?',
    whereArgs: [source.stableKey],
  );

  Map<String, Object?> _materialToRow(Material material) => {
    'id': material.metadata.id,
    'category_id': material.categoryId,
    'name': material.name,
    'description': material.description,
    'purchase_quantity_scaled': material.purchase.quantity.amount.scaledValue,
    'purchase_unit_id': material.purchase.quantity.unitId,
    'purchase_price_minor': material.purchase.price.minorUnits,
    'currency': material.purchase.price.currency,
    'consumption_unit_id': material.consumptionUnitId,
    'brand_or_supplier': material.brandOrSupplier,
    'notes': material.notes,
    'is_active': material.isActive ? 1 : 0,
    ..._metadataToRow(material.metadata),
  };

  Map<String, Object?> _productToRow(Product product) => {
    'id': product.metadata.id,
    'category_id': product.categoryId,
    'name': product.name,
    'description': product.description,
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
    'notes': product.notes,
    'is_active': product.isActive ? 1 : 0,
    ..._metadataToRow(product.metadata),
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
    'notes': usage.notes,
    ..._metadataToRow(usage.metadata),
  };

  Map<String, Object?> _metadataToRow(SyncMetadata metadata) => {
    'created_at': metadata.createdAt.toUtc().toIso8601String(),
    'updated_at': metadata.updatedAt.toUtc().toIso8601String(),
    'deleted_at': metadata.deletedAt?.toUtc().toIso8601String(),
  };
}
