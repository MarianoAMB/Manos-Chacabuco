import '../money/decimal_value.dart';
import '../money/money.dart';
import '../money/precise_unit_cost.dart';
import '../../domain/materials/material_models.dart';

abstract final class ArgentineNumberFormatter {
  static String decimal(
    DecimalValue value, {
    int fractionDigits = 2,
    bool trimTrailingZeros = true,
  }) {
    if (fractionDigits < 0 || fractionDigits > 6) {
      throw RangeError.range(fractionDigits, 0, 6, 'fractionDigits');
    }
    final roundingFactor = _powerOfTen(6 - fractionDigits);
    final roundedScaled =
        divideAndRound(value.scaledValue, roundingFactor) * roundingFactor;
    final sign = roundedScaled < 0 ? '-' : '';
    final absolute = roundedScaled.abs();
    final whole = absolute ~/ DecimalValue.scale;
    final grouped = _groupThousands(whole.toString());
    if (fractionDigits == 0) return '$sign$grouped';

    var fraction = (absolute % DecimalValue.scale)
        .toString()
        .padLeft(6, '0')
        .substring(0, fractionDigits);
    if (trimTrailingZeros) fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? '$sign$grouped' : '$sign$grouped,$fraction';
  }

  static String money(Money value) {
    final prefix = value.currency == 'ARS' ? r'$' : '${value.currency} ';
    return '$prefix${moneyAmount(value)}';
  }

  static String moneyAmount(Money value) {
    final sign = value.minorUnits < 0 ? '-' : '';
    final absolute = value.minorUnits.abs();
    final whole = absolute ~/ 100;
    final cents = (absolute % 100).toString().padLeft(2, '0');
    return '$sign${_groupThousands(whole.toString())},$cents';
  }

  static String unitCost(PreciseUnitCost cost, MeasurementUnit displayUnit) {
    final scaledMinor = cost.scaledMinorUnitsFor(displayUnit.baseUnitFactor);
    final major = DecimalValue.scaled(divideAndRound(scaledMinor, 100));
    final digits = major.scaledValue.abs() < DecimalValue.scale ? 4 : 2;
    return '${cost.currency == 'ARS' ? r'$' : '${cost.currency} '}'
        '${decimal(major, fractionDigits: digits)} / ${displayUnit.symbol}';
  }

  static String _groupThousands(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  static int _powerOfTen(int exponent) {
    var result = 1;
    for (var index = 0; index < exponent; index++) {
      result *= 10;
    }
    return result;
  }
}
