import '../../core/money/decimal_value.dart';
import '../common/sync_metadata.dart';
import '../geometry/geometry_models.dart';
import '../materials/material_models.dart';
import '../pricing/pricing_models.dart';

final class ProductCategory {
  const ProductCategory({
    required this.metadata,
    required this.name,
    this.isActive = true,
  });

  final SyncMetadata metadata;
  final String name;
  final bool isActive;
}

/// Medidas semánticas por código (por ejemplo, diameter/height) y forma.
/// El mapa permite sumar parámetros a una geometría sin migrar el modelo Dart.
final class ProductDimensions {
  const ProductDimensions({this.shapeCode = 'custom', this.values = const {}});

  final String shapeCode;
  final Map<String, MeasuredQuantity> values;
}

enum ProductMaterialRole { primary, complementary }

enum ConsumptionSource { manual, estimated, confirmed }

extension ConsumptionSourceLabel on ConsumptionSource {
  String get label => switch (this) {
    ConsumptionSource.manual => 'Registrado manualmente',
    ConsumptionSource.estimated => 'Estimado',
    ConsumptionSource.confirmed => 'Real confirmado',
  };
}

final class ProductMaterialUsage {
  const ProductMaterialUsage({
    required this.metadata,
    required this.productId,
    required this.materialId,
    required this.consumption,
    this.materialVariantId,
    this.role = ProductMaterialRole.primary,
    this.consumptionSource = ConsumptionSource.manual,
    this.calibrationEligible = true,
    this.notes,
  });

  final SyncMetadata metadata;
  final String productId;
  final String materialId;
  final String? materialVariantId;
  final MeasuredQuantity consumption;
  final ProductMaterialRole role;
  final ConsumptionSource consumptionSource;
  final bool calibrationEligible;
  final String? notes;
}

final class Product {
  const Product({
    required this.metadata,
    required this.name,
    required this.categoryId,
    required this.priceMultiplier,
    this.description,
    this.photoPath,
    this.dimensions,
    this.geometryProfile,
    this.pricingOverrides = const PricingOverrides(),
    this.notes,
    this.isActive = true,
  });

  final SyncMetadata metadata;
  final String name;
  final String categoryId;
  final String? description;
  final String? photoPath;
  final ProductDimensions? dimensions;
  final GeometryProfile? geometryProfile;

  /// Regla propia del producto; se conserva separada de defaults globales.
  final DecimalValue priceMultiplier;
  final PricingOverrides pricingOverrides;
  final String? notes;
  final bool isActive;

  Product withActive(bool value, DateTime updatedAt) => Product(
    metadata: SyncMetadata(
      id: metadata.id,
      createdAt: metadata.createdAt,
      updatedAt: updatedAt,
      deletedAt: metadata.deletedAt,
    ),
    name: name,
    categoryId: categoryId,
    priceMultiplier: priceMultiplier,
    description: description,
    photoPath: photoPath,
    dimensions: dimensions,
    geometryProfile: geometryProfile,
    pricingOverrides: pricingOverrides,
    notes: notes,
    isActive: value,
  );
}
