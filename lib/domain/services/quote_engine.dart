import '../../core/money/money.dart';
import '../quotes/quote_models.dart';

final class QuoteRecalculationComparison {
  const QuoteRecalculationComparison({
    required this.quotedTotal,
    required this.currentTotal,
  });

  final Money quotedTotal;
  final Money currentTotal;
  Money get difference => currentTotal - quotedTotal;
}

final class QuoteEngine {
  const QuoteEngine();

  DateTime calculateValidUntil(DateTime date, int validityDays) {
    if (validityDays < 0) {
      throw ArgumentError.value(validityDays, 'validityDays');
    }
    return _dateOnly(date).add(Duration(days: validityDays));
  }

  int calculateValidityDays(DateTime date, DateTime validUntil) {
    final days = _dateOnly(validUntil).difference(_dateOnly(date)).inDays;
    if (days < 0) throw ArgumentError('El vencimiento no puede ser anterior');
    return days;
  }

  QuoteValidityStatus validityStatus(Quote quote, DateTime today) =>
      _dateOnly(today).isAfter(_dateOnly(quote.validUntil))
      ? QuoteValidityStatus.expired
      : QuoteValidityStatus.current;

  Money adjustmentTotal(
    Iterable<QuoteAdjustment> adjustments, {
    String currency = 'ARS',
  }) {
    var result = Money(minorUnits: 0, currency: currency);
    for (final adjustment in adjustments) {
      result = result + adjustment.amount;
    }
    return result;
  }

  Money finalUnitPrice({
    required Money calculatedPrice,
    required Iterable<QuoteAdjustment> itemAdjustments,
  }) =>
      calculatedPrice +
      adjustmentTotal(itemAdjustments, currency: calculatedPrice.currency);

  Money itemSubtotal(QuoteItem item) => Money(
    minorUnits: item.unitPrice.minorUnits * item.quantity,
    currency: item.unitPrice.currency,
  );

  Money total({
    required Iterable<QuoteItem> items,
    required Iterable<QuoteAdjustment> generalAdjustments,
    String currency = 'ARS',
  }) {
    var result = Money(minorUnits: 0, currency: currency);
    for (final item in items) {
      result = result + itemSubtotal(item);
    }
    return result + adjustmentTotal(generalAdjustments, currency: currency);
  }

  bool isBelowWholesaleMinimum({
    required QuotePriceType priceType,
    required Money total,
    required Money? minimum,
  }) =>
      priceType == QuotePriceType.wholesale &&
      minimum != null &&
      total.compareTo(minimum) < 0;

  QuoteRecalculationComparison compare({
    required Money quotedTotal,
    required Money currentTotal,
  }) => QuoteRecalculationComparison(
    quotedTotal: quotedTotal,
    currentTotal: currentTotal,
  );

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
