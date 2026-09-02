import 'decimal_value.dart';
import 'money.dart';

/// Costo por unidad base con seis decimales de precisión de centavo.
///
/// `Money` continúa representando importes finales. Esta tasa evita perder
/// precisión al dividir una compra entre miles de gramos o centímetros.
final class PreciseUnitCost {
  const PreciseUnitCost({
    required this.scaledMinorUnits,
    required this.currency,
  });

  final int scaledMinorUnits;
  final String currency;

  Money costFor(DecimalValue baseQuantity) => Money(
    minorUnits: divideAndRound(
      scaledMinorUnits * baseQuantity.scaledValue,
      DecimalValue.scale * DecimalValue.scale,
    ),
    currency: currency,
  );

  int scaledMinorUnitsFor(DecimalValue unitFactor) => divideAndRound(
    scaledMinorUnits * unitFactor.scaledValue,
    DecimalValue.scale,
  );

  @override
  bool operator ==(Object other) =>
      other is PreciseUnitCost &&
      other.scaledMinorUnits == scaledMinorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(scaledMinorUnits, currency);
}
