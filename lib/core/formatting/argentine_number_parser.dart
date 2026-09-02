import '../money/decimal_value.dart';
import '../money/money.dart';

abstract final class ArgentineNumberParser {
  static DecimalValue parseDecimal(String input) {
    final normalized = _normalize(input);
    return DecimalValue.parse(normalized);
  }

  static DecimalValue? tryParseDecimal(String input) {
    try {
      return parseDecimal(input);
    } on FormatException {
      return null;
    }
  }

  static Money parseMoney(String input, {String currency = 'ARS'}) {
    final normalized = _normalize(input);
    final fraction = normalized.split('.').elementAtOrNull(1) ?? '';
    if (fraction.length > 2) {
      throw FormatException('El importe admite hasta dos decimales', input);
    }
    final decimal = DecimalValue.parse(normalized);
    return Money(
      minorUnits: divideAndRound(decimal.scaledValue * 100, DecimalValue.scale),
      currency: currency,
    );
  }

  static Money? tryParseMoney(String input, {String currency = 'ARS'}) {
    try {
      return parseMoney(input, currency: currency);
    } on FormatException {
      return null;
    }
  }

  static String _normalize(String input) {
    var value = input
        .trim()
        .replaceAll(r'$', '')
        .replaceAll(RegExp(r'\s+'), '');
    if (value.isEmpty) throw FormatException('Ingresá un número', input);

    final commaIndex = value.lastIndexOf(',');
    if (commaIndex >= 0) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
      return value;
    }

    final dots = '.'.allMatches(value).length;
    if (dots > 1) return value.replaceAll('.', '');
    if (dots == 1) {
      final fractionLength = value.length - value.lastIndexOf('.') - 1;
      if (fractionLength == 3) return value.replaceAll('.', '');
    }
    return value;
  }
}
