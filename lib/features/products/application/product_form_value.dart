import '../../../core/money/decimal_value.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/products/product_models.dart';

final class ProductUsageFormValue {
  const ProductUsageFormValue({
    required this.materialId,
    required this.consumption,
    required this.role,
    this.id,
    this.materialVariantId,
    this.consumptionSource = ConsumptionSource.manual,
    this.calibrationEligible = true,
    this.notes,
  });

  final String? id;
  final String materialId;
  final String? materialVariantId;
  final ConsumptionSource consumptionSource;
  final bool calibrationEligible;
  final MeasuredQuantity consumption;
  final ProductMaterialRole role;
  final String? notes;
}

final class ProductFormValue {
  const ProductFormValue({
    required this.name,
    required this.categoryId,
    required this.priceMultiplier,
    required this.usages,
    this.id,
    this.description,
    this.dimensions,
    this.geometryProfile,
    this.wasteOverride,
    this.threadOverride,
    this.retailOverride,
    this.notes,
    this.isActive = true,
    this.currentPhotoReference,
    this.newPhotoSourcePath,
    this.removePhoto = false,
  });

  final String? id;
  final String name;
  final String categoryId;
  final String? description;
  final ProductDimensions? dimensions;
  final GeometryProfile? geometryProfile;
  final DecimalValue priceMultiplier;
  final DecimalValue? wasteOverride;
  final DecimalValue? threadOverride;
  final DecimalValue? retailOverride;
  final String? notes;
  final bool isActive;
  final List<ProductUsageFormValue> usages;
  final String? currentPhotoReference;
  final String? newPhotoSourcePath;
  final bool removePhoto;
}
