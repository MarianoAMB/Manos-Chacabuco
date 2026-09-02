import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_settings_repository.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/repositories/product_photo_store.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/materials/application/materials_controller.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';
import 'package:manos_chacabuco/features/products/application/products_controller.dart';
import 'package:manos_chacabuco/features/settings/application/settings_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'recalcula con precios actuales, reglas y duplicado independiente',
    () async {
      final database = await AppDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final settingsRepository = SqliteSettingsRepository(database);
      final settings = await settingsRepository.getOrCreateDefaults();
      final settingsController = SettingsController(
        repository: settingsRepository,
        initialSettings: settings,
      );
      final materialRepository = SqliteMaterialRepository(database);
      final materialCatalog = SqliteMaterialCatalogRepository(database);
      final materialsController = MaterialsController(
        materialRepository: materialRepository,
        catalogRepository: materialCatalog,
      );
      await materialsController.load();
      final productsController = ProductsController(
        productRepository: SqliteProductRepository(database),
        catalogRepository: SqliteProductCatalogRepository(database),
        photoStore: _FakePhotoStore(),
        materialsController: materialsController,
        settingsController: settingsController,
      );
      addTearDown(productsController.dispose);
      await productsController.load();

      final meter = materialsController.units.firstWhere(
        (unit) => unit.code == 'meter',
      );
      final category = materialsController.categories.first;
      Future<void> saveMaterial(int priceMinor) => materialsController.save(
        MaterialFormValue(
          id: materialsController.materials.firstOrNull?.material.metadata.id,
          name: 'Cordón',
          categoryId: category.metadata.id,
          purchase: PurchasePresentation(
            quantity: MeasuredQuantity(
              amount: DecimalValue.parse('10'),
              unitId: meter.id,
            ),
            price: Money.ars(priceMinor),
          ),
          consumptionUnitId: meter.id,
          isActive: true,
          variants: const [],
        ),
      );

      await saveMaterial(100000);
      final materialId =
          materialsController.materials.single.material.metadata.id;
      final productCategory = productsController.categories.first;
      await productsController.save(
        ProductFormValue(
          name: 'Cesto',
          categoryId: productCategory.metadata.id,
          priceMultiplier: DecimalValue.parse('2'),
          usages: [
            ProductUsageFormValue(
              materialId: materialId,
              consumption: MeasuredQuantity(
                amount: DecimalValue.parse('2'),
                unitId: meter.id,
              ),
              role: ProductMaterialRole.primary,
            ),
            ProductUsageFormValue(
              materialId: materialId,
              consumption: MeasuredQuantity(
                amount: DecimalValue.parse('1'),
                unitId: meter.id,
              ),
              role: ProductMaterialRole.complementary,
            ),
          ],
        ),
      );

      var bundle = productsController.products.single;
      var calculation = productsController.calculate(
        bundle.product,
        bundle.usages,
      );
      expect(calculation.cost.primaryMaterials, const Money.ars(20000));
      expect(calculation.cost.thread, const Money.ars(1200));
      expect(calculation.cost.waste, const Money.ars(300));
      expect(calculation.cost.complementaryMaterials, const Money.ars(10000));
      expect(calculation.cost.totalCost, const Money.ars(31500));
      expect(calculation.pricing.wholesalePrice, const Money.ars(63000));
      expect(calculation.pricing.retailPrice, isNull);

      await saveMaterial(200000);
      bundle = productsController.products.single;
      calculation = productsController.calculate(bundle.product, bundle.usages);
      expect(calculation.cost.totalCost, const Money.ars(63000));
      expect(calculation.pricing.wholesalePrice, const Money.ars(126000));

      await settingsController.save(
        settingsController.settings.copyWith(
          defaultRetailPercentage: DecimalValue.percent('20'),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      );
      calculation = productsController.calculate(bundle.product, bundle.usages);
      expect(calculation.pricing.retailPrice, const Money.ars(151200));

      await productsController.save(
        ProductFormValue(
          id: bundle.product.metadata.id,
          name: bundle.product.name,
          categoryId: bundle.product.categoryId,
          priceMultiplier: bundle.product.priceMultiplier,
          wasteOverride: DecimalValue.percent('5'),
          threadOverride: DecimalValue.percent('10'),
          retailOverride: DecimalValue.percent('30'),
          usages: [
            for (final usage in bundle.usages)
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
      bundle = productsController.products.single;
      calculation = productsController.calculate(bundle.product, bundle.usages);
      expect(calculation.cost.thread, const Money.ars(4000));
      expect(calculation.cost.waste, const Money.ars(2000));
      expect(calculation.cost.totalCost, const Money.ars(66000));
      expect(calculation.pricing.wholesalePrice, const Money.ars(132000));
      expect(calculation.pricing.retailPrice, const Money.ars(171600));

      final duplicate = await productsController.duplicate(bundle);
      expect(productsController.products, hasLength(2));
      expect(duplicate.product.metadata.id, isNot(bundle.product.metadata.id));
      expect(duplicate.product.name, 'Cesto (copia)');
      expect(
        duplicate.usages.map((usage) => usage.metadata.id).toSet(),
        isNot(equals(bundle.usages.map((usage) => usage.metadata.id).toSet())),
      );
      expect(
        productsController
            .calculate(duplicate.product, duplicate.usages)
            .pricing
            .retailPrice,
        const Money.ars(171600),
      );
    },
  );
}

final class _FakePhotoStore implements ProductPhotoStore {
  @override
  String absolutePath(String reference) => reference;

  @override
  Future<void> delete(String reference) async {}

  @override
  Future<String?> duplicate(String? reference) async =>
      reference == null ? null : '$reference-copy';

  @override
  Future<String> importFile(String sourcePath) async => sourcePath;
}
