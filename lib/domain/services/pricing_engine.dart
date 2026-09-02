import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';

final class PricingBreakdown {
  const PricingBreakdown({
    required this.totalCost,
    required this.multiplier,
    required this.wholesalePrice,
    required this.retailPercentage,
    required this.retailPrice,
  });

  final Money totalCost;
  final DecimalValue multiplier;
  final Money wholesalePrice;
  final DecimalValue? retailPercentage;
  final Money? retailPrice;

  Money get wholesale => wholesalePrice;
  Money? get retail => retailPrice;
}

typedef PriceResult = PricingBreakdown;

final class PricingEngine {
  const PricingEngine();

  PricingBreakdown calculate({
    required Money totalCost,
    required DecimalValue priceMultiplier,
    DecimalValue? retailPercentage,
  }) {
    final wholesale = totalCost.multiply(priceMultiplier);
    final retail = retailPercentage == null
        ? null
        : wholesale.multiply(DecimalValue.one + retailPercentage);
    return PricingBreakdown(
      totalCost: totalCost,
      multiplier: priceMultiplier,
      wholesalePrice: wholesale,
      retailPercentage: retailPercentage,
      retailPrice: retail,
    );
  }
}
