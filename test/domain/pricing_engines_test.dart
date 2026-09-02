import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/core/money/precise_unit_cost.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/cost_engine.dart';
import 'package:manos_chacabuco/domain/services/pricing_engine.dart';

void main() {
  test('suma consumo real de cada variante y no promedia precios', () {
    const engine = CostEngine();
    final result = engine.calculate(
      lines: [
        MaterialCostLine(
          materialId: 'cordon',
          variantId: 'negro',
          consumedBaseUnits: DecimalValue.parse('100'),
          costPerBaseUnit: const PreciseUnitCost(
            scaledMinorUnits: 10000000,
            currency: 'ARS',
          ),
          role: ProductMaterialRole.primary,
          currency: 'ARS',
        ),
        MaterialCostLine(
          materialId: 'cordon',
          variantId: 'natural',
          consumedBaseUnits: DecimalValue.parse('200'),
          costPerBaseUnit: const PreciseUnitCost(
            scaledMinorUnits: 5000000,
            currency: 'ARS',
          ),
          role: ProductMaterialRole.primary,
          currency: 'ARS',
        ),
      ],
      threadPercentage: DecimalValue.percent('6'),
      wastePercentage: DecimalValue.percent('1.5'),
    );

    expect(result.materials, const Money.ars(2000));
    expect(result.thread, const Money.ars(120));
    expect(result.waste, const Money.ars(30));
    expect(result.total, const Money.ars(2150));
  });

  test('calcula mayorista y minorista desde reglas explícitas', () {
    const engine = PricingEngine();
    final result = engine.calculate(
      totalCost: const Money.ars(1245000),
      priceMultiplier: DecimalValue.parse('2.4'),
      retailPercentage: DecimalValue.percent('20'),
    );

    expect(result.wholesale, const Money.ars(2988000));
    expect(result.retail, const Money.ars(3585600));
  });

  test('no inventa minorista cuando el porcentaje no está definido', () {
    const engine = PricingEngine();
    final result = engine.calculate(
      totalCost: const Money.ars(10000),
      priceMultiplier: DecimalValue.parse('2'),
    );

    expect(result.wholesale, const Money.ars(20000));
    expect(result.retail, isNull);
  });
}
