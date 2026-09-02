import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/domain/settings/app_settings.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/domain/pricing/pricing_models.dart';

void main() {
  test(
    'defaults conserva reglas confirmadas y deja indefinidos los pendientes',
    () {
      final now = DateTime.utc(2026, 9, 1);
      final settings = AppSettings.defaults(now: now);

      expect(settings.businessName, 'Manos Chacabuco');
      expect(settings.currency, 'ARS');
      expect(settings.defaultWastePercentage.toPercentString(), '1.5');
      expect(settings.defaultThreadPercentage.toPercentString(), '6.0');
      expect(settings.defaultRetailPercentage, isNull);
      expect(settings.defaultProductMultiplier, isNull);
      expect(settings.minimumWholesaleAmount, isNull);
    },
  );

  test('serialización mantiene enteros escalados y nulos', () {
    final original = AppSettings.defaults(now: DateTime.utc(2026, 9, 1));

    final restored = AppSettings.fromJson(original.toJson());

    expect(restored.businessName, original.businessName);
    expect(restored.defaultWastePercentage, original.defaultWastePercentage);
    expect(restored.defaultRetailPercentage, isNull);
    expect(restored.updatedAt, original.updatedAt);
  });

  test('resolver hereda defaults y conserva overrides del producto', () {
    final initial = AppSettings(
      businessName: 'Manos Chacabuco',
      currency: 'ARS',
      defaultWastePercentage: DecimalValue.percent('1.5'),
      defaultThreadPercentage: DecimalValue.percent('6'),
      defaultRetailPercentage: DecimalValue.percent('20'),
      updatedAt: DateTime.utc(2026, 9, 1),
    );
    const resolver = PricingRulesResolver();
    final inherited = resolver.resolve(initial, const PricingOverrides());
    expect(inherited.wastePercentage, DecimalValue.percent('1.5'));
    expect(inherited.threadPercentage, DecimalValue.percent('6'));
    expect(inherited.retailPercentage, DecimalValue.percent('20'));

    final updated = initial.copyWith(
      defaultWastePercentage: DecimalValue.percent('2'),
      defaultThreadPercentage: DecimalValue.percent('8'),
      defaultRetailPercentage: DecimalValue.percent('25'),
    );
    final overridden = resolver.resolve(
      updated,
      PricingOverrides(
        wastePercentage: DecimalValue.percent('3'),
        threadPercentage: DecimalValue.percent('7'),
        retailPercentage: DecimalValue.percent('30'),
      ),
    );
    expect(overridden.wastePercentage, DecimalValue.percent('3'));
    expect(overridden.threadPercentage, DecimalValue.percent('7'));
    expect(overridden.retailPercentage, DecimalValue.percent('30'));
    expect(
      resolver.resolve(updated, const PricingOverrides()).wastePercentage,
      DecimalValue.percent('2'),
    );
  });
}
