import '../../core/money/decimal_value.dart';
import '../../core/money/precise_unit_cost.dart';
import '../materials/material_models.dart';

final class UnitConverter {
  const UnitConverter();

  DecimalValue toBase(MeasuredQuantity quantity, MeasurementUnit unit) {
    if (quantity.unitId != unit.id) {
      throw ArgumentError('La unidad no corresponde a la cantidad');
    }
    return DecimalValue.scaled(
      divideAndRound(
        quantity.amount.scaledValue * unit.baseUnitFactor.scaledValue,
        DecimalValue.scale,
      ),
    );
  }
}

final class MaterialCostCalculator {
  const MaterialCostCalculator({this.converter = const UnitConverter()});

  final UnitConverter converter;

  PreciseUnitCost calculate(
    PurchasePresentation purchase,
    MeasurementUnit purchaseUnit,
  ) {
    final normalizedQuantity = converter.toBase(
      purchase.quantity,
      purchaseUnit,
    );
    if (normalizedQuantity.scaledValue <= 0) {
      throw ArgumentError('La cantidad comprada debe ser mayor que cero');
    }
    if (purchase.price.minorUnits < 0) {
      throw ArgumentError('El precio no puede ser negativo');
    }

    return PreciseUnitCost(
      scaledMinorUnits: divideAndRound(
        purchase.price.minorUnits * DecimalValue.scale * DecimalValue.scale,
        normalizedQuantity.scaledValue,
      ),
      currency: purchase.price.currency,
    );
  }
}
