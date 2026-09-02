import 'dart:math' as math;

import '../../core/money/decimal_value.dart';
import '../products/product_models.dart';

enum EstimationConfidence { good, limited, insufficient }

extension EstimationConfidenceLabel on EstimationConfidence {
  String get label => switch (this) {
    EstimationConfidence.good => 'Buena referencia',
    EstimationConfidence.limited => 'Referencia limitada',
    EstimationConfidence.insufficient => 'Sin referencias suficientes',
  };
}

final class MaterialCalibrationReference {
  const MaterialCalibrationReference({
    required this.productId,
    required this.productName,
    required this.materialId,
    required this.compatibilityKey,
    required this.effectiveArea,
    required this.consumptionBaseUnits,
    required this.consumptionSource,
  });

  final String productId;
  final String productName;
  final String materialId;
  final String compatibilityKey;
  final double effectiveArea;
  final double consumptionBaseUnits;
  final ConsumptionSource consumptionSource;
}

final class MaterialReferencePrediction {
  const MaterialReferencePrediction({
    required this.reference,
    required this.predictedBaseUnits,
  });

  final MaterialCalibrationReference reference;
  final double predictedBaseUnits;
}

final class MaterialEstimate {
  const MaterialEstimate({
    required this.materialId,
    required this.confidence,
    required this.references,
    this.estimatedBaseUnits,
    this.minimumBaseUnits,
    this.maximumBaseUnits,
  });

  final String materialId;
  final double? estimatedBaseUnits;
  final double? minimumBaseUnits;
  final double? maximumBaseUnits;
  final EstimationConfidence confidence;
  final List<MaterialReferencePrediction> references;

  bool get hasEstimate => estimatedBaseUnits != null;
}

final class ProductScaleEstimate {
  const ProductScaleEstimate({required this.ratio, required this.usages});

  final double ratio;
  final List<ProductMaterialUsage> usages;
}

/// Calibra consumo con datos del negocio. La mediana y el descarte por MAD
/// evitan que una referencia extrema domine el resultado; la similitud de área
/// y la fuente del dato sólo definen el peso dentro del conjunto robusto.
final class MaterialEstimationEngine {
  const MaterialEstimationEngine();

  ProductScaleEstimate scaleFromProduct({
    required double referenceArea,
    required double targetArea,
    required List<ProductMaterialUsage> usages,
  }) {
    if (referenceArea <= 0 || targetArea <= 0) {
      throw ArgumentError('Las superficies deben ser mayores que cero.');
    }
    final ratio = targetArea / referenceArea;
    return ProductScaleEstimate(
      ratio: ratio,
      usages: [
        for (final usage in usages)
          ProductMaterialUsage(
            metadata: usage.metadata,
            productId: usage.productId,
            materialId: usage.materialId,
            materialVariantId: usage.materialVariantId,
            consumption: usage.role == ProductMaterialRole.primary
                ? usage.consumption.copyWith(
                    amount: DecimalValue.scaled(
                      (usage.consumption.amount.scaledValue * ratio).round(),
                    ),
                  )
                : usage.consumption,
            role: usage.role,
            consumptionSource: usage.role == ProductMaterialRole.primary
                ? ConsumptionSource.estimated
                : usage.consumptionSource,
            calibrationEligible: usage.calibrationEligible,
            notes: usage.notes,
          ),
      ],
    );
  }

  MaterialEstimate estimate({
    required String materialId,
    required String compatibilityKey,
    required double targetArea,
    required Iterable<MaterialCalibrationReference> references,
  }) {
    if (targetArea <= 0) {
      throw ArgumentError('La superficie objetivo debe ser mayor que cero.');
    }
    var candidates = references
        .where(
          (reference) =>
              reference.materialId == materialId &&
              reference.compatibilityKey == compatibilityKey &&
              reference.effectiveArea > 0 &&
              reference.consumptionBaseUnits > 0,
        )
        .toList(growable: false);
    if (candidates.any(
      (reference) => reference.consumptionSource != ConsumptionSource.estimated,
    )) {
      candidates = candidates
          .where(
            (reference) =>
                reference.consumptionSource != ConsumptionSource.estimated,
          )
          .toList(growable: false);
    }
    if (candidates.isEmpty) {
      return MaterialEstimate(
        materialId: materialId,
        confidence: EstimationConfidence.insufficient,
        references: const [],
      );
    }
    final predictions = [
      for (final reference in candidates)
        MaterialReferencePrediction(
          reference: reference,
          predictedBaseUnits:
              reference.consumptionBaseUnits *
              targetArea /
              reference.effectiveArea,
        ),
    ];
    final robust = _removeOutliers(predictions);
    final central = _weightedMedian(robust, targetArea);
    final sorted = robust.map((item) => item.predictedBaseUnits).toList()
      ..sort();
    final rangeAvailable = sorted.length >= 2 && sorted.first != sorted.last;
    final relativeSpread = rangeAvailable
        ? (sorted.last - sorted.first) / central
        : 0.0;
    final confidence = robust.length >= 3 && relativeSpread <= 0.25
        ? EstimationConfidence.good
        : EstimationConfidence.limited;
    return MaterialEstimate(
      materialId: materialId,
      estimatedBaseUnits: central,
      minimumBaseUnits: rangeAvailable ? sorted.first : null,
      maximumBaseUnits: rangeAvailable ? sorted.last : null,
      confidence: confidence,
      references: robust,
    );
  }

  List<MaterialReferencePrediction> _removeOutliers(
    List<MaterialReferencePrediction> values,
  ) {
    if (values.length < 3) return values;
    final median = _median(values.map((item) => item.predictedBaseUnits));
    final deviations = values
        .map((item) => (item.predictedBaseUnits - median).abs())
        .toList();
    final mad = _median(deviations);
    if (mad == 0) {
      final equalToMedian = values
          .where((item) => (item.predictedBaseUnits - median).abs() < 0.000001)
          .toList(growable: false);
      return equalToMedian.isEmpty ? values : equalToMedian;
    }
    final retained = values
        .where((item) => (item.predictedBaseUnits - median).abs() <= 3 * mad)
        .toList(growable: false);
    return retained.isEmpty ? values : retained;
  }

  double _weightedMedian(
    List<MaterialReferencePrediction> values,
    double targetArea,
  ) {
    final sorted = [...values]
      ..sort(
        (left, right) =>
            left.predictedBaseUnits.compareTo(right.predictedBaseUnits),
      );
    double weight(MaterialReferencePrediction value) {
      final sourceWeight = switch (value.reference.consumptionSource) {
        ConsumptionSource.confirmed => 4.0,
        ConsumptionSource.manual => 2.0,
        ConsumptionSource.estimated => 1.0,
      };
      final areaRatio = math.min(
        targetArea / value.reference.effectiveArea,
        value.reference.effectiveArea / targetArea,
      );
      return sourceWeight * areaRatio;
    }

    final total = sorted.fold<double>(0, (sum, item) => sum + weight(item));
    var accumulated = 0.0;
    for (final value in sorted) {
      accumulated += weight(value);
      if (accumulated >= total / 2) return value.predictedBaseUnits;
    }
    return sorted.last.predictedBaseUnits;
  }

  double _median(Iterable<double> values) {
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
