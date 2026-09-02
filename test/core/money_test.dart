import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';

void main() {
  group('Money', () {
    test('multiplica sin usar punto flotante', () {
      const cost = Money.ars(1245000);

      final wholesale = cost.multiply(DecimalValue.parse('2.4'));

      expect(wholesale, const Money.ars(2988000));
    });

    test('redondea mitades alejándose de cero', () {
      const positive = Money.ars(1);
      const negative = Money.ars(-1);
      final half = DecimalValue.parse('0.5');

      expect(positive.multiply(half), const Money.ars(1));
      expect(negative.multiply(half), const Money.ars(-1));
    });

    test('rechaza sumar monedas diferentes', () {
      expect(
        () =>
            const Money.ars(100) +
            const Money(minorUnits: 100, currency: 'USD'),
        throwsArgumentError,
      );
    });
  });

  group('DecimalValue', () {
    test('acepta coma y transforma porcentaje a razón', () {
      final percentage = DecimalValue.percent('1,5');

      expect(percentage.scaledValue, 15000);
      expect(percentage.toPercentString(), '1.5');
    });

    test('limita la precisión a seis decimales', () {
      expect(() => DecimalValue.parse('1.1234567'), throwsFormatException);
    });
  });
}
