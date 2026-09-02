import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';

final class AppSettings {
  const AppSettings({
    required this.businessName,
    required this.currency,
    required this.defaultWastePercentage,
    required this.defaultThreadPercentage,
    required this.updatedAt,
    this.defaultRetailPercentage,
    this.defaultProductMultiplier,
    this.minimumWholesaleAmount,
  });

  factory AppSettings.defaults({DateTime? now}) => AppSettings(
    businessName: 'Manos Chacabuco',
    currency: 'ARS',
    defaultWastePercentage: DecimalValue.percent('1.5'),
    defaultThreadPercentage: DecimalValue.percent('6'),
    updatedAt: now ?? DateTime.now().toUtc(),
  );

  final String businessName;
  final String currency;
  final DecimalValue defaultWastePercentage;
  final DecimalValue defaultThreadPercentage;
  final DecimalValue? defaultRetailPercentage;
  final DecimalValue? defaultProductMultiplier;
  final Money? minimumWholesaleAmount;
  final DateTime updatedAt;

  AppSettings copyWith({
    String? businessName,
    String? currency,
    DecimalValue? defaultWastePercentage,
    DecimalValue? defaultThreadPercentage,
    DecimalValue? defaultRetailPercentage,
    bool clearDefaultRetailPercentage = false,
    DecimalValue? defaultProductMultiplier,
    bool clearDefaultProductMultiplier = false,
    Money? minimumWholesaleAmount,
    bool clearMinimumWholesaleAmount = false,
    DateTime? updatedAt,
  }) => AppSettings(
    businessName: businessName ?? this.businessName,
    currency: currency ?? this.currency,
    defaultWastePercentage:
        defaultWastePercentage ?? this.defaultWastePercentage,
    defaultThreadPercentage:
        defaultThreadPercentage ?? this.defaultThreadPercentage,
    defaultRetailPercentage: clearDefaultRetailPercentage
        ? null
        : defaultRetailPercentage ?? this.defaultRetailPercentage,
    defaultProductMultiplier: clearDefaultProductMultiplier
        ? null
        : defaultProductMultiplier ?? this.defaultProductMultiplier,
    minimumWholesaleAmount: clearMinimumWholesaleAmount
        ? null
        : minimumWholesaleAmount ?? this.minimumWholesaleAmount,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'businessName': businessName,
    'currency': currency,
    'defaultWastePercentage': defaultWastePercentage.scaledValue,
    'defaultThreadPercentage': defaultThreadPercentage.scaledValue,
    'defaultRetailPercentage': defaultRetailPercentage?.scaledValue,
    'defaultProductMultiplier': defaultProductMultiplier?.scaledValue,
    'minimumWholesaleMinorUnits': minimumWholesaleAmount?.minorUnits,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    businessName: json['businessName']! as String,
    currency: json['currency']! as String,
    defaultWastePercentage: DecimalValue.scaled(
      json['defaultWastePercentage']! as int,
    ),
    defaultThreadPercentage: DecimalValue.scaled(
      json['defaultThreadPercentage']! as int,
    ),
    defaultRetailPercentage: switch (json['defaultRetailPercentage']) {
      final int value => DecimalValue.scaled(value),
      _ => null,
    },
    defaultProductMultiplier: switch (json['defaultProductMultiplier']) {
      final int value => DecimalValue.scaled(value),
      _ => null,
    },
    minimumWholesaleAmount: switch (json['minimumWholesaleMinorUnits']) {
      final int value => Money(
        minorUnits: value,
        currency: json['currency']! as String,
      ),
      _ => null,
    },
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );
}
