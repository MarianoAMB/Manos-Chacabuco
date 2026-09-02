import '../products/product_models.dart';

abstract interface class ProductRepository {
  Future<List<Product>> findAll({bool includeInactive = false});
  Future<Product?> findById(String id);
  Future<List<ProductMaterialUsage>> findUsages(String productId);
  Future<void> saveAggregate(
    Product product,
    List<ProductMaterialUsage> usages,
  );
  Future<void> softDelete(String id, DateTime deletedAt);
}

final class MaterialInUseException implements Exception {
  const MaterialInUseException();
}

final class MaterialVariantInUseException implements Exception {
  const MaterialVariantInUseException();
}
