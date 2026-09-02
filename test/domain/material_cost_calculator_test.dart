import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/formatting/argentine_number_formatter.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/services/material_cost_calculator.dart';

void main() {
  const calculator = MaterialCostCalculator();
  const gram = MeasurementUnit(
    id: 'g',
    code: 'gram',
    name: 'Gramos',
    symbol: 'g',
    dimension: MeasurementDimension.weight,
    baseUnitFactor: DecimalValue.one,
  );
  const kilogram = MeasurementUnit(
    id: 'kg',
    code: 'kilogram',
    name: 'Kilogramos',
    symbol: 'kg',
    dimension: MeasurementDimension.weight,
    baseUnitFactor: DecimalValue.scaled(1000000000),
  );
  const meter = MeasurementUnit(
    id: 'm',
    code: 'meter',
    name: 'Metros',
    symbol: 'm',
    dimension: MeasurementDimension.length,
    baseUnitFactor: DecimalValue.one,
  );
  const item = MeasurementUnit(
    id: 'u',
    code: 'item',
    name: 'Unidades',
    symbol: 'u',
    dimension: MeasurementDimension.count,
    baseUnitFactor: DecimalValue.one,
  );
  const squareMeter = MeasurementUnit(
    id: 'm2',
    code: 'square_meter',
    name: 'Metros cuadrados',
    symbol: 'm²',
    dimension: MeasurementDimension.area,
    baseUnitFactor: DecimalValue.one,
  );
  const squareCentimeter = MeasurementUnit(
    id: 'cm2',
    code: 'square_centimeter',
    name: 'Centímetros cuadrados',
    symbol: 'cm²',
    dimension: MeasurementDimension.area,
    baseUnitFactor: DecimalValue.scaled(100),
  );

  test('calcula 35.000 pesos por 2.100 gramos', () {
    final cost = calculator.calculate(
      _purchase(priceMinor: 3500000, amount: '2100', unitId: gram.id),
      gram,
    );

    expect(ArgentineNumberFormatter.unitCost(cost, gram), r'$16,67 / g');
  });

  test('2,1 kg equivale a 2.100 g', () {
    final byKilogram = calculator.calculate(
      _purchase(priceMinor: 3500000, amount: '2.1', unitId: kilogram.id),
      kilogram,
    );
    final byGram = calculator.calculate(
      _purchase(priceMinor: 3500000, amount: '2100', unitId: gram.id),
      gram,
    );

    expect(byKilogram, byGram);
  });

  test('calcula costos por metro y por unidad', () {
    final perMeter = calculator.calculate(
      _purchase(priceMinor: 1000000, amount: '20', unitId: meter.id),
      meter,
    );
    final perItem = calculator.calculate(
      _purchase(priceMinor: 500000, amount: '10', unitId: item.id),
      item,
    );

    expect(ArgentineNumberFormatter.unitCost(perMeter, meter), r'$500 / m');
    expect(ArgentineNumberFormatter.unitCost(perItem, item), r'$500 / u');
  });

  test('calcula superficie y convierte de m² a cm²', () {
    final cost = calculator.calculate(
      _purchase(priceMinor: 500000, amount: '0.5', unitId: squareMeter.id),
      squareMeter,
    );

    expect(
      ArgentineNumberFormatter.unitCost(cost, squareMeter),
      r'$10.000 / m²',
    );
    expect(
      ArgentineNumberFormatter.unitCost(cost, squareCentimeter),
      r'$1 / cm²',
    );
  });

  test('dos variantes con distinto precio conservan costos diferentes', () {
    final economical = calculator.calculate(
      _purchase(priceMinor: 1000000, amount: '20', unitId: meter.id),
      meter,
    );
    final premium = calculator.calculate(
      _purchase(priceMinor: 1400000, amount: '20', unitId: meter.id),
      meter,
    );

    expect(economical.scaledMinorUnits, isNot(premium.scaledMinorUnits));
    expect(ArgentineNumberFormatter.unitCost(premium, meter), r'$700 / m');
  });
}

PurchasePresentation _purchase({
  required int priceMinor,
  required String amount,
  required String unitId,
}) => PurchasePresentation(
  quantity: MeasuredQuantity(
    amount: DecimalValue.parse(amount),
    unitId: unitId,
  ),
  price: Money.ars(priceMinor),
);
