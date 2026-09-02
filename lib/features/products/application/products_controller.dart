// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/decimal_value.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/geometry/geometry_models.dart';
import '../../../domain/materials/material_models.dart';
import '../../../domain/pricing/pricing_models.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/repositories/product_catalog_repository.dart';
import '../../../domain/repositories/product_photo_store.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../../domain/services/cost_engine.dart';
import '../../../domain/services/geometry_engine.dart';
import '../../../domain/services/material_cost_calculator.dart';
import '../../../domain/services/material_estimation_engine.dart';
import '../../../domain/services/pricing_engine.dart';
import '../../materials/application/materials_controller.dart';
import '../../settings/application/settings_controller.dart';
import 'product_form_value.dart';

final class ProductBundle {
  const ProductBundle({required this.product, required this.usages});

  final Product product;
  final List<ProductMaterialUsage> usages;
}

final class ProductCalculationLine {
  const ProductCalculationLine({
    required this.usage,
    required this.material,
    required this.variant,
    required this.resolved,
  });

  final ProductMaterialUsage usage;
  final Material material;
  final MaterialVariant? variant;
  final ResolvedMaterialCostLine resolved;
}

final class ProductCalculation {
  const ProductCalculation({
    required this.lines,
    required this.rules,
    required this.cost,
    required this.pricing,
  });

  final List<ProductCalculationLine> lines;
  final EffectivePricingRules rules;
  final CostBreakdown cost;
  final PricingBreakdown pricing;
}

final class ProductMaterialEstimation {
  const ProductMaterialEstimation({
    required this.targetGeometry,
    required this.usages,
    required this.estimates,
    required this.calculation,
    this.referenceGeometry,
    this.ratio,
  });

  final GeometryResult targetGeometry;
  final GeometryResult? referenceGeometry;
  final double? ratio;
  final List<ProductMaterialUsage> usages;
  final List<MaterialEstimate> estimates;
  final ProductCalculation calculation;
}

