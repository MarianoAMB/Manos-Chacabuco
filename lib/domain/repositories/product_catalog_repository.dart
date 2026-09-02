import '../products/product_models.dart';

abstract interface class ProductCatalogRepository {
  Future<List<ProductCategory>> findCategories();
  Future<void> saveCategory(ProductCategory category);
  Future<void> deleteCategory(String id);
}

final class ProductCategoryInUseException implements Exception {
  const ProductCategoryInUseException();
}

final class DuplicateProductCategoryException implements Exception {
  const DuplicateProductCategoryException();
}
