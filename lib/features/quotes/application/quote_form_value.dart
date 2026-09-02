import 'dart:convert';

import '../../../core/money/decimal_value.dart';
import '../../../core/money/money.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/quotes/quote_models.dart';
import '../../products/application/product_form_value.dart';

final class QuoteAdjustmentFormValue {
  const QuoteAdjustmentFormValue({
    required this.description,
    required this.amount,
    this.id,
  });

  final String? id;
  final String description;
  final Money amount;
}

final class QuoteItemFormValue {
  const QuoteItemFormValue({
    required this.name,
    required this.quantity,
    required this.priceMultiplier,
    required this.usages,
    this.id,
    this.sourceProductId,
    this.categoryId,
    this.description,
    this.personalizationDescription,
    this.dimensions,
    this.geometryProfile,
    this.wasteOverride,
    this.threadOverride,
    this.retailOverride,
    this.adjustments = const [],
    this.existingSnapshot,
  });

  factory QuoteItemFormValue.fromItem(
    QuoteItem item,
    List<QuoteAdjustment> adjustments,
  ) => QuoteItemFormValue(
    id: item.metadata.id,
    sourceProductId: item.sourceProductId,
    name: item.name,
    categoryId: item.categoryId,
    description: item.description,
    personalizationDescription: item.personalizationDescription,
    dimensions: item.dimensions,
    geometryProfile: item.geometryProfile,
    quantity: item.quantity,
    priceMultiplier: item.priceMultiplier,
    wasteOverride: item.pricingOverrides.wastePercentage,
    threadOverride: item.pricingOverrides.threadPercentage,
    retailOverride: item.pricingOverrides.retailPercentage,
    usages: [
      for (final usage in item.usages)
        ProductUsageFormValue(
          id: usage.metadata.id,
          materialId: usage.materialId,
          materialVariantId: usage.materialVariantId,
          consumption: usage.consumption,
          role: usage.role,
          consumptionSource: usage.consumptionSource,
          calibrationEligible: usage.calibrationEligible,
          notes: usage.notes,
        ),
    ],
    adjustments: [
      for (final adjustment in adjustments)
        QuoteAdjustmentFormValue(
          id: adjustment.metadata.id,
          description: adjustment.description,
          amount: adjustment.amount,
        ),
    ],
    existingSnapshot: item.snapshot,
  );

  final String? id;
  final String? sourceProductId;
  final String name;
  final String? categoryId;
  final String? description;
  final String? personalizationDescription;
  final ProductDimensions? dimensions;
  final GeometryProfile? geometryProfile;
  final int quantity;
  final DecimalValue priceMultiplier;
  final DecimalValue? wasteOverride;
  final DecimalValue? threadOverride;
  final DecimalValue? retailOverride;
  final List<ProductUsageFormValue> usages;
  final List<QuoteAdjustmentFormValue> adjustments;
  final QuoteItemSnapshot? existingSnapshot;

  String get configurationSignature => jsonEncode({
    'name': name.trim(),
    'categoryId': categoryId,
    'description': description?.trim(),
    'personalization': personalizationDescription?.trim(),
    'dimensions': {
      for (final entry
          in dimensions?.values.entries ??
              const <MapEntry<String, MeasuredQuantity>>[])
        entry.key: [entry.value.amount.scaledValue, entry.value.unitId],
    },
    'geometryProfile': geometryProfile?.toJson(),
    'multiplier': priceMultiplier.scaledValue,
    'waste': wasteOverride?.scaledValue,
    'thread': threadOverride?.scaledValue,
    'retail': retailOverride?.scaledValue,
    'usages': [
      for (final usage in usages)
        [
          usage.materialId,
          usage.materialVariantId,
          usage.consumption.amount.scaledValue,
          usage.consumption.unitId,
          usage.role.name,
          usage.consumptionSource.name,
          usage.notes?.trim(),
        ],
    ],
  });

  QuoteItemFormValue copyWith({
    String? name,
    String? categoryId,
    String? description,
    String? personalizationDescription,
    ProductDimensions? dimensions,
    GeometryProfile? geometryProfile,
    bool clearGeometryProfile = false,
    int? quantity,
    DecimalValue? priceMultiplier,
    DecimalValue? wasteOverride,
    bool clearWasteOverride = false,
    DecimalValue? threadOverride,
    bool clearThreadOverride = false,
    DecimalValue? retailOverride,
    bool clearRetailOverride = false,
    List<ProductUsageFormValue>? usages,
    List<QuoteAdjustmentFormValue>? adjustments,
    QuoteItemSnapshot? existingSnapshot,
    bool clearExistingSnapshot = false,
  }) => QuoteItemFormValue(
    id: id,
    sourceProductId: sourceProductId,
    name: name ?? this.name,
    categoryId: categoryId ?? this.categoryId,
    description: description ?? this.description,
    personalizationDescription:
        personalizationDescription ?? this.personalizationDescription,
    dimensions: dimensions ?? this.dimensions,
    geometryProfile: clearGeometryProfile
        ? null
        : geometryProfile ?? this.geometryProfile,
    quantity: quantity ?? this.quantity,
    priceMultiplier: priceMultiplier ?? this.priceMultiplier,
    wasteOverride: clearWasteOverride
        ? null
        : wasteOverride ?? this.wasteOverride,
    threadOverride: clearThreadOverride
        ? null
        : threadOverride ?? this.threadOverride,
    retailOverride: clearRetailOverride
        ? null
        : retailOverride ?? this.retailOverride,
    usages: usages ?? this.usages,
    adjustments: adjustments ?? this.adjustments,
    existingSnapshot: clearExistingSnapshot
        ? null
        : existingSnapshot ?? this.existingSnapshot,
  );
}

final class QuoteFormValue {
  const QuoteFormValue({
    required this.customerName,
    required this.date,
    required this.validityDays,
    required this.validUntil,
    required this.priceType,
    required this.items,
    this.id,
    this.notes,
    this.generalAdjustments = const [],
  });

  factory QuoteFormValue.fromAggregate(QuoteAggregate aggregate) =>
      QuoteFormValue(
        id: aggregate.quote.metadata.id,
        customerName: aggregate.quote.customerName,
        date: aggregate.quote.date,
        validityDays: aggregate.quote.validityDays,
        validUntil: aggregate.quote.validUntil,
        priceType: aggregate.quote.priceType,
        notes: aggregate.quote.notes,
        items: [
          for (final item in aggregate.items)
            QuoteItemFormValue.fromItem(
              item,
              aggregate.adjustmentsFor(item.metadata.id),
            ),
        ],
        generalAdjustments: [
          for (final adjustment in aggregate.generalAdjustments)
            QuoteAdjustmentFormValue(
              id: adjustment.metadata.id,
              description: adjustment.description,
              amount: adjustment.amount,
            ),
        ],
      );

  final String? id;
  final String customerName;
  final DateTime date;
  final int validityDays;
  final DateTime validUntil;
  final QuotePriceType priceType;
  final String? notes;
  final List<QuoteItemFormValue> items;
  final List<QuoteAdjustmentFormValue> generalAdjustments;
}
