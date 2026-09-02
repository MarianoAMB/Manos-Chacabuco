import '../../../domain/materials/material_models.dart';

final class MaterialFormValue {
  const MaterialFormValue({
    required this.name,
    required this.categoryId,
    required this.purchase,
    required this.consumptionUnitId,
    required this.isActive,
    required this.variants,
    this.id,
    this.description,
    this.brandOrSupplier,
    this.notes,
  });

  final String? id;
  final String name;
  final String categoryId;
  final PurchasePresentation purchase;
  final String consumptionUnitId;
  final String? description;
  final String? brandOrSupplier;
  final String? notes;
  final bool isActive;
  final List<VariantFormValue> variants;
}

final class VariantFormValue {
  const VariantFormValue({
    required this.name,
    required this.purchase,
    required this.isActive,
    this.id,
    this.notes,
  });

  final String? id;
  final String name;
  final PurchasePresentation purchase;
  final String? notes;
  final bool isActive;
}
