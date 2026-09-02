import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_quote_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/quotes/quote_models.dart';
import 'package:manos_chacabuco/domain/repositories/product_photo_store.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/materials/application/materials_controller.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';
import 'package:manos_chacabuco/features/products/application/products_controller.dart';
import 'package:manos_chacabuco/features/quotes/application/quote_form_value.dart';
import 'package:manos_chacabuco/features/quotes/application/quotes_controller.dart';
import 'package:manos_chacabuco/features/settings/application/settings_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('preserva snapshot, recalcula explícitamente, duplica y convierte sin alterar original', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final settingsRepository = SqliteSettingsRepository(database);
    final settingsController = SettingsController(
      repository: settingsRepository,
      initialSettings: await settingsRepository.getOrCreateDefaults(),
    );
    await settingsController.save(
      settingsController.settings.copyWith(
        defaultProductMultiplier: DecimalValue.parse('2'),
        defaultRetailPercentage: DecimalValue.percent('20'),
        minimumWholesaleAmount: const Money.ars(100000000),
        updatedAt: DateTime.utc(2026, 9, 2),
      ),
    );
    final materialRepository = SqliteMaterialRepository(database);
    final materialsController = MaterialsController(
      materialRepository: materialRepository,
      catalogRepository: SqliteMaterialCatalogRepository(database),
    );
    await materialsController.load();
    final productRepository = SqliteProductRepository(database);
    final productsController = ProductsController(
      productRepository: productRepository,
      catalogRepository: SqliteProductCatalogRepository(database),
      photoStore: _FakePhotoStore(),
      materialsController: materialsController,
      settingsController: settingsController,
    );
    await productsController.load();
    var currentDate = DateTime.utc(2026, 9, 2, 10);
    final quotesController = QuotesController(
      quoteRepository: SqliteQuoteRepository(database),
      productsController: productsController,
      settingsController: settingsController,
      now: () => currentDate,
    );
    await quotesController.load();

    final gram = materialsController.units.firstWhere(
      (unit) => unit.code == 'gram',
    );
    final category = materialsController.categories.first;
    Future<void> saveMaterial({
      required int basePrice,
      required int naturalPrice,
      required int blackPrice,
    }) async {
      final existing = materialsController.materials.firstOrNull;
      final variants = existing?.variants ?? const <MaterialVariant>[];
      String? idOf(String name) => variants
          .where((variant) => variant.name == name)
          .firstOrNull
          ?.metadata
          .id;
      await materialsController.save(
        MaterialFormValue(
          id: existing?.material.metadata.id,
          name: 'Cordón PP',
          categoryId: category.metadata.id,
          purchase: _presentation(gram.id, basePrice),
          consumptionUnitId: gram.id,
          isActive: true,
          variants: [
            VariantFormValue(
              id: idOf('Natural'),
              name: 'Natural',
              purchase: _presentation(gram.id, naturalPrice),
              isActive: true,
            ),
            VariantFormValue(
              id: idOf('Negro'),
              name: 'Negro',
              purchase: _presentation(gram.id, blackPrice),
              isActive: true,
            ),
          ],
        ),
      );
    }

    await saveMaterial(
      basePrice: 1000000,
      naturalPrice: 1000000,
      blackPrice: 2000000,
    );
    final material = materialsController.materials.single;
    final natural = material.variants.firstWhere(
      (variant) => variant.name == 'Natural',
    );
    final black = material.variants.firstWhere(
      (variant) => variant.name == 'Negro',
    );
    final productCategory = productsController.categories.first;
    await productsController.save(
      ProductFormValue(
        name: 'Macetero 20×20',
        categoryId: productCategory.metadata.id,
        dimensions: ProductDimensions(
          values: {
            'Diámetro': MeasuredQuantity(
              amount: DecimalValue.parse('20'),
              unitId: materialsController.units
                  .firstWhere((unit) => unit.code == 'centimeter')
                  .id,
            ),
          },
        ),
        priceMultiplier: DecimalValue.parse('2'),
        usages: [
          ProductUsageFormValue(
            materialId: material.material.metadata.id,
            materialVariantId: natural.metadata.id,
            consumption: MeasuredQuantity(
              amount: DecimalValue.parse('400'),
              unitId: gram.id,
            ),
            role: ProductMaterialRole.primary,
          ),
        ],
      ),
    );
    final source = productsController.products.single;
    final originalName = source.product.name;
    final baseItem = quotesController.itemFromProduct(source);
    final customItem = baseItem.copyWith(
      name: 'Macetero personalizado',
      dimensions: ProductDimensions(
        values: {
          'Diámetro': MeasuredQuantity(
            amount: DecimalValue.parse('25'),
            unitId: materialsController.units
                .firstWhere((unit) => unit.code == 'centimeter')
                .id,
          ),
        },
      ),
      quantity: 3,
      usages: [
        ProductUsageFormValue(
          materialId: material.material.metadata.id,
          materialVariantId: natural.metadata.id,
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('100'),
            unitId: gram.id,
          ),
          role: ProductMaterialRole.primary,
        ),
        ProductUsageFormValue(
          materialId: material.material.metadata.id,
          materialVariantId: black.metadata.id,
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('300'),
            unitId: gram.id,
          ),
          role: ProductMaterialRole.primary,
        ),
      ],
      adjustments: const [
        QuoteAdjustmentFormValue(
          description: 'Tapa especial',
          amount: Money.ars(250000),
        ),
      ],
    );
    final saved = await quotesController.save(
      QuoteFormValue(
        customerName: 'Decoraciones Luna',
        date: DateTime.utc(2026, 9, 2),
        validityDays: 15,
        validUntil: DateTime.utc(2026, 9, 17),
        priceType: QuotePriceType.retail,
        items: [customItem],
      ),
    );

    expect(saved.items.single.snapshot.materials, hasLength(2));
    expect(
      saved.items.single.snapshot.materials.map((line) => line.variantName),
      containsAll(['Natural', 'Negro']),
    );
    expect(saved.items.single.quantity, 3);
    expect(
      saved.items.single.snapshot.primaryMaterials,
      const Money.ars(700000),
    );
    expect(saved.items.single.snapshot.totalCost, const Money.ars(752500));
    expect(
      saved.items.single.unitPrice.minorUnits,
      saved.items.single.snapshot.retailPrice!.minorUnits + 250000,
    );
    expect(saved.quote.total, const Money.ars(6168000));
    expect(productsController.products.single.product.name, originalName);
    expect(
      productsController
          .products
          .single
          .product
          .dimensions!
          .values['Diámetro']!
          .amount,
      DecimalValue.parse('20'),
    );
    final historicalTotal = saved.quote.total;

    await saveMaterial(
      basePrice: 3000000,
      naturalPrice: 3000000,
      blackPrice: 4000000,
    );
    await quotesController.load();
    expect(quotesController.quotes.single.quote.total, historicalTotal);

    await productsController.save(
      ProductFormValue(
        id: source.product.metadata.id,
        name: 'Producto original modificado',
        categoryId: source.product.categoryId,
        priceMultiplier: source.product.priceMultiplier,
        usages: [
          for (final usage in source.usages)
            ProductUsageFormValue(
              id: usage.metadata.id,
              materialId: usage.materialId,
              materialVariantId: usage.materialVariantId,
              consumption: usage.consumption,
              role: usage.role,
            ),
        ],
      ),
    );
    expect(
      quotesController.quotes.single.items.single.name,
      'Macetero personalizado',
    );

    final preview = quotesController.previewRecalculation(
      quotesController.quotes.single,
    );
    expect(preview.comparison.currentTotal, isNot(historicalTotal));
    expect(preview.comparison.currentTotal, const Money.ars(12360000));
    final recalculated = await quotesController.applyRecalculation(preview);
    expect(recalculated.quote.total, preview.comparison.currentTotal);

    expect(
      quotesController.engine.isBelowWholesaleMinimum(
        priceType: QuotePriceType.wholesale,
        total: const Money.ars(100),
        minimum: settingsController.settings.minimumWholesaleAmount,
      ),
      isTrue,
    );

    currentDate = DateTime.utc(2026, 9, 20, 10);
    final duplicate = await quotesController.duplicate(recalculated);
    expect(duplicate.quote.metadata.id, isNot(recalculated.quote.metadata.id));
    expect(duplicate.quote.date, DateTime.utc(2026, 9, 20));
    expect(duplicate.quote.validityDays, 15);
    expect(duplicate.quote.validUntil, DateTime.utc(2026, 10, 5));
    expect(
      duplicate.items.single.metadata.id,
      isNot(recalculated.items.single.metadata.id),
    );
    expect(duplicate.items.single.usages, hasLength(2));

    final productDraft = quotesController.productDraftFromItem(
      recalculated.items.single,
    );
    expect(productDraft.product.metadata.id, isNot(source.product.metadata.id));
    expect(productDraft.product.name, 'Macetero personalizado');
    expect(productDraft.usages, hasLength(2));
    expect(productDraft.product.notes, isNull);
    await productsController.save(
      ProductFormValue(
        id: productDraft.product.metadata.id,
        name: productDraft.product.name,
        categoryId: productDraft.product.categoryId,
        description: productDraft.product.description,
        dimensions: productDraft.product.dimensions,
        priceMultiplier: productDraft.product.priceMultiplier,
        wasteOverride: productDraft.product.pricingOverrides.wastePercentage,
        threadOverride: productDraft.product.pricingOverrides.threadPercentage,
        retailOverride: productDraft.product.pricingOverrides.retailPercentage,
        notes: productDraft.product.notes,
        usages: [
          for (final usage in productDraft.usages)
            ProductUsageFormValue(
              id: usage.metadata.id,
              materialId: usage.materialId,
              materialVariantId: usage.materialVariantId,
              consumption: usage.consumption,
              role: usage.role,
              notes: usage.notes,
            ),
        ],
      ),
    );
    expect(productsController.products, hasLength(2));
    expect(
      productsController.products
          .where(
            (bundle) =>
                bundle.product.metadata.id == productDraft.product.metadata.id,
          )
          .single
          .product
          .name,
      'Macetero personalizado',
    );

    final restored = await SqliteQuoteRepository(database)
        .findById(recalculated.quote.metadata.id);
    expect(restored!.quote.total, recalculated.quote.total);
    expect(restored.items.single.snapshot.materials, hasLength(2));
  });
}

PurchasePresentation _presentation(String unitId, int priceMinor) =>
    PurchasePresentation(
      quantity: MeasuredQuantity(
        amount: DecimalValue.parse('1000'),
        unitId: unitId,
      ),
      price: Money.ars(priceMinor),
    );

final class _FakePhotoStore implements ProductPhotoStore {
  @override
  String absolutePath(String reference) => reference;

  @override
  Future<void> delete(String reference) async {}

  @override
  Future<String?> duplicate(String? reference) async => reference;

  @override
  Future<String> importFile(String sourcePath) async => sourcePath;
}
