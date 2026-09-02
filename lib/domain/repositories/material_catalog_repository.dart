import '../materials/material_models.dart';

abstract interface class MaterialCatalogRepository {
  Future<List<MeasurementUnit>> findUnits();
  Future<List<MaterialCategory>> findCategories();
  Future<void> saveCategory(MaterialCategory category);
  Future<void> deleteCategory(String id);
}

final class CategoryInUseException implements Exception {
  const CategoryInUseException();
}

final class DuplicateCategoryException implements Exception {
  const DuplicateCategoryException();
}
