import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../../core/money/precise_unit_cost.dart';
import '../common/sync_metadata.dart';
import '../geometry/geometry_models.dart';
import '../materials/material_models.dart';
import '../pricing/pricing_models.dart';
import '../products/product_models.dart';

enum QuotePriceType { retail, wholesale }

enum QuoteValidityStatus { current, expired }

final class Quote {
  const Quote({
    required this.metadata,
    required this.customerName,
    required this.date,
    required this.validityDays,
    required this.validUntil,
    required this.priceType,
    required this.total,
    this.notes,
  });

  final SyncMetadata metadata;
  final String customerName;
  final DateTime date;
  final int validityDays;
  final DateTime validUntil;
  final QuotePriceType priceType;
  final Money total;
  final String? notes;
}

/// Copia histórica y legible de una línea de material al momento de cotizar.
final class QuoteMaterialSnapshot {
  const QuoteMaterialSnapshot({
    required this.materialId,
    required this.materialName,
    required this.consumption,
    required this.unitName,
    required this.unitSymbol,
    required this.role,
    required this.unitCost,
    required this.cost,
    this.variantId,
    this.variantName,
  });

  final String materialId;
  final String? variantId;
  final String materialName;
  final String? variantName;
  final MeasuredQuantity consumption;
  final String unitName;
  final String unitSymbol;
  final ProductMaterialRole role;
  final PreciseUnitCost unitCost;
  final Money cost;

  Map<String, Object?> toJson() => {
    'materialId': materialId,
    'variantId': variantId,
    'materialName': materialName,
    'variantName': variantName,
    'amountScaled': consumption.amount.scaledValue,
    'unitId': consumption.unitId,
    'unitName': unitName,
    'unitSymbol': unitSymbol,
    'role': role.name,
    'unitCostScaledMinor': unitCost.scaledMinorUnits,
    'costMinor': cost.minorUnits,
    'currency': cost.currency,
  };

  factory QuoteMaterialSnapshot.fromJson(Map<String, Object?> json) =>
      QuoteMaterialSnapshot(
        materialId: json['materialId']! as String,
        variantId: json['variantId'] as String?,
        materialName: json['materialName']! as String,
        variantName: json['variantName'] as String?,
        consumption: MeasuredQuantity(
          amount: DecimalValue.scaled(json['amountScaled']! as int),
          unitId: json['unitId']! as String,
        ),
        unitName: json['unitName']! as String,
        unitSymbol: json['unitSymbol']! as String,
        role: ProductMaterialRole.values.byName(json['role']! as String),
        unitCost: PreciseUnitCost(
          scaledMinorUnits: json['unitCostScaledMinor']! as int,
          currency: json['currency']! as String,
        ),
        cost: Money(
          minorUnits: json['costMinor']! as int,
          currency: json['currency']! as String,
        ),
      );
}

/// Resultado comercial inmutable. Contiene ambas tarifas y los importes que
/// explican el cálculo histórico.
final class QuoteItemSnapshot {
  const QuoteItemSnapshot({
    required this.materials,
    required this.primaryMaterials,
    required this.thread,
    required this.waste,
    required this.complementaryMaterials,
    required this.totalCost,
    required this.threadPercentage,
    required this.wastePercentage,
    required this.multiplier,
    required this.wholesalePrice,
    required this.retailPercentage,
    required this.capturedAt,
    this.retailPrice,
  });

  final List<QuoteMaterialSnapshot> materials;
  final Money primaryMaterials;
  final Money thread;
  final Money waste;
  final Money complementaryMaterials;
  final Money totalCost;
  final DecimalValue threadPercentage;
  final DecimalValue wastePercentage;
  final DecimalValue multiplier;
  final Money wholesalePrice;
  final DecimalValue? retailPercentage;
  final Money? retailPrice;
  final DateTime capturedAt;