final class ProductsController extends ChangeNotifier {
  ProductsController({
    required ProductRepository productRepository,
    required ProductCatalogRepository catalogRepository,
    required ProductPhotoStore photoStore,
    required MaterialsController materialsController,
    required SettingsController settingsController,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _productRepository = productRepository,
       _catalogRepository = catalogRepository,
       _photoStore = photoStore,
       _materialsController = materialsController,
       _settingsController = settingsController,
       _uuid = uuid,
       _now = now ?? DateTime.now {
    _materialsController.addListener(_dependencyChanged);
    _settingsController.addListener(_dependencyChanged);
  }

  final ProductRepository _productRepository;
  final ProductCatalogRepository _catalogRepository;
  final ProductPhotoStore _photoStore;
  final MaterialsController _materialsController;
  final SettingsController _settingsController;
  final Uuid _uuid;
  final DateTime Function() _now;
  final CostEngine _costEngine = const CostEngine();
  final PricingEngine _pricingEngine = const PricingEngine();
  final PricingRulesResolver _rulesResolver = const PricingRulesResolver();
  final GeometryEngine _geometryEngine = GeometryEngine.standard();
  final MaterialEstimationEngine _estimationEngine =
      const MaterialEstimationEngine();
  final UnitConverter _unitConverter = const UnitConverter();

  List<ProductBundle> _products = const [];
  List<ProductCategory> _categories = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  List<ProductBundle> get products => _products;
  List<ProductCategory> get categories => _categories;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  int get activeCount =>
      _products.where((item) => item.product.isActive).length;
  MaterialsController get materialsController => _materialsController;
  SettingsController get settingsController => _settingsController;

  ProductCategory? categoryById(String id) =>
      _categories.where((category) => category.metadata.id == id).firstOrNull;

  String? photoAbsolutePath(String? reference) =>
      reference == null ? null : _photoStore.absolutePath(reference);

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object>([
        _productRepository.findAll(includeInactive: true),
        _catalogRepository.findCategories(),
      ]);
      final products = results[0] as List<Product>;
      _categories = results[1] as List<ProductCategory>;
      final usages = await Future.wait(
        products.map(
          (product) => _productRepository.findUsages(product.metadata.id),
        ),
      );
      _products = [
        for (var index = 0; index < products.length; index++)
          ProductBundle(product: products[index], usages: usages[index]),
      ];
    } catch (error, stackTrace) {
      debugPrint('Error cargando productos: $error\n$stackTrace');
      _errorMessage = 'No pudimos cargar los productos. Intentá nuevamente.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  ProductCalculation calculate(
    Product product,
    List<ProductMaterialUsage> usages,
  ) {
    final lines = <ProductCalculationLine>[];
    for (final usage in usages) {
      final bundle = _materialsController.materials
          .where((item) => item.material.metadata.id == usage.materialId)
          .firstOrNull;
      if (bundle == null) throw StateError('Materia prima no disponible');
      final variant = usage.materialVariantId == null
          ? null
          : bundle.variants
                .where((item) => item.metadata.id == usage.materialVariantId)
                .firstOrNull;
      if (usage.materialVariantId != null && variant == null) {
        throw StateError('Variante no disponible');
      }
      final purchase = variant?.purchaseOverride ?? bundle.material.purchase;
      final usageUnit = _requireUnit(usage.consumption.unitId);
      final purchaseUnit = _requireUnit(purchase.quantity.unitId);
      final materialUnit = _requireUnit(bundle.material.consumptionUnitId);
      final resolved = _costEngine.resolveLine(
        usage: usage,
        material: bundle.material,
        variant: variant,
        usageUnit: usageUnit,
        purchaseUnit: purchaseUnit,
        materialConsumptionUnit: materialUnit,
      );
      lines.add(
        ProductCalculationLine(
          usage: usage,
          material: bundle.material,
          variant: variant,
          resolved: resolved,
        ),
      );
    }
    final rules = _rulesResolver.resolve(
      _settingsController.settings,
      PricingOverrides(
        wastePercentage: product.pricingOverrides.wastePercentage,
        threadPercentage: product.pricingOverrides.threadPercentage,
        retailPercentage: product.pricingOverrides.retailPercentage,
        priceMultiplier: product.priceMultiplier,
      ),
    );
    final cost = _costEngine.calculate(
      lines: lines.map((line) => line.resolved.line),
      threadPercentage: rules.threadPercentage,
      wastePercentage: rules.wastePercentage,
      currency: _settingsController.settings.currency,
    );
    final pricing = _pricingEngine.calculate(
      totalCost: cost.totalCost,
      priceMultiplier: product.priceMultiplier,
      retailPercentage: rules.retailPercentage,
    );
    return ProductCalculation(
      lines: lines,
      rules: rules,
      cost: cost,
      pricing: pricing,
    );
  }

  Future<void> save(ProductFormValue value) async {
    _validate(value);
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    String? importedPhoto;
    try {
      final now = _now().toUtc();
      final existing = value.id == null
          ? null
          : _products
                .where((item) => item.product.metadata.id == value.id)
                .firstOrNull;
      final productId = value.id ?? _uuid.v4();
      var photoReference = value.removePhoto
          ? null
          : value.currentPhotoReference;
      if (value.newPhotoSourcePath != null) {
        importedPhoto = await _photoStore.importFile(value.newPhotoSourcePath!);
        photoReference = importedPhoto;
      }
      final product = Product(
        metadata: SyncMetadata(
          id: productId,
          createdAt: existing?.product.metadata.createdAt ?? now,
          updatedAt: now,
        ),
        name: value.name.trim(),
        categoryId: value.categoryId,
        priceMultiplier: value.priceMultiplier,
        description: _nullableTrim(value.description),
        photoPath: photoReference,
        dimensions: value.dimensions,
        geometryProfile: value.geometryProfile,
        pricingOverrides: PricingOverrides(
          wastePercentage: value.wasteOverride,
          threadPercentage: value.threadOverride,
          retailPercentage: value.retailOverride,
        ),
        notes: _nullableTrim(value.notes),
        isActive: value.isActive,
      );
      final previousUsages = {
        for (final usage in existing?.usages ?? const <ProductMaterialUsage>[])
          usage.metadata.id: usage,
      };
      final usages = [
        for (final input in value.usages)
          ProductMaterialUsage(
            metadata: SyncMetadata(
              id: input.id ?? _uuid.v4(),
              createdAt: previousUsages[input.id]?.metadata.createdAt ?? now,
              updatedAt: now,
            ),
            productId: productId,
            materialId: input.materialId,
            materialVariantId: input.materialVariantId,
            consumption: input.consumption,
            role: input.role,
            consumptionSource: input.consumptionSource,
            calibrationEligible: input.calibrationEligible,
            notes: _nullableTrim(input.notes),
          ),
      ];
      calculate(product, usages);
      await _productRepository.saveAggregate(product, usages);
      final oldPhoto = existing?.product.photoPath;
      if (oldPhoto != null && oldPhoto != photoReference) {
        await _photoStore.delete(oldPhoto);
      }
      await load();
    } catch (error, stackTrace) {
      if (importedPhoto != null) await _photoStore.delete(importedPhoto);
      debugPrint('Error guardando producto: $error\n$stackTrace');
      _errorMessage = 'No pudimos guardar este producto. Revisá los datos e intentá nuevamente.';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<ProductBundle> duplicate(ProductBundle source) async {
    final now = _now().toUtc();
    final productId = _uuid.v4();
    final photo = await _photoStore.duplicate(source.product.photoPath);
    final product = Product(
      metadata: SyncMetadata(id: productId, createdAt: now, updatedAt: now),
      name: '${source.product.name} (copia)',
      categoryId: source.product.categoryId,
      priceMultiplier: source.product.priceMultiplier,
      description: source.product.description,
      photoPath: photo,
      dimensions: source.product.dimensions,
      geometryProfile: source.product.geometryProfile,
      pricingOverrides: source.product.pricingOverrides,
      notes: source.product.notes,
    );
    final usages = [
      for (final usage in source.usages)
        ProductMaterialUsage(
          metadata: SyncMetadata(
            id: _uuid.v4(),
            createdAt: now,
            updatedAt: now,
          ),
          productId: productId,
          materialId: usage.materialId,
          materialVariantId: usage.materialVariantId,
          consumption: usage.consumption,
          role: usage.role,
          consumptionSource: usage.consumptionSource,
          calibrationEligible: usage.calibrationEligible,
          notes: usage.notes,
        ),
    ];
    try {
      await _productRepository.saveAggregate(product, usages);
    } catch (_) {
      if (photo != null) await _photoStore.delete(photo);
      rethrow;
    }
    await load();
    return _products.firstWhere(
      (item) => item.product.metadata.id == productId,
    );
  }

  Future<void> setProductActive(ProductBundle bundle, bool active) async {
    await _productRepository.saveAggregate(
      bundle.product.withActive(active, _now().toUtc()),
      bundle.usages,
    );
    await load();
  }

  GeometryResult calculateGeometry(
    GeometryProfile profile,
    ProductDimensions dimensions,
  ) {
    final values = <String, double>{};
    for (final parameter in GeometryParameters.requiredFor(profile)) {
      final dimensionName = profile.dimensionBindings[parameter];
      final quantity = dimensionName == null
          ? null
          : dimensions.values[dimensionName];
      if (quantity == null) {
        throw GeometryValidationException(
          'Vinculá la medida ${GeometryParameters.label(parameter).toLowerCase()}.',
        );
      }
      final unit = _requireUnit(quantity.unitId);
      if (unit.dimension != MeasurementDimension.length) {
        throw const GeometryValidationException(
          'Las medidas geométricas deben usar una unidad de longitud.',
        );
      }
      final base = _unitConverter.toBase(quantity, unit);
      values[parameter] = base.scaledValue / DecimalValue.scale * 100;
    }
    final result = _geometryEngine.calculate(
      GeometryInput(profile: profile, valuesCm: values),
    );
    if (result.totalEffectiveArea <= 0) {
      throw const GeometryValidationException(
        'Elegí al menos una superficie para calcular.',
      );
    }
    return result;
  }

  double lengthInCentimeters(MeasuredQuantity quantity) {
    final unit = _requireUnit(quantity.unitId);
    if (unit.dimension != MeasurementDimension.length) {
      throw ArgumentError('La medida debe usar una unidad de longitud.');
    }
    return _unitConverter.toBase(quantity, unit).scaledValue /
        DecimalValue.scale *
        100;
  }

  DecimalValue amountFromBaseUnits(double amount, String unitId) =>
      _fromBaseUnits(amount, _requireUnit(unitId));

  ProductMaterialEstimation estimateFromProduct({
    required ProductBundle reference,
    required Product targetProduct,
  }) {
    final referenceProfile = reference.product.geometryProfile;
    final referenceDimensions = reference.product.dimensions;
    final targetProfile = targetProduct.geometryProfile;
    final targetDimensions = targetProduct.dimensions;
    if (referenceProfile == null ||
        referenceDimensions == null ||
        targetProfile == null ||
        targetDimensions == null) {
      throw const GeometryValidationException(
        'Completá la forma y las medidas antes de estimar.',
      );
    }
    if (referenceProfile.compatibilityKey != targetProfile.compatibilityKey) {
      throw const GeometryValidationException(
        'La pieza de referencia y la nueva deben tener la misma configuración geométrica.',
      );
    }
    final referenceGeometry = calculateGeometry(
      referenceProfile,
      referenceDimensions,
    );
    final targetGeometry = calculateGeometry(targetProfile, targetDimensions);
    final scaled = _estimationEngine.scaleFromProduct(
      referenceArea: referenceGeometry.totalEffectiveArea,
      targetArea: targetGeometry.totalEffectiveArea,
      usages: reference.usages,
    );
    final usages = [
      for (var index = 0; index < scaled.usages.length; index++)
        _copyUsageForTarget(
          scaled.usages[index],
          targetProduct.metadata.id,
          index,
        ),
    ];
    return ProductMaterialEstimation(
      targetGeometry: targetGeometry,
      referenceGeometry: referenceGeometry,
      ratio: scaled.ratio,
      usages: usages,
      estimates: const [],
      calculation: calculate(targetProduct, usages),
    );
  }

  ProductMaterialEstimation? estimateNewPiece({
    required Product targetProduct,
    required String materialId,
    String? materialVariantId,
  }) {
    final profile = targetProduct.geometryProfile;
    final dimensions = targetProduct.dimensions;
    if (profile == null || dimensions == null) {
      throw const GeometryValidationException(
        'Completá la forma y las medidas antes de estimar.',
      );
    }
    final targetGeometry = calculateGeometry(profile, dimensions);
    final estimate = _estimationEngine.estimate(
      materialId: materialId,
      compatibilityKey: profile.compatibilityKey,
      targetArea: targetGeometry.totalEffectiveArea,
      references: _calibrationReferences(materialId),
    );
    if (!estimate.hasEstimate) return null;
    final material = _materialsController.materials
        .where((item) => item.material.metadata.id == materialId)
        .firstOrNull;
    if (material == null) throw StateError('Materia prima no disponible');
    final unit = _requireUnit(material.material.consumptionUnitId);
    final amount = _fromBaseUnits(estimate.estimatedBaseUnits!, unit);
    final now = _now().toUtc();
    final usages = [
      ProductMaterialUsage(
        metadata: SyncMetadata(
          id: 'estimated-${targetProduct.metadata.id}-$materialId',
          createdAt: now,
          updatedAt: now,
        ),
        productId: targetProduct.metadata.id,
        materialId: materialId,
        materialVariantId: materialVariantId,
        consumption: MeasuredQuantity(amount: amount, unitId: unit.id),
        consumptionSource: ConsumptionSource.estimated,
      ),
    ];
    return ProductMaterialEstimation(
      targetGeometry: targetGeometry,
      usages: usages,
      estimates: [estimate],
      calculation: calculate(targetProduct, usages),
    );
  }

  ProductMaterialEstimation? estimateRecipeFromHistory({
    required Product targetProduct,
    required List<ProductMaterialUsage> currentUsages,
  }) {
    final profile = targetProduct.geometryProfile;
    final dimensions = targetProduct.dimensions;
    if (profile == null || dimensions == null) {
      throw const GeometryValidationException(
        'Completá la forma y las medidas antes de estimar.',
      );
    }
    final targetGeometry = calculateGeometry(profile, dimensions);
    final result = <ProductMaterialUsage>[];
    final estimates = <MaterialEstimate>[];
    final primaryMaterialIds = currentUsages
        .where((usage) => usage.role == ProductMaterialRole.primary)
        .map((usage) => usage.materialId)
        .toSet();
    for (final materialId in primaryMaterialIds) {
      final estimate = _estimationEngine.estimate(
        materialId: materialId,
        compatibilityKey: profile.compatibilityKey,
        targetArea: targetGeometry.totalEffectiveArea,
        references: _calibrationReferences(materialId).where(
          (reference) => reference.productId != targetProduct.metadata.id,
        ),
      );
      estimates.add(estimate);
      final lines = currentUsages
          .where(
            (usage) =>
                usage.role == ProductMaterialRole.primary &&
                usage.materialId == materialId,
          )
          .toList(growable: false);
      if (!estimate.hasEstimate) {
        result.addAll(lines);
        continue;
      }
      final normalized = <ProductMaterialUsage, double>{};
      var currentTotal = 0.0;
      for (final line in lines) {
        final unit = _requireUnit(line.consumption.unitId);
        final amount =
            _unitConverter.toBase(line.consumption, unit).scaledValue /
            DecimalValue.scale;
        normalized[line] = amount;
        currentTotal += amount;
      }
      for (final line in lines) {
        final share = currentTotal > 0
            ? normalized[line]! / currentTotal
            : 1 / lines.length;
        final unit = _requireUnit(line.consumption.unitId);
        result.add(
          ProductMaterialUsage(
            metadata: line.metadata,
            productId: targetProduct.metadata.id,
            materialId: line.materialId,
            materialVariantId: line.materialVariantId,
            consumption: line.consumption.copyWith(
              amount: _fromBaseUnits(
                estimate.estimatedBaseUnits! * share,
                unit,
              ),
            ),
            role: line.role,
            consumptionSource: ConsumptionSource.estimated,
            calibrationEligible: line.calibrationEligible,
            notes: line.notes,
          ),
        );
      }
    }
    result.addAll(
      currentUsages.where(
        (usage) => usage.role == ProductMaterialRole.complementary,
      ),
    );
    if (!estimates.any((estimate) => estimate.hasEstimate)) return null;
    return ProductMaterialEstimation(
      targetGeometry: targetGeometry,
      usages: result,
      estimates: estimates,
      calculation: calculate(targetProduct, result),
    );
  }

  List<MaterialCalibrationReference> _calibrationReferences(String materialId) {
    final references = <MaterialCalibrationReference>[];
    for (final bundle in _products) {
      final profile = bundle.product.geometryProfile;
      final dimensions = bundle.product.dimensions;
      if (profile == null || dimensions == null) continue;
      final matching = bundle.usages.where(
        (usage) =>
            usage.calibrationEligible &&
            usage.role == ProductMaterialRole.primary &&
            usage.materialId == materialId,
      );
      if (matching.isEmpty) continue;
      try {
        final geometry = calculateGeometry(profile, dimensions);
        var totalBase = 0.0;
        var source = ConsumptionSource.confirmed;
        for (final usage in matching) {
          final unit = _requireUnit(usage.consumption.unitId);
          totalBase +=
              _unitConverter.toBase(usage.consumption, unit).scaledValue /
              DecimalValue.scale;
          if (_sourcePriority(usage.consumptionSource) <
              _sourcePriority(source)) {
            source = usage.consumptionSource;
          }
        }
        references.add(
          MaterialCalibrationReference(
            productId: bundle.product.metadata.id,
            productName: bundle.product.name,
            materialId: materialId,
            compatibilityKey: profile.compatibilityKey,
            effectiveArea: geometry.totalEffectiveArea,
            consumptionBaseUnits: totalBase,
            consumptionSource: source,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return references;
  }

  ProductMaterialUsage _copyUsageForTarget(
    ProductMaterialUsage source,
    String productId,
    int index,
  ) {
    final now = _now().toUtc();
    return ProductMaterialUsage(
      metadata: SyncMetadata(
        id: 'estimated-$productId-$index',
        createdAt: now,
        updatedAt: now,
      ),
      productId: productId,
      materialId: source.materialId,
      materialVariantId: source.materialVariantId,
      consumption: source.consumption,
      role: source.role,
      consumptionSource: source.consumptionSource,
      calibrationEligible: source.calibrationEligible,
      notes: source.notes,
    );
  }

  DecimalValue _fromBaseUnits(double baseUnits, MeasurementUnit unit) =>
      DecimalValue.scaled(
        (baseUnits *
                DecimalValue.scale *
                DecimalValue.scale /
                unit.baseUnitFactor.scaledValue)
            .round(),
      );

  int _sourcePriority(ConsumptionSource source) => switch (source) {
    ConsumptionSource.estimated => 1,
    ConsumptionSource.manual => 2,
    ConsumptionSource.confirmed => 3,
  };

  Future<void> deleteProduct(ProductBundle bundle) async {
    await _productRepository.softDelete(
      bundle.product.metadata.id,
      _now().toUtc(),
    );
    if (bundle.product.photoPath != null) {
      await _photoStore.delete(bundle.product.photoPath!);
    }
    await load();
  }

  Future<void> addCategory(String name) async {
    final now = _now().toUtc();
    await _catalogRepository.saveCategory(
      ProductCategory(
        metadata: SyncMetadata(id: _uuid.v4(), createdAt: now, updatedAt: now),
        name: name.trim(),
      ),
    );
    await _reloadCategories();
  }

  Future<void> renameCategory(ProductCategory category, String name) async {
    await _catalogRepository.saveCategory(
      ProductCategory(
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

  Future<void> deleteCategory(ProductCategory category) async {
    await _catalogRepository.deleteCategory(category.metadata.id);
    await _reloadCategories();
  }

  Future<void> _reloadCategories() async {
    _categories = await _catalogRepository.findCategories();
    notifyListeners();
  }

  MeasurementUnit _requireUnit(String id) =>
      _materialsController.unitById(id) ??
      (throw StateError('Unidad no disponible'));

  void _validate(ProductFormValue value) {
    if (value.name.trim().isEmpty) {
      throw ArgumentError('Ingresá el nombre del producto');
    }
    if (value.categoryId.isEmpty) throw ArgumentError('Elegí una categoría');
    if (value.priceMultiplier.scaledValue <= 0) {
      throw ArgumentError('El multiplicador debe ser mayor que cero');
    }
    if (value.usages.isEmpty) {
      throw ArgumentError('Agregá al menos una materia prima');
    }
    for (final usage in value.usages) {
      if (usage.consumption.amount.scaledValue <= 0) {
        throw ArgumentError('Cada consumo debe ser mayor que cero');
      }
    }
    for (final value in [
      value.wasteOverride,
      value.threadOverride,
      value.retailOverride,
    ]) {
      if (value != null && value.scaledValue < 0) {
        throw ArgumentError('Los porcentajes no pueden ser negativos');
      }
    }
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _dependencyChanged() => notifyListeners();

  @override
  void dispose() {
    _materialsController.removeListener(_dependencyChanged);
    _settingsController.removeListener(_dependencyChanged);
    super.dispose();
  }
}
