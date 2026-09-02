import 'decimal_value.dart';

final class Money implements Comparable<Money> {
  const Money({required this.minorUnits, this.currency = 'ARS'});

  const Money.ars(int minorUnits) : this(minorUnits: minorUnits);

  final int minorUnits;
  final String currency;

  static const zeroArs = Money.ars(0);

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits + other.minorUnits, currency: currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits: minorUnits - other.minorUnits, currency: currency);
  }

  Money multiply(DecimalValue factor) => Money(
    minorUnits: divideAndRound(
      minorUnits * factor.scaledValue,
      DecimalValue.scale,
    ),
    currency: currency,
  );

  Money multiplyScaledQuantity(int scaledQuantity) => Money(
    minorUnits: divideAndRound(minorUnits * scaledQuantity, DecimalValue.scale),
    currency: currency,
  );

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('No se pueden mezclar $currency y ${other.currency}');
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  Map<String, Object> toJson() => {
    'minorUnits': minorUnits,
    'currency': currency,
  };

  factory Money.fromJson(Map<String, Object?> json) => Money(
    minorUnits: json['minorUnits']! as int,
    currency: json['currency']! as String,
  );

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() => '$currency $minorUnits';
}
