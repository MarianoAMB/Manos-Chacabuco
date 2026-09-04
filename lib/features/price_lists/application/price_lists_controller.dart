// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/materials/material_models.dart';
import '../../../core/money/money.dart';
import '../../../domain/price_lists/price_list_models.dart';
import '../../../domain/repositories/price_list_exporters.dart';
import '../../../domain/repositories/price_list_preferences_repository.dart';
import '../../../domain/services/price_list_data_builder.dart';
import '../../../domain/services/product_commercial_formatter.dart';
import '../../products/application/products_controller.dart';
import '../../settings/application/settings_controller.dart';

enum PriceListWorkStatus {
  idle,
  loading,
  generatingPdf,
  generatingImages,
  sharing,
}

final class PriceListsController extends ChangeNotifier {
  PriceListsController({
    required ProductsController productsController,
    required SettingsController settingsController,
    required PriceListPreferencesRepository preferencesRepository,
    required PriceListPdfExporter pdfExporter,
    required PriceListImageExporter imageExporter,
    required PriceListFileService fileService,
    required ShareService shareService,
    DateTime Function()? now,
  }) : _productsController = productsController,
       _settingsController = settingsController,
       _preferencesRepository = preferencesRepository,
       _pdfExporter = pdfExporter,
       _imageExporter = imageExporter,
       _fileService = fileService,
       _shareService = shareService,
       _now = now ?? DateTime.now {
    _productsController.addListener(_dependencyChanged);
    _settingsController.addListener(_dependencyChanged);
  }

  final ProductsController _productsController;
  final SettingsController _settingsController;
  final PriceListPreferencesRepository _preferencesRepository;
  final PriceListPdfExporter _pdfExporter;
  final PriceListImageExporter _imageExporter;
  final PriceListFileService _fileService;
  final ShareService _shareService;
  final DateTime Function() _now;
  final PriceListDataBuilder _builder = const PriceListDataBuilder();
  final ProductCommercialFormatter _formatter =
      const ProductCommercialFormatter();

  PriceListConfig? _config;
  PriceListWorkStatus _status = PriceListWorkStatus.idle;
  String? _errorMessage;
  String? _successMessage;
  List<String> _lastSavedPaths = const [];

  PriceListConfig? get config => _config;
  PriceListWorkStatus get status => _status;
  bool get isBusy => _status != PriceListWorkStatus.idle;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;
  List<String> get lastSavedPaths => _lastSavedPaths;
  List<PriceListSourceProduct> get products => _buildSources();

  List<String> get availableCategoryIds {
    final sources = products.where((source) => source.isActive);
    final ids = sources.map((source) => source.categoryId).toSet().toList();
    ids.sort((left, right) {
      final leftName = sources
          .firstWhere((item) => item.categoryId == left)
          .categoryName;
      final rightName = sources
          .firstWhere((item) => item.categoryId == right)
          .categoryName;
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    });
    return ids;
  }

  String categoryName(String id) =>
      products
          .where((source) => source.categoryId == id)
          .map((source) => source.categoryName)
          .firstOrNull ??
      'Otros';

  int get selectedCount {
    final current = _config;
    if (current == null) return 0;
    return products.where((source) {
      if (!current.selectedProductIds.contains(source.productId)) return false;
      if (!source.isEligibleFor(current.priceType)) return false;
      return current.showProductsWithoutPhoto || source.photoPath != null;
    }).length;
  }

  int get missingPriceCount {
    final current = _config;
    if (current == null) return 0;
    return products
        .where(
          (source) =>
              source.isActive && !source.isEligibleFor(current.priceType),
        )
        .length;
  }

  PriceListDocument? get preview {
    final current = _config;
    if (current == null) return null;
    return _builder.build(
      products: products,
      config: current,
      businessName: _settingsController.settings.businessName,
      logoPath: _settingsController.logoAbsolutePath,
      generatedAt: _now(),
      minimumWholesaleAmount:
          _settingsController.settings.minimumWholesaleAmount,
    );
  }

