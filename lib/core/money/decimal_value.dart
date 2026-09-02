/// Decimal de seis posiciones almacenado como entero.
///
/// Se usa para porcentajes, multiplicadores y cantidades sin introducir
/// errores binarios de punto flotante en las reglas de negocio.
final class DecimalValue implements Comparable<DecimalValue> {
  const DecimalValue.scaled(this.scaledValue);

  static const int scale = 1000000;
  static const zero = DecimalValue.scaled(0);
  static const one = DecimalValue.scaled(scale);

  final int scaledValue;

  factory DecimalValue.parse(String source) {
    final normalized = source.trim().replaceAll(',', '.');
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(normalized);
    if (match == null) {
      throw FormatException('Decimal inválido', source);
    }

    final sign = match.group(1) == '-' ? -1 : 1;
    final whole = int.parse(match.group(2)!);
    final fractionText = match.group(3) ?? '';
    if (fractionText.length > 6) {
      throw FormatException('Se admiten hasta 6 decimales', source);
    }
    final paddedFraction = fractionText.padRight(6, '0');
    final fraction = paddedFraction.isEmpty ? 0 : int.parse(paddedFraction);
    return DecimalValue.scaled(sign * ((whole * scale) + fraction));
  }

  factory DecimalValue.percent(String percent) {
    final value = DecimalValue.parse(percent);
    return DecimalValue.scaled(_divideRounded(value.scaledValue, 100));
  }

  DecimalValue operator +(DecimalValue other) =>
      DecimalValue.scaled(scaledValue + other.scaledValue);

  DecimalValue operator -(DecimalValue other) =>
      DecimalValue.scaled(scaledValue - other.scaledValue);

  @override
  int compareTo(DecimalValue other) => scaledValue.compareTo(other.scaledValue);

  String toDecimalString({int fractionDigits = 2}) {
    assert(fractionDigits >= 0 && fractionDigits <= 6);
    final sign = scaledValue < 0 ? '-' : '';
    final absolute = scaledValue.abs();
    final whole = absolute ~/ scale;
    if (fractionDigits == 0) return '$sign$whole';
    final fraction = (absolute % scale).toString().padLeft(6, '0');
    return '$sign$whole.${fraction.substring(0, fractionDigits)}';
  }

  String toPercentString({int fractionDigits = 1}) {
    final percentScaled = scaledValue * 100;
    return DecimalValue.scaled(percentScaled)
        .toDecimalString(fractionDigits: fractionDigits);
  }

  @override
  bool operator ==(Object other) =>
      other is DecimalValue && other.scaledValue == scaledValue;

  @override
  int get hashCode => scaledValue.hashCode;

  @override
  String toString() => toDecimalString(fractionDigits: 6);
}

int divideAndRound(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'Debe ser positivo');
  }
  return _divideRounded(numerator, denominator);
}

int _divideRounded(int numerator, int denominator) {
  final sign = numerator < 0 ? -1 : 1;
  final absolute = numerator.abs();
  var result = absolute ~/ denominator;
  final remainder = absolute % denominator;
  if (remainder * 2 >= denominator) result += 1;
  return sign * result;
}
