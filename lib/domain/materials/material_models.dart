import '../../core/money/decimal_value.dart';
import '../../core/money/money.dart';
import '../common/sync_metadata.dart';

enum MeasurementDimension { weight, length, area, count }

/// Unidad extensible: las fórmulas dependen de la dimensión y el factor, no de
/// un enum cerrado de gramos/metros/unidades.
final class MeasurementUnit {
  const MeasurementUnit({
    required this.id,
    required this.code,
    required this.name,
    required this.symbol,
    required this.dimension,
    required this.baseUnitFactor,
  });

  final String id;
  final String code;
  final String name;
  final String symbol;
  final MeasurementDimension dimension;
  final DecimalValue baseUnitFactor;
}

final class MeasuredQuantity {
  const MeasuredQuantity({required this.amount, required this.unitId});

  final DecimalValue amount;
  final String unitId;

  MeasuredQuantity copyWith({DecimalValue? amount, String? unitId}) =>
      MeasuredQuantity(
        amount: amount ?? this.amount,
        unitId: unitId ?? this.unitId,
      );
}

final class MaterialCategory {
  const MaterialCategory({
    required this.metadata,
    required this.name,
    this.isActive = true,
  });

  final SyncMetadata metadata;
  final String name;
  final bool isActive;
}

final class PurchasePresentation {
  const PurchasePresentation({required this.quantity, required this.price});

  final MeasuredQuantity quantity;
  final Money price;
}

final class Material {
  const Material({
    required this.metadata,
    required this.name,
    required this.categoryId,
    required this.purchase,
    required this.consumptionUnitId,
    this.description,
    this.brandOrSupplier,
    this.notes,
    this.isActive = true,
  });

  final SyncMetadata metadata;
  final String name;
  final String categoryId;
  final String? description;
  final PurchasePresentation purchase;
  final String consumptionUnitId;
  final String? brandOrSupplier;
  final String? notes;
  final bool isActive;

  Material withActive(bool value, DateTime updatedAt) => Material(
    metadata: SyncMetadata(
      id: metadata.id,
      createdAt: metadata.createdAt,
      updatedAt: updatedAt,
      deletedAt: metadata.deletedAt,
    ),
    name: name,
    categoryId: categoryId,
    purchase: purchase,
    consumptionUnitId: consumptionUnitId,
    description: description,
    brandOrSupplier: brandOrSupplier,
    notes: notes,
    isActive: value,
  );
}

/// Una variante puede redefinir el precio/presentación de compra del material.
final class MaterialVariant {
  const MaterialVariant({
    required this.metadata,
    required this.materialId,
    required this.name,
    this.purchaseOverride,
    this.notes,
    this.isActive = true,
  });

  final SyncMetadata metadata;
  final String materialId;
  final String name;
  final PurchasePresentation? purchaseOverride;
  final String? notes;
  final bool isActive;

  MaterialVariant withActive(bool value, DateTime updatedAt) => MaterialVariant(
    metadata: SyncMetadata(
      id: metadata.id,
      createdAt: metadata.createdAt,
      updatedAt: updatedAt,
      deletedAt: metadata.deletedAt,
    ),
    materialId: materialId,
    name: name,
    purchaseOverride: purchaseOverride,
    notes: notes,
    isActive: value,
  );
}
