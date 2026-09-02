// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/decimal_value.dart';
import '../../../core/money/money.dart';
import '../../../domain/common/sync_metadata.dart';
import '../../../domain/pricing/pricing_models.dart';
import '../../../domain/products/product_models.dart';
import '../../../domain/quotes/quote_models.dart';
import '../../../domain/repositories/quote_repository.dart';
import '../../../domain/services/quote_engine.dart';
import '../../products/application/product_form_value.dart';
import '../../products/application/products_controller.dart';
import '../../settings/application/settings_controller.dart';
import 'quote_form_value.dart';

final class QuoteDraftItemCalculation {
  const QuoteDraftItemCalculation({
    required this.productCalculation,
    required this.calculatedUnitPrice,
    required this.adjustments,
    required this.finalUnitPrice,
    required this.subtotal,
  });

  final ProductCalculation productCalculation;
  final Money calculatedUnitPrice;
  final Money adjustments;
  final Money finalUnitPrice;
  final Money subtotal;
}

final class QuoteRecalculationPreview {
  const QuoteRecalculationPreview({
    required this.updated,
    required this.comparison,
  });

  final QuoteAggregate updated;
  final QuoteRecalculationComparison comparison;
}

final class QuotesController extends ChangeNotifier {
  QuotesController({
    required QuoteRepository quoteRepository,
    required ProductsController productsController,
    required SettingsController settingsController,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _quoteRepository = quoteRepository,
       productsController = productsController,
       settingsController = settingsController,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final QuoteRepository _quoteRepository;
  final ProductsController productsController;
  final SettingsController settingsController;
  final Uuid _uuid;
  final DateTime Function() _now;
  final QuoteEngine engine = const QuoteEngine();

  List<QuoteAggregate> _quotes = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _errorMessage;

  List<QuoteAggregate> get quotes => _quotes;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;
  int get currentCount => _quotes
      .where(
        (item) =>
            engine.validityStatus(item.quote, _now()) ==
            QuoteValidityStatus.current,
      )
      .length;

  DateTime get today {
    final value = _now();
    return DateTime.utc(value.year, value.month, value.day);
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _quotes = await _quoteRepository.findAll();
    } catch (error, stackTrace) {
      debugPrint('Error cargando presupuestos: $error\n$stackTrace');
      _errorMessage = 'No pudimos cargar los presupuestos. Intentá nuevamente.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  QuoteItemFormValue itemFromProduct(ProductBundle bundle) =>
      QuoteItemFormValue(
        sourceProductId: bundle.product.metadata.id,
        name: bundle.product.name,
        categoryId: bundle.product.categoryId,
        description: bundle.product.description,
        dimensions: bundle.product.dimensions,
        geometryProfile: bundle.product.geometryProfile,
        quantity: 1,
        priceMultiplier: bundle.product.priceMultiplier,
        wasteOverride: bundle.product.pricingOverrides.wastePercentage,
        threadOverride: bundle.product.pricingOverrides.threadPercentage,
        retailOverride: bundle.product.pricingOverrides.retailPercentage,
        usages: [
          for (final usage in bundle.usages)
            ProductUsageFormValue(
              materialId: usage.materialId,
              materialVariantId: usage.materialVariantId,
              consumption: usage.consumption,
              role: usage.role,
              consumptionSource: usage.consumptionSource,
              calibrationEligible: usage.calibrationEligible,
              notes: usage.notes,
            ),
        ],
      );

  QuoteItemFormValue emptyCustomItem() {
    final settings = settingsController.settings;
    return QuoteItemFormValue(
      name: '',
      categoryId: productsController.categories.firstOrNull?.metadata.id,
      quantity: 1,
      priceMultiplier: settings.defaultProductMultiplier ?? DecimalValue.one,
      usages: const [],
    );
  }

  QuoteDraftItemCalculation calculateDraftItem(
    QuoteItemFormValue value,
    QuotePriceType priceType,
  ) {
    final now = _now().toUtc();
    final itemId = value.id ?? 'draft-item';
    final product = Product(
      metadata: SyncMetadata(id: itemId, createdAt: now, updatedAt: now),
      name: value.name,
      categoryId:
          value.categoryId ??
          productsController.categories.firstOrNull?.metadata.id ??
          'custom',
      description: value.description,
      dimensions: value.dimensions,
      geometryProfile: value.geometryProfile,
      priceMultiplier: value.priceMultiplier,
      pricingOverrides: PricingOverrides(
        wastePercentage: value.wasteOverride,
        threadPercentage: value.threadOverride,
        retailPercentage: value.retailOverride,
      ),
    );
    final usages = [
      for (final usage in value.usages)
        ProductMaterialUsage(
          metadata: SyncMetadata(
            id: usage.id ?? _uuid.v4(),
            createdAt: now,
            updatedAt: now,
          ),
          productId: itemId,
          materialId: usage.materialId,
          materialVariantId: usage.materialVariantId,
          consumption: usage.consumption,
          role: usage.role,
          consumptionSource: usage.consumptionSource,
          calibrationEligible: usage.calibrationEligible,
          notes: usage.notes,
        ),
    ];
    final calculation = productsController.calculate(product, usages);
    final selected = priceType == QuotePriceType.wholesale
        ? calculation.pricing.wholesalePrice
        : calculation.pricing.retailPrice ??
              (throw StateError(
                'Definí un porcentaje minorista para este producto o en Configuración.',
              ));
    final adjustments = _formAdjustmentTotal(value.adjustments);
    final finalPrice = selected + adjustments;
    return QuoteDraftItemCalculation(
      productCalculation: calculation,
      calculatedUnitPrice: selected,
      adjustments: adjustments,
      finalUnitPrice: finalPrice,
      subtotal: Money(
        minorUnits: finalPrice.minorUnits * value.quantity,
        currency: finalPrice.currency,
      ),
    );
  }

  Money calculateDraftTotal(QuoteFormValue value) {
    var result = Money(
      minorUnits: 0,
      currency: settingsController.settings.currency,
    );
    for (final item in value.items) {
      if (item.existingSnapshot != null) {
        final base = item.existingSnapshot!.priceFor(value.priceType);
        final unit = base + _formAdjustmentTotal(item.adjustments);
        result =
            result +
            Money(
              minorUnits: unit.minorUnits * item.quantity,
              currency: unit.currency,
            );
      } else {
        result = result + calculateDraftItem(item, value.priceType).subtotal;
      }
    }
    return result + _formAdjustmentTotal(value.generalAdjustments);
  }

  Future<QuoteAggregate> save(
    QuoteFormValue value, {
    bool forceRecalculate = false,
  }) async {
    _validate(value);
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final aggregate = _buildAggregate(
        value,
        forceRecalculate: forceRecalculate,
      );
      await _quoteRepository.saveAggregate(aggregate);
      await load();
      return _quotes.firstWhere(
        (item) => item.quote.metadata.id == aggregate.quote.metadata.id,
      );
    } catch (error, stackTrace) {
      debugPrint('Error guardando presupuesto: $error\n$stackTrace');
      _errorMessage = 'No pudimos guardar el presupuesto. Revisá los datos e intentá nuevamente.';
      rethrow;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  QuoteAggregate _buildAggregate(
    QuoteFormValue value, {
    required bool forceRecalculate,
    bool duplicate = false,
  }) {
    final now = _now().toUtc();
    final existing = duplicate || value.id == null
        ? null
        : _quotes
              .where((item) => item.quote.metadata.id == value.id)
              .firstOrNull;
    final quoteId = duplicate ? _uuid.v4() : value.id ?? _uuid.v4();
    final existingItems = {
      for (final item in existing?.items ?? const <QuoteItem>[])
        item.metadata.id: item,
    };
    final items = <QuoteItem>[];
    final adjustments = <QuoteAdjustment>[];

    for (final formItem in value.items) {
      final original = existingItems[formItem.id];
      final itemId = duplicate ? _uuid.v4() : formItem.id ?? _uuid.v4();
      final calculation = forceRecalculate || formItem.existingSnapshot == null
          ? calculateDraftItem(formItem, value.priceType)
          : null;
      final snapshot = calculation == null
          ? formItem.existingSnapshot!
          : _snapshotFromCalculation(calculation.productCalculation, now);
      final itemAdjustments = <QuoteAdjustment>[];
      for (final input in formItem.adjustments) {
        itemAdjustments.add(
          QuoteAdjustment(
            metadata: SyncMetadata(
              id: duplicate ? _uuid.v4() : input.id ?? _uuid.v4(),
              createdAt: duplicate
                  ? now
                  : existing?.adjustments
                            .where((item) => item.metadata.id == input.id)
                            .firstOrNull
                            ?.metadata
                            .createdAt ??
                        now,
              updatedAt: now,
            ),
            quoteId: quoteId,
            quoteItemId: itemId,
            description: input.description.trim(),
            amount: input.amount,
          ),
        );
      }
      adjustments.addAll(itemAdjustments);
      final basePrice = snapshot.priceFor(value.priceType);
      final unitPrice = engine.finalUnitPrice(
        calculatedPrice: basePrice,
        itemAdjustments: itemAdjustments,
      );
      final usages = [
        for (final input in formItem.usages)
          ProductMaterialUsage(
            metadata: SyncMetadata(
              id: duplicate ? _uuid.v4() : input.id ?? _uuid.v4(),
              createdAt: duplicate ? now : original?.metadata.createdAt ?? now,
              updatedAt: now,
            ),
            productId: itemId,
            materialId: input.materialId,
            materialVariantId: input.materialVariantId,
            consumption: input.consumption,
            role: input.role,
            consumptionSource: input.consumptionSource,
            calibrationEligible: input.calibrationEligible,
            notes: _nullableTrim(input.notes),
          ),
      ];
      items.add(
        QuoteItem(
          metadata: SyncMetadata(
            id: itemId,
            createdAt: duplicate ? now : original?.metadata.createdAt ?? now,
            updatedAt: now,
          ),
          quoteId: quoteId,
          sourceProductId: formItem.sourceProductId,
          name: formItem.name.trim(),
          categoryId: formItem.categoryId,
          description: _nullableTrim(formItem.description),
          personalizationDescription: _nullableTrim(
            formItem.personalizationDescription,
          ),
          dimensions: formItem.dimensions,
          geometryProfile: formItem.geometryProfile,
          quantity: formItem.quantity,
          priceMultiplier: formItem.priceMultiplier,
          pricingOverrides: PricingOverrides(
            wastePercentage: formItem.wasteOverride,
            threadPercentage: formItem.threadOverride,
            retailPercentage: formItem.retailOverride,
          ),
          usages: usages,
          snapshot: snapshot,
          unitPrice: unitPrice,
        ),
      );
    }
    for (final input in value.generalAdjustments) {
      adjustments.add(
        QuoteAdjustment(
          metadata: SyncMetadata(
            id: duplicate ? _uuid.v4() : input.id ?? _uuid.v4(),
            createdAt: duplicate
                ? now
                : existing?.adjustments
                          .where((item) => item.metadata.id == input.id)
                          .firstOrNull
                          ?.metadata
                          .createdAt ??
                      now,
            updatedAt: now,
          ),
          quoteId: quoteId,
          description: input.description.trim(),
          amount: input.amount,
        ),
      );
    }
    final general = adjustments.where((item) => item.quoteItemId == null);
    final total = engine.total(
      items: items,
      generalAdjustments: general,
      currency: settingsController.settings.currency,
    );
    final date = duplicate ? today : value.date;
    final validUntil = duplicate
        ? engine.calculateValidUntil(date, value.validityDays)
        : value.validUntil;
    return QuoteAggregate(
      quote: Quote(
        metadata: SyncMetadata(
          id: quoteId,
          createdAt: duplicate
              ? now
              : existing?.quote.metadata.createdAt ?? now,
          updatedAt: now,
        ),
        customerName: value.customerName.trim(),
        date: date,
        validityDays: value.validityDays,
        validUntil: validUntil,
        priceType: value.priceType,
        total: total,
        notes: _nullableTrim(value.notes),
      ),
      items: items,
      adjustments: adjustments,
    );
  }

  QuoteItemSnapshot _snapshotFromCalculation(
    ProductCalculation calculation,
    DateTime capturedAt,
  ) => QuoteItemSnapshot(
    materials: [
      for (final line in calculation.lines)
        QuoteMaterialSnapshot(
          materialId: line.material.metadata.id,
          variantId: line.variant?.metadata.id,
          materialName: line.material.name,
          variantName: line.variant?.name,
          consumption: line.usage.consumption,
          unitName:
              productsController.materialsController
                  .unitById(line.usage.consumption.unitId)
                  ?.name ??
              line.usage.consumption.unitId,
          unitSymbol:
              productsController.materialsController
                  .unitById(line.usage.consumption.unitId)
                  ?.symbol ??
              '',
          role: line.usage.role,
          unitCost: line.resolved.line.costPerBaseUnit,
          cost: line.resolved.cost,
        ),
    ],
    primaryMaterials: calculation.cost.primaryMaterials,
    thread: calculation.cost.thread,
    waste: calculation.cost.waste,
    complementaryMaterials: calculation.cost.complementaryMaterials,
    totalCost: calculation.cost.totalCost,
    threadPercentage: calculation.rules.threadPercentage,
    wastePercentage: calculation.rules.wastePercentage,
    multiplier: calculation.pricing.multiplier,
    wholesalePrice: calculation.pricing.wholesalePrice,
    retailPercentage: calculation.pricing.retailPercentage,
    retailPrice: calculation.pricing.retailPrice,
    capturedAt: capturedAt,
  );

  Future<QuoteAggregate> duplicate(QuoteAggregate source) async {
    final copy = _buildAggregate(
      QuoteFormValue.fromAggregate(source),
      forceRecalculate: false,
      duplicate: true,
    );
    await _quoteRepository.saveAggregate(copy);
    await load();
    return _quotes.firstWhere(
      (item) => item.quote.metadata.id == copy.quote.metadata.id,
    );
  }

  QuoteRecalculationPreview previewRecalculation(QuoteAggregate source) {
    final updated = _buildAggregate(
      QuoteFormValue.fromAggregate(source),
      forceRecalculate: true,
    );
    return QuoteRecalculationPreview(
      updated: updated,
      comparison: engine.compare(
        quotedTotal: source.quote.total,
        currentTotal: updated.quote.total,
      ),
    );
  }

  Future<QuoteAggregate> applyRecalculation(
    QuoteRecalculationPreview preview,
  ) async {
    await _quoteRepository.saveAggregate(preview.updated);
    await load();
    return _quotes.firstWhere(
      (item) => item.quote.metadata.id == preview.updated.quote.metadata.id,
    );
  }

  ProductBundle productDraftFromItem(QuoteItem item) {
    final now = _now().toUtc();
    final id = _uuid.v4();
    final categoryId =
        item.categoryId ??
        productsController.categories.firstOrNull?.metadata.id ??
        (throw StateError('Creá una categoría de productos primero.'));
    return ProductBundle(
      product: Product(
        metadata: SyncMetadata(id: id, createdAt: now, updatedAt: now),
        name: item.name,
        categoryId: categoryId,
        description: item.description,
        dimensions: item.dimensions,
        geometryProfile: item.geometryProfile,
        priceMultiplier: item.priceMultiplier,
        pricingOverrides: item.pricingOverrides,
        notes: item.personalizationDescription,
      ),
      usages: [
        for (final usage in item.usages)
          ProductMaterialUsage(
            metadata: SyncMetadata(
              id: _uuid.v4(),
              createdAt: now,
              updatedAt: now,
            ),
            productId: id,
            materialId: usage.materialId,
            materialVariantId: usage.materialVariantId,
            consumption: usage.consumption,
            role: usage.role,
            consumptionSource: usage.consumptionSource,
            calibrationEligible: usage.calibrationEligible,
            notes: usage.notes,
          ),
      ],
    );
  }

  Future<void> deleteQuote(QuoteAggregate aggregate) async {
    await _quoteRepository.softDelete(
      aggregate.quote.metadata.id,
      _now().toUtc(),
    );
    await load();
  }

  bool belowWholesaleMinimum(Quote quote) => engine.isBelowWholesaleMinimum(
    priceType: quote.priceType,
    total: quote.total,
    minimum: settingsController.settings.minimumWholesaleAmount,
  );

  Money _formAdjustmentTotal(List<QuoteAdjustmentFormValue> values) {
    var total = Money(
      minorUnits: 0,
      currency: settingsController.settings.currency,
    );
    for (final item in values) {
      total = total + item.amount;
    }
    return total;
  }

  void _validate(QuoteFormValue value) {
    if (value.customerName.trim().isEmpty) {
      throw ArgumentError('Ingresá el nombre del cliente.');
    }
    if (value.validityDays < 0) {
      throw ArgumentError('La validez no puede ser negativa.');
    }
    if (value.items.isEmpty) {
      throw ArgumentError('Agregá al menos un producto.');
    }
    for (final item in value.items) {
      if (item.name.trim().isEmpty) {
        throw ArgumentError('Completá el producto.');
      }
      if (item.quantity <= 0) {
        throw ArgumentError('La cantidad debe ser mayor que cero.');
      }
      if (item.usages.isEmpty) {
        throw ArgumentError('${item.name}: agregá una materia prima.');
      }
      if (item.priceMultiplier.scaledValue <= 0) {
        throw ArgumentError('${item.name}: revisá el multiplicador.');
      }
      for (final adjustment in item.adjustments) {
        if (adjustment.description.trim().isEmpty) {
          throw ArgumentError('Describí cada ajuste adicional.');
        }
      }
    }
  }

  String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
