import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/formatting/argentine_number_formatter.dart';
import 'package:manos_chacabuco/core/formatting/argentine_number_parser.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';

void main() {
  group('entrada numérica argentina', () {
    test('acepta coma decimal', () {
      expect(
        ArgentineNumberParser.parseDecimal('1,5'),
        DecimalValue.parse('1.5'),
      );
    });

    test('acepta punto de miles y coma decimal', () {
      expect(
        ArgentineNumberParser.parseMoney(r'$ 35.438,98'),
        const Money.ars(3543898),
      );
    });

    test('acepta el mismo importe sin separador de miles', () {
      expect(
        ArgentineNumberParser.parseMoney('35438,98'),
        const Money.ars(3543898),
      );
    });

    test('formatea y redondea con convención argentina', () {
      expect(
        ArgentineNumberFormatter.decimal(DecimalValue.parse('16.875704')),
        '16,88',
      );
      expect(
        ArgentineNumberFormatter.money(const Money.ars(3543898)),
        r'$35.438,98',
      );
    });
  });
}
