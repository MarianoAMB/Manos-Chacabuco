import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/material_estimation_engine.dart';

void main() {
  const engine = MaterialEstimationEngine();

  test('una referencia escala 400 a 600 cuando el área crece 1,5 veces', () {
    final estimate = engine.estimate(
      materialId: 'pp',
      compatibilityKey: 'cylinder|base,lateral|none',
      targetArea: 3000,
      references: const [
        MaterialCalibrationReference(
          productId: 'p1',
          productName: 'Cesto 20×20',
          materialId: 'pp',
          compatibilityKey: 'cylinder|base,lateral|none',
          effectiveArea: 2000,
          consumptionBaseUnits: 400,
          consumptionSource: ConsumptionSource.confirmed,
        ),
      ],
    );

    expect(estimate.estimatedBaseUnits, closeTo(600, 0.000001));
    expect(estimate.minimumBaseUnits, isNull);
    expect(estimate.references, hasLength(1));
    expect(estimate.confidence, EstimationConfidence.limited);
  });

  test('escala receta multimaterial 200 y 150 por un ratio de 1,5', () {
    final scaled = engine.scaleFromProduct(
      referenceArea: 2000,
      targetArea: 3000,
      usages: [
        _usage('cotton', 'natural', '200'),
        _usage('pp', 'natural', '150'),
        _usage('zip', null, '1', role: ProductMaterialRole.complementary),
      ],
    );

    expect(scaled.ratio, 1.5);
    expect(scaled.usages[0].consumption.amount, DecimalValue.parse('300'));
    expect(scaled.usages[1].consumption.amount, DecimalValue.parse('225'));
    expect(scaled.usages[2].consumption.amount, DecimalValue.parse('1'));
    expect(scaled.usages[0].consumptionSource, ConsumptionSource.estimated);
  });

  test('variantes del mismo material conservan su distribución física', () {
    final scaled = engine.scaleFromProduct(
      referenceArea: 2000,
      targetArea: 3000,
      usages: [_usage('pp', 'natural', '100'), _usage('pp', 'black', '300')],
    );

    expect(scaled.usages[0].consumption.amount, DecimalValue.parse('150'));
    expect(scaled.usages[1].consumption.amount, DecimalValue.parse('450'));
  });

  test('múltiples referencias generan rango y devuelven las utilizadas', () {
    final estimate = engine.estimate(
      materialId: 'pp',
      compatibilityKey: 'same',
      targetArea: 3000,
      references: const [
        MaterialCalibrationReference(
          productId: 'a',
          productName: 'A',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 2000,
          consumptionBaseUnits: 480,
          consumptionSource: ConsumptionSource.confirmed,
        ),
        MaterialCalibrationReference(
          productId: 'b',
          productName: 'B',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 2000,
          consumptionBaseUnits: 500,
          consumptionSource: ConsumptionSource.manual,
        ),
        MaterialCalibrationReference(
          productId: 'c',
          productName: 'C',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 2000,
          consumptionBaseUnits: 520,
          consumptionSource: ConsumptionSource.confirmed,
        ),
      ],
    );

    expect(estimate.references, hasLength(3));
    expect(estimate.minimumBaseUnits, 720);
    expect(estimate.maximumBaseUnits, 780);
    expect(estimate.estimatedBaseUnits, anyOf(720, 750, 780));
    expect(estimate.confidence, EstimationConfidence.good);
  });

  test('un outlier extremo no domina la estimación robusta', () {
    final estimate = engine.estimate(
      materialId: 'pp',
      compatibilityKey: 'same',
      targetArea: 1000,
      references: const [
        MaterialCalibrationReference(
          productId: 'a',
          productName: 'A',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 1000,
          consumptionBaseUnits: 500,
          consumptionSource: ConsumptionSource.confirmed,
        ),
        MaterialCalibrationReference(
          productId: 'b',
          productName: 'B',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 1000,
          consumptionBaseUnits: 520,
          consumptionSource: ConsumptionSource.confirmed,
        ),
        MaterialCalibrationReference(
          productId: 'outlier',
          productName: 'Extremo',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 1000,
          consumptionBaseUnits: 5000,
          consumptionSource: ConsumptionSource.confirmed,
        ),
      ],
    );

    expect(
      estimate.references.map((item) => item.reference.productId),
      isNot(contains('outlier')),
    );
    expect(estimate.estimatedBaseUnits, lessThan(1000));
  });

  test('sin referencias no inventa consumo', () {
    final estimate = engine.estimate(
      materialId: 'pp',
      compatibilityKey: 'same',
      targetArea: 1000,
      references: const [],
    );

    expect(estimate.hasEstimate, isFalse);
    expect(estimate.confidence, EstimationConfidence.insufficient);
  });

  test('confirmado tiene prioridad y estimado no crea feedback loop', () {
    final estimate = engine.estimate(
      materialId: 'pp',
      compatibilityKey: 'same',
      targetArea: 1000,
      references: const [
        MaterialCalibrationReference(
          productId: 'confirmed',
          productName: 'Real',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 1000,
          consumptionBaseUnits: 500,
          consumptionSource: ConsumptionSource.confirmed,
        ),
        MaterialCalibrationReference(
          productId: 'estimated',
          productName: 'Estimado previo',
          materialId: 'pp',
          compatibilityKey: 'same',
          effectiveArea: 1000,
          consumptionBaseUnits: 5000,
          consumptionSource: ConsumptionSource.estimated,
        ),
      ],
    );

    expect(estimate.references, hasLength(1));
    expect(estimate.references.single.reference.productId, 'confirmed');
    expect(estimate.estimatedBaseUnits, 500);
  });
}

ProductMaterialUsage _usage(
  String materialId,
  String? variantId,
  String amount, {
  ProductMaterialRole role = ProductMaterialRole.primary,
}) {
  final now = DateTime.utc(2026, 9, 2);
  return ProductMaterialUsage(
    metadata: SyncMetadata(
      id: '$materialId-$variantId-$amount',
      createdAt: now,
      updatedAt: now,
    ),
    productId: 'product',
    materialId: materialId,
    materialVariantId: variantId,
    consumption: MeasuredQuantity(
      amount: DecimalValue.parse(amount),
      unitId: 'gram',
    ),
    role: role,
    consumptionSource: ConsumptionSource.confirmed,
  );
}
