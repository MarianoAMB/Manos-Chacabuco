import '../materials/material_models.dart';

abstract interface class MaterialRepository {
  Future<List<Material>> findAll({bool includeInactive = false});
  Future<Material?> findById(String id);
  Future<List<MaterialVariant>> findVariants(String materialId);
  Future<void> saveAggregate(Material material, List<MaterialVariant> variants);
  Future<void> softDelete(String id, DateTime deletedAt);
}
