import 'dart:convert';
import 'dart:io';

import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/data/importing/xlsx_workbook_reader.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/importing/import_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/historical_sheet_analyzer.dart';
import 'package:manos_chacabuco/domain/settings/app_settings.dart';
import 'package:uuid/uuid.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Uso: dart run tool/import_dry_run.dart archivo.xlsx');
    exitCode = 64;
    return;
  }

  final analyzedAt = DateTime.utc(2026, 9, 2);
  final bytes = await File(arguments.single).readAsBytes();
  final workbook = const XlsxWorkbookReader().read(bytes);
  var id = 0;
  final preview = const HistoricalSheetAnalyzer().analyze(
    workbook: workbook,
    spreadsheetId: '1xByYNR5_7jVRI4H6yGWOVubsAOn6n15YmghdT-D_mH8',
    sheetName: 'Hoja 1',
    units: _units,
    materialCategories: _materialCategories(analyzedAt),
    productCategories: _productCategories(analyzedAt),
    existingMaterials: const [],
    existingProducts: const [],
    sourceLinks: const <String, ImportSourceLink>{},
    settings: AppSettings.defaults(now: analyzedAt),
    idFactory: () => const Uuid().v5(Namespace.url.value, 'dry-run-${id++}'),
    analyzedAt: analyzedAt,
  );

  final comparable = preview.products.where(
    (item) =>
        item.priceComparison.sheetCost != null &&
        item.priceComparison.appCost != null,
  );
  final absoluteCostDifferenceMinor = comparable.fold<int>(0, (total, item) {
    return total +
        (item.priceComparison.appCost!.minorUnits -
                item.priceComparison.sheetCost!.minorUnits)
            .abs();
  });
  final signedCostDifferenceMinor = comparable.fold<int>(0, (total, item) {
    return total +
        item.priceComparison.appCost!.minorUnits -
        item.priceComparison.sheetCost!.minorUnits;
  });
  final largestDifference = comparable.isEmpty
      ? null
      : comparable.reduce((left, right) {
          final leftDifference =
              (left.priceComparison.appCost!.minorUnits -
                      left.priceComparison.sheetCost!.minorUnits)
                  .abs();
          final rightDifference =
              (right.priceComparison.appCost!.minorUnits -
                      right.priceComparison.sheetCost!.minorUnits)
                  .abs();
          return leftDifference >= rightDifference ? left : right;
        });
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'sheet': preview.sheetName,
      'materialsDetected': preview.materials.length,
      'newMaterialsReady': preview.newMaterialCount,
      'productsDetected': preview.products.length,
      'newProductsReady': preview.newProductCount,
      'primaryRelationships': preview.primaryRelationshipCount,
      'complementaryRelationships': preview.complementaryRelationshipCount,
      'productsWithWeight': preview.productsWithWeight,
      'productsWithMultiplier': preview.productsWithMultiplier,
      'productsWithMeasures': preview.productsWithMeasures,
      'detectedMeasureValues': preview.detectedMeasures,
      'safeGeometryProfiles': preview.safeGeometryCount,
      'calibrationReady': preview.calibrationReadyCount,
      'reviewCases': preview.reviewCount,
      'materialReview': [
        for (final item in preview.materials)
          if (item.confidence != ImportConfidence.safe)
            item.source.originalName,
      ],
      'issues': preview.issues.length,
      'omittedRows': preview.omittedRows,
      'comparableCosts': comparable.length,
      'averageAbsoluteCostDifferenceArs': comparable.isEmpty
          ? null
          : absoluteCostDifferenceMinor / comparable.length / 100,
      'averageSignedCostDifferenceArs': comparable.isEmpty
          ? null
          : signedCostDifferenceMinor / comparable.length / 100,
      'costsWithinArs100': comparable
          .where(
            (item) =>
                (item.priceComparison.appCost!.minorUnits -
                        item.priceComparison.sheetCost!.minorUnits)
                    .abs() <=
                10000,
          )
          .length,
      'largestCostDifference': largestDifference == null
          ? null
          : {
              'product': largestDifference.source.originalName,
              'differenceArs':
                  (largestDifference.priceComparison.appCost!.minorUnits -
                      largestDifference.priceComparison.sheetCost!.minorUnits) /
                  100,
            },
      'issuesByType': {
        for (final kind in ImportIssueKind.values)
          kind.name: preview.issues.where((issue) => issue.kind == kind).length,
      },
    }),
  );
}

const _units = [
  MeasurementUnit(
    id: 'd8a885bb-55c2-4fb3-b430-933781c3f8c0',
    code: 'gram',
    name: 'Gramos',
    symbol: 'g',
    dimension: MeasurementDimension.weight,
    baseUnitFactor: DecimalValue.scaled(1000000),
  ),
  MeasurementUnit(
    id: 'b59af36e-bb0c-4533-a4a8-48ec2cead406',
    code: 'centimeter',
    name: 'Centímetros',
    symbol: 'cm',
    dimension: MeasurementDimension.length,
    baseUnitFactor: DecimalValue.scaled(10000),
  ),
  MeasurementUnit(
    id: '44df27a1-a71f-447c-b6ee-02e75b6d6238',
    code: 'square_centimeter',
    name: 'Centímetros cuadrados',
    symbol: 'cm²',
    dimension: MeasurementDimension.area,
    baseUnitFactor: DecimalValue.scaled(100),
  ),
  MeasurementUnit(
    id: '2bf70ea7-4bb8-4249-b009-f57f55aa1a85',
    code: 'item',
    name: 'Unidades',
    symbol: 'u',
    dimension: MeasurementDimension.count,
    baseUnitFactor: DecimalValue.scaled(1000000),
  ),
];

List<MaterialCategory> _materialCategories(DateTime now) {
  const values = [
    ('16a028b4-23e3-46f4-9aa0-956cfa5f1392', 'Cordones'),
    ('1e7a99d0-0fea-411f-a4e6-15f26c53e45e', 'Cueros y cuerinas'),
    ('490386f4-1afe-4b6c-9876-19dd33a72aa9', 'Cierres'),
    ('502cbd3c-4aa5-4f82-b811-a95f97485d3b', 'Mosquetones'),
    ('0608546f-b7a4-46bf-b027-33a7997944cf', 'Herrajes y avíos'),
    ('b4f04da4-ae96-44f8-884a-d129983fd086', 'Cintas'),
    ('fd65e750-06ae-4f4d-8c6a-b0e6104649df', 'Hilos'),
    ('d00325ab-e7cc-4c2c-a153-4605ba0dcc54', 'Otros'),
  ];
  return [
    for (final value in values)
      MaterialCategory(
        metadata: SyncMetadata(id: value.$1, createdAt: now, updatedAt: now),
        name: value.$2,
      ),
  ];
}

List<ProductCategory> _productCategories(DateTime now) {
  const values = [
    ('a27c29b7-5d11-4cae-9c26-57fc7a441001', 'Deco'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441002', 'Cestos'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441003', 'Maceteros'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441004', 'Bandejas'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441005', 'Cajas y contenedores'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441006', 'Bolsos y accesorios'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441007', 'Cocina y mesa'),
    ('a27c29b7-5d11-4cae-9c26-57fc7a441008', 'Otros'),
  ];
  return [
    for (final value in values)
      ProductCategory(
        metadata: SyncMetadata(id: value.$1, createdAt: now, updatedAt: now),
        name: value.$2,
      ),
  ];
}
