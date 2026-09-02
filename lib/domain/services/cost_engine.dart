import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../../core/money/precise_unit_cost.dart';
import '../materials/material_models.dart';
import '../products/product_models.dart';
import 'material_cost_calculator.dart';

/// Una línea representa el consumo real de una variante concreta.
final class MaterialCostLine {
  const MaterialCostLine({
    required this.materialId,
    required this.consumedBaseUnits,
    required this.costPerBaseUnit,
    required this.role,
    required this.currency,
    this.variantId,
  });

  final String materialId;
  final String? variantId;
  final DecimalValue consumedBaseUnits;
  final PreciseUnitCost costPerBaseUnit;
  final ProductMaterialRole role;
  final String currency;

  Money get cost => costPerBaseUnit.costFor(consumedBaseUnits);
}

final class ResolvedMaterialCostLine {
  const ResolvedMaterialCostLine({required this.usageId, required this.line});

  final String usageId;
  final MaterialCostLine line;

  Money get cost => line.cost;
}

final class CostBreakdown {
  const CostBreakdown({
    required this.primaryMaterials,
    required this.thread,
    required this.waste,
    required this.complementaryMaterials,
    required this.totalCost,
  });

  final Money primaryMaterials;
  final Money thread;
  final Money waste;
  final Money complementaryMaterials;
  final Money totalCost;

  Money get materials => primaryMaterials + complementaryMaterials;
  Money get total => totalCost;
}

final class CostEngine {
  const CostEngine({
    this.materialCalculator = const MaterialCostCalculator(),
    this.converter = const UnitConverter(),
  });

  final MaterialCostCalculator materialCalculator;
  final UnitConverter converter;

  ResolvedMaterialCostLine resolveLine({
    required ProductMaterialUsage usage,
    required Material material,
    required MaterialVariant? variant,
    required MeasurementUnit usageUnit,
    required MeasurementUnit purchaseUnit,
    required MeasurementUnit materialConsumptionUnit,
  }) {
    if (usage.materialId != material.metadata.id) {
      throw ArgumentError('La materia prima no corresponde al consumo');
    }
    if (variant != null && variant.materialId != material.metadata.id) {
      throw ArgumentError('La variante no pertenece a la materia prima');
    }
    if (usageUnit.dimension != materialConsumptionUnit.dimension) {
      throw ArgumentError('La unidad elegida no es compatible con el material');
    }
    final purchase = variant?.purchaseOverride ?? material.purchase;
    final normalized = converter.toBase(usage.consumption, usageUnit);
    return ResolvedMaterialCostLine(
      usageId: usage.metadata.id,
      line: MaterialCostLine(
        materialId: material.metadata.id,
        variantId: variant?.metadata.id,
        consumedBaseUnits: normalized,
        costPerBaseUnit: materialCalculator.calculate(purchase, purchaseUnit),
        role: usage.role,
        currency: purchase.price.currency,
      ),
    );
  }

  CostBreakdown calculate({
    required Iterable<MaterialCostLine> lines,
    required DecimalValue threadPercentage,
    required DecimalValue wastePercentage,
    String currency = 'ARS',
  }) {
    var primary = Money(minorUnits: 0, currency: currency);
    var complementary = Money(minorUnits: 0, currency: currency);
    for (final line in lines) {
      if (line.role == ProductMaterialRole.primary) {
        primary = primary + line.cost;
      } else {
        complementary = complementary + line.cost;
      }
    }

    final thread = primary.multiply(threadPercentage);
    final waste = primary.multiply(wastePercentage);
    return CostBreakdown(
      primaryMaterials: primary,
      thread: thread,
      waste: waste,
      complementaryMaterials: complementary,
      totalCost: primary + thread + waste + complementary,
    );
  }
}
