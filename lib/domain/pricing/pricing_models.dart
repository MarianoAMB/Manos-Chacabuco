import '../../core/money/decimal_value.dart';
import '../settings/app_settings.dart';

final class PricingOverrides {
  const PricingOverrides({
    this.wastePercentage,
    this.threadPercentage,
    this.retailPercentage,
    this.priceMultiplier,
  });

  final DecimalValue? wastePercentage;
  final DecimalValue? threadPercentage;
  final DecimalValue? retailPercentage;
  final DecimalValue? priceMultiplier;
}

final class EffectivePricingRules {
  const EffectivePricingRules({
    required this.wastePercentage,
    required this.threadPercentage,
    required this.retailPercentage,
    required this.priceMultiplier,
  });

  final DecimalValue wastePercentage;
  final DecimalValue threadPercentage;
  final DecimalValue? retailPercentage;
  final DecimalValue? priceMultiplier;
}

final class PricingRulesResolver {
  const PricingRulesResolver();

  EffectivePricingRules resolve(
    AppSettings settings,
    PricingOverrides overrides,
  ) => EffectivePricingRules(
    wastePercentage:
        overrides.wastePercentage ?? settings.defaultWastePercentage,
    threadPercentage:
        overrides.threadPercentage ?? settings.defaultThreadPercentage,
    retailPercentage:
        overrides.retailPercentage ?? settings.defaultRetailPercentage,
    priceMultiplier:
        overrides.priceMultiplier ?? settings.defaultProductMultiplier,
  );
}