  Future<void> start(PriceListType type) async {
    _status = PriceListWorkStatus.loading;
    _errorMessage = null;
    _successMessage = null;
    _lastSavedPaths = const [];
    notifyListeners();
    try {
      final saved = await _preferencesRepository.load(type);
      if (saved != null) {
        _config = saved.copyWith(priceType: type);
      } else {
        final sources = products.where((source) => source.isEligibleFor(type));
        _config = PriceListConfig(
          priceType: type,
          selectedProductIds: sources.map((source) => source.productId).toSet(),
          selectedCategoryIds: sources
              .map((source) => source.categoryId)
              .toSet(),
          showWholesaleMinimum: type == PriceListType.wholesale,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Error abriendo listas de precios: $error\n$stackTrace');
      _errorMessage = 'No pudimos preparar la lista. Intentá nuevamente.';
    } finally {
      _status = PriceListWorkStatus.idle;
      notifyListeners();
    }
  }

  void closeDraft() {
    _config = null;
    _errorMessage = null;
    _successMessage = null;
    _lastSavedPaths = const [];
    notifyListeners();
  }

  void selectAll() {
    final current = _config;
    if (current == null) return;
    final eligible = products.where(
      (source) => source.isEligibleFor(current.priceType),
    );
    _update(
      current.copyWith(
        selectedProductIds: eligible.map((source) => source.productId).toSet(),
        selectedCategoryIds: eligible
            .map((source) => source.categoryId)
            .toSet(),
      ),
    );
  }

  void clearAll() {
    final current = _config;
    if (current == null) return;
    _update(
      current.copyWith(
        selectedProductIds: const {},
        selectedCategoryIds: const {},
      ),
    );
  }

  void toggleCategory(String categoryId, bool selected) {
    final current = _config;
    if (current == null) return;
    final categories = {...current.selectedCategoryIds};
    final productIds = {...current.selectedProductIds};
    final matching = products.where(
      (source) =>
          source.categoryId == categoryId &&
          source.isEligibleFor(current.priceType),
    );
    if (selected) {
      categories.add(categoryId);
      productIds.addAll(matching.map((source) => source.productId));
    } else {
      categories.remove(categoryId);
      productIds.removeAll(matching.map((source) => source.productId));
    }
    _update(
      current.copyWith(
        selectedCategoryIds: categories,
        selectedProductIds: productIds,
      ),
    );
  }

  void toggleProduct(PriceListSourceProduct source, bool selected) {
    final current = _config;
    if (current == null || !source.isEligibleFor(current.priceType)) return;
    final products = {...current.selectedProductIds};
    final categories = {...current.selectedCategoryIds};
    if (selected) {
      products.add(source.productId);
      categories.add(source.categoryId);
    } else {
      products.remove(source.productId);
      final categoryHasSelection = this.products.any(
        (item) =>
            item.categoryId == source.categoryId &&
            products.contains(item.productId),
      );
      if (!categoryHasSelection) categories.remove(source.categoryId);
    }
    _update(
      current.copyWith(
        selectedProductIds: products,
        selectedCategoryIds: categories,
      ),
    );
  }

  void setSort(PriceListSort value) {
    final current = _config;
    if (current != null) _update(current.copyWith(sort: value));
  }

  void setShowPhotos(bool value) {
    if (_config?.showPhotos == value) return;
    _copy(showPhotos: value);
  }

  Future<void> selectExportStyle(bool showPhotos) async {
    final current = _config;
    if (current == null || current.showPhotos == showPhotos) return;
    final updated = current.copyWith(showPhotos: showPhotos);
    _config = updated;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    await _savePreferences(updated);
  }

  void setShowProductsWithoutPhoto(bool value) =>
      _copy(showProductsWithoutPhoto: value);
  void setShowDimensions(bool value) => _copy(showDimensions: value);
  void setShowMaterial(bool value) => _copy(showMaterial: value);
  void setGroupByCategory(bool value) => _copy(groupByCategory: value);
  void setShowWholesaleMinimum(bool value) =>
      _copy(showWholesaleMinimum: value);
  void setShowUpdatedDate(bool value) => _copy(showUpdatedDate: value);

  void setFooterNote(String value) {
    final current = _config;
    if (current == null) return;
    _update(
      current.copyWith(
        footerNote: value.trim().isEmpty ? null : value,
        clearFooterNote: value.trim().isEmpty,
      ),
    );
  }

  Future<void> exportPdf({required bool askLocation}) async {
    await _run(
      PriceListWorkStatus.generatingPdf,
      action: () async {
        final file = await _pdfExporter.export(_requireDocument());
        final paths = await _fileService.save([file], askLocation: askLocation);
        _lastSavedPaths = paths;
        _successMessage = paths.isEmpty ? null : 'PDF guardado correctamente.';
      },
      friendlyError: 'No pudimos generar el PDF. Intentá nuevamente.',
    );
  }

  Future<void> exportImages({required bool askLocation}) async {
    await _run(
      PriceListWorkStatus.generatingImages,
      action: () async {
        final files = await _imageExporter.export(_requireDocument());
        final paths = await _fileService.save(files, askLocation: askLocation);
        _lastSavedPaths = paths;
        _successMessage = paths.isEmpty
            ? null
            : paths.length == 1
            ? 'Imagen guardada correctamente.'
            : 'Se generaron ${paths.length} imágenes.';
      },
      friendlyError: 'No pudimos generar las imágenes. Intentá nuevamente.',
    );
  }

  Future<void> sharePdf() async {
    await _run(
      PriceListWorkStatus.sharing,
      action: () async {
        final file = await _pdfExporter.export(_requireDocument());
        await _shareService.share(
          [file],
          text:
              '${_settingsController.settings.businessName} - ${_config!.priceType.title}',
        );
      },
      friendlyError: 'No pudimos abrir el menú para compartir el PDF.',
    );
  }

  Future<void> shareImages() async {
    await _run(
      PriceListWorkStatus.sharing,
      action: () async {
        final files = await _imageExporter.export(_requireDocument());
        await _shareService.share(
          files,
          text:
              '${_settingsController.settings.businessName} - ${_config!.priceType.title}',
        );
      },
      friendlyError: 'No pudimos abrir el menú para compartir las imágenes.',
    );
  }

  Future<void> openLastFile() async {
    if (_lastSavedPaths.isNotEmpty) {
      await _fileService.openFile(_lastSavedPaths.first);
    }
  }

  Future<void> openLastFolder() async {
    if (_lastSavedPaths.isNotEmpty) {
      await _fileService.openContainingFolder(_lastSavedPaths.first);
    }
  }

  void _copy({
    bool? showPhotos,
    bool? showProductsWithoutPhoto,
    bool? showDimensions,
    bool? showMaterial,
    bool? groupByCategory,
    bool? showWholesaleMinimum,
    bool? showUpdatedDate,
  }) {
    final current = _config;
    if (current == null) return;
    _update(
      current.copyWith(
        showPhotos: showPhotos,
        showProductsWithoutPhoto: showProductsWithoutPhoto,
        showDimensions: showDimensions,
        showMaterial: showMaterial,
        groupByCategory: groupByCategory,
        showWholesaleMinimum: showWholesaleMinimum,
        showUpdatedDate: showUpdatedDate,
      ),
    );
  }

  void _update(PriceListConfig value) {
    _config = value;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    unawaited(_savePreferences(value));
  }

  Future<void> _savePreferences(PriceListConfig value) async {
    try {
      await _preferencesRepository.save(value, _now().toUtc());
    } catch (error, stackTrace) {
      debugPrint(
        'No se guardaron las preferencias de lista: $error\n$stackTrace',
      );
    }
  }

  Future<void> _run(
    PriceListWorkStatus status, {
    required Future<void> Function() action,
    required String friendlyError,
  }) async {
    if (isBusy) return;
    _status = status;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('Error exportando lista: $error\n$stackTrace');
      _errorMessage = friendlyError;
    } finally {
      _status = PriceListWorkStatus.idle;
      notifyListeners();
    }
  }

  PriceListDocument _requireDocument() {
    final document = preview;
    if (document == null || document.items.isEmpty) {
      throw StateError('Elegí al menos un producto con precio.');
    }
    return document;
  }

  List<PriceListSourceProduct> _buildSources() {
    final materialBundles = _productsController.materialsController.materials;
    final materials = [for (final bundle in materialBundles) bundle.material];
    final variants = [for (final bundle in materialBundles) ...bundle.variants];
    final units = _productsController.materialsController.units;
    return [
      for (final bundle in _productsController.products)
        _source(bundle, materials, variants, units),
    ];
  }

  PriceListSourceProduct _source(
    ProductBundle bundle,
    List<Material> materials,
    List<MaterialVariant> variants,
    List<MeasurementUnit> units,
  ) {
    final product = bundle.product;
    final category = _productsController.categoryById(product.categoryId);
    final photoPath = product.photoPath == null
        ? null
        : _productsController.photoAbsolutePath(product.photoPath);
    Money? wholesale;
    Money? retail;
    try {
      final pricing = _productsController
          .calculate(product, bundle.usages)
          .pricing;
      wholesale = pricing.wholesalePrice;
      retail = pricing.retailPrice;
    } catch (_) {
      wholesale = null;
      retail = null;
    }
    return PriceListSourceProduct(
      productId: product.metadata.id,
      name: product.name,
      categoryId: product.categoryId,
      categoryName: category?.name ?? 'Otros',
      isActive: product.isActive,
      photoPath: photoPath,
      dimensionsText: _formatter.dimensions(product.dimensions, units),
      materialText: _formatter.primaryMaterials(
        usages: bundle.usages,
        materials: materials,
        variants: variants,
      ),
      wholesalePrice: wholesale,
      retailPrice: retail,
    );
  }

  void _dependencyChanged() => notifyListeners();

  @override
  void dispose() {
    _productsController.removeListener(_dependencyChanged);
    _settingsController.removeListener(_dependencyChanged);
    super.dispose();
  }
}
