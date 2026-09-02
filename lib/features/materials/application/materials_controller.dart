// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/precise_unit_cost.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/repositories/material_catalog_repository.dart';
import '../../../domain/repositories/material_repository.dart';
import '../../../domain/services/material_cost_calculator.dart';
import 'material_form_value.dart';

final class MaterialBundle {
  const MaterialBundle({required this.material, required this.variants});

  final Material material;
  final List<MaterialVariant> variants;
}

final class MaterialsController extends ChangeNotifier {
  MaterialsController({
    required MaterialRepository materialRepository,
    required MaterialCatalogRepository catalogRepository,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _materialRepository = materialRepository,
       _catalogRepository = catalogRepository,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final MaterialRepository _materialRepository;
  final MaterialCatalogRepository _catalogRepository;
  final Uuid _uuid;
  final DateTime Function() _now;
  final MaterialCostCalculator _calculator = const MaterialCostCalculator();

  List<MaterialBundle> _materials = const [];
  List<MaterialCategory> _categories = const [];
  List<MeasurementUnit> _units = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  List<MaterialBundle> get materials => _materials;
  List<MaterialCategory> get categories => _categories;
  List<MeasurementUnit> get units => _units;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  int get activeCount =>
      _materials.where((bundle) => bundle.material.isActive).length;

  MaterialCategory? categoryById(String id) =>
      _categories.where((category) => category.metadata.id == id).firstOrNull;

  MeasurementUnit? unitById(String id) =>
      _units.where((unit) => unit.id == id).firstOrNull;

  PreciseUnitCost unitCost(PurchasePresentation purchase) {
    final unit = unitById(purchase.quantity.unitId);
    if (unit == null) throw StateError('Unidad no disponible');
    return _calculator.calculate(purchase, unit);
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _materialRepository.findAll(includeInactive: true),
        _catalogRepository.findCategories(),
        _catalogRepository.findUnits(),
      ]);
      final materials = results[0] as List<Material>;
      _categories = results[1] as List<MaterialCategory>;
      _units = results[2] as List<MeasurementUnit>;
      final variants = await Future.wait(
        materials.map(
          (material) => _materialRepository.findVariants(material.metadata.id),
        ),
      );
      _materials = [
        for (var index = 0; index < materials.length; index++)
          MaterialBundle(material: materials[index], variants: variants[index]),
      ];
    } catch (error, stackTrace) {
      debugPrint('Error cargando materias primas: $error\n$stackTrace');
      _errorMessage =
          'No pudimos cargar las materias primas. Intentá nuevamente.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> save(MaterialFormValue value) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final now = _now().toUtc();
      final existingBundle = value.id == null
          ? null
          : _materials
                .where((bundle) => bundle.material.metadata.id == value.id)
                .firstOrNull;
      final materialId = value.id ?? _uuid.v4();
      final material = Material(
        metadata: SyncMetadata(
          id: materialId,
          createdAt: existingBundle?.material.metadata.createdAt ?? now,
          updatedAt: now,
        ),
        name: value.name.trim(),
        categoryId: value.categoryId,
        purchase: value.purchase,
        consumptionUnitId: value.consumptionUnitId,
        description: _nullableTrim(value.description),
        brandOrSupplier: _nullableTrim(value.brandOrSupplier),
        notes: _nullableTrim(value.notes),
        isActive: value.isActive,
      );

      final existingVariants = {
        for (final variant
            in existingBundle?.variants ?? const <MaterialVariant>[])
          variant.metadata.id: variant,
      };
      final variants = [
        for (final input in value.variants)
          MaterialVariant(
            metadata: SyncMetadata(
              id: input.id ?? _uuid.v4(),
              createdAt: existingVariants[input.id]?.metadata.createdAt ?? now,
              updatedAt: now,
            ),
            materialId: materialId,
            name: input.name.trim(),
            purchaseOverride: input.purchase,
            notes: _nullableTrim(input.notes),
            isActive: input.isActive,
          ),
      ];
      await _materialRepository.saveAggregate(material, variants);
      await load();
    } catch (error, stackTrace) {
      debugPrint('Error guardando materia prima: $error\n$stackTrace');
      _errorMessage = 'No pudimos guardar esta materia prima. Revisá los datos e intentá nuevamente.';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> setMaterialActive(MaterialBundle bundle, bool active) async {
    final now = _now().toUtc();
    await _materialRepository.saveAggregate(
      bundle.material.withActive(active, now),
      bundle.variants,
    );
    await load();
  }

  Future<void> deleteMaterial(MaterialBundle bundle) async {
    await _materialRepository.softDelete(
      bundle.material.metadata.id,
      _now().toUtc(),
    );
    await load();
  }

  Future<void> addCategory(String name) async {
    final now = _now().toUtc();
    await _catalogRepository.saveCategory(
      MaterialCategory(
        metadata: SyncMetadata(id: _uuid.v4(), createdAt: now, updatedAt: now),
        name: name.trim(),
      ),
    );
    await _reloadCategories();
  }

  Future<void> renameCategory(MaterialCategory category, String name) async {
    await _catalogRepository.saveCategory(
      MaterialCategory(
        metadata: SyncMetadata(
          id: category.metadata.id,
          createdAt: category.metadata.createdAt,
          updatedAt: _now().toUtc(),
        ),
        name: name.trim(),
        isActive: category.isActive,
      ),
    );
    await _reloadCategories();
  }

  Future<void> deleteCategory(MaterialCategory category) async {
    await _catalogRepository.deleteCategory(category.metadata.id);
    await _reloadCategories();
  }

  Future<void> _reloadCategories() async {
    _categories = await _catalogRepository.findCategories();
    notifyListeners();
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