  Money priceFor(QuotePriceType type) {
    if (type == QuotePriceType.wholesale) return wholesalePrice;
    return retailPrice ??
        (throw StateError(
          'Definí un porcentaje minorista para este producto o en Configuración.',
        ));
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'materials': materials.map((item) => item.toJson()).toList(),
    'primaryMaterialsMinor': primaryMaterials.minorUnits,
    'threadMinor': thread.minorUnits,
    'wasteMinor': waste.minorUnits,
    'complementaryMaterialsMinor': complementaryMaterials.minorUnits,
    'totalCostMinor': totalCost.minorUnits,
    'threadPercentageScaled': threadPercentage.scaledValue,
    'wastePercentageScaled': wastePercentage.scaledValue,
    'multiplierScaled': multiplier.scaledValue,
    'wholesalePriceMinor': wholesalePrice.minorUnits,
    'retailPercentageScaled': retailPercentage?.scaledValue,
    'retailPriceMinor': retailPrice?.minorUnits,
    'currency': totalCost.currency,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  factory QuoteItemSnapshot.fromJson(Map<String, Object?> json) {
    final currency = json['currency']! as String;
    Money money(String key) =>
        Money(minorUnits: json[key]! as int, currency: currency);
    return QuoteItemSnapshot(
      materials: [
        for (final item in json['materials']! as List<Object?>)
          QuoteMaterialSnapshot.fromJson(
            Map<String, Object?>.from(item! as Map),
          ),
      ],
      primaryMaterials: money('primaryMaterialsMinor'),
      thread: money('threadMinor'),
      waste: money('wasteMinor'),
      complementaryMaterials: money('complementaryMaterialsMinor'),
      totalCost: money('totalCostMinor'),
      threadPercentage: DecimalValue.scaled(
        json['threadPercentageScaled']! as int,
      ),
      wastePercentage: DecimalValue.scaled(
        json['wastePercentageScaled']! as int,
      ),
      multiplier: DecimalValue.scaled(json['multiplierScaled']! as int),
      wholesalePrice: money('wholesalePriceMinor'),
      retailPercentage: switch (json['retailPercentageScaled']) {
        final int value => DecimalValue.scaled(value),
        _ => null,
      },
      retailPrice: switch (json['retailPriceMinor']) {
        final int value => Money(minorUnits: value, currency: currency),
        _ => null,
      },
      capturedAt: DateTime.parse(json['capturedAt']! as String),
    );
  }
}

/// La configuración productiva pertenece al ítem y nunca modifica el producto
/// usado como punto de partida.
final class QuoteItem {
  const QuoteItem({
    required this.metadata,
    required this.quoteId,
    required this.name,
    required this.quantity,
    required this.priceMultiplier,
    required this.usages,
    required this.snapshot,
    required this.unitPrice,
    this.sourceProductId,
    this.categoryId,
    this.description,
    this.personalizationDescription,
    this.dimensions,
    this.geometryProfile,
    this.pricingOverrides = const PricingOverrides(),
  });

  final SyncMetadata metadata;
  final String quoteId;
  final String? sourceProductId;
  final String name;
  final String? categoryId;
  final String? description;
  final String? personalizationDescription;
  final ProductDimensions? dimensions;
  final GeometryProfile? geometryProfile;
  final int quantity;
  final DecimalValue priceMultiplier;
  final PricingOverrides pricingOverrides;
  final List<ProductMaterialUsage> usages;
  final QuoteItemSnapshot snapshot;
  final Money unitPrice;
}

final class QuoteAdjustment {
  const QuoteAdjustment({
    required this.metadata,
    required this.quoteId,
    required this.description,
    required this.amount,
    this.quoteItemId,
  });

  final SyncMetadata metadata;
  final String quoteId;
  final String? quoteItemId;
  final String description;
  final Money amount;
}

final class QuoteAggregate {
  const QuoteAggregate({
    required this.quote,
    required this.items,
    required this.adjustments,
  });

  final Quote quote;
  final List<QuoteItem> items;
  final List<QuoteAdjustment> adjustments;

  List<QuoteAdjustment> adjustmentsFor(String itemId) => adjustments
      .where((adjustment) => adjustment.quoteItemId == itemId)
      .toList(growable: false);

  List<QuoteAdjustment> get generalAdjustments => adjustments
      .where((adjustment) => adjustment.quoteItemId == null)
      .toList(growable: false);
}
