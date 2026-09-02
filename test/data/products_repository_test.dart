import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_material_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_catalog_repository.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_product_repository.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/pricing/pricing_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/repositories/product_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persiste agregado completo y protege referencias activas', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final materialCatalog = SqliteMaterialCatalogRepository(database);
    final materialRepository = SqliteMaterialRepository(database);
    final productCatalog = SqliteProductCatalogRepository(database);
    final productRepository = SqliteProductRepository(database);
    final meter = (await materialCatalog.findUnits()).firstWhere(
      (unit) => unit.code == 'meter',
    );
    final materialCategory = (await materialCatalog.findCategories()).first;
    final productCategory = (await productCatalog.findCategories()).firstWhere(
      (category) => category.name == 'Cestos',
    );
    final now = DateTime.utc(2026, 9, 1);
    final material = Material(
      metadata: SyncMetadata(id: 'material-1', createdAt: now, updatedAt: now),
      name: 'Cordón',
      categoryId: materialCategory.metadata.id,
      purchase: PurchasePresentation(
        quantity: MeasuredQuantity(
          amount: DecimalValue.parse('10'),
          unitId: meter.id,
        ),
        price: const Money.ars(100000),
      ),
      consumptionUnitId: meter.id,
    );
    final variant = MaterialVariant(
      metadata: SyncMetadata(id: 'variant-1', createdAt: now, updatedAt: now),
      materialId: material.metadata.id,
      name: 'Natural',
      purchaseOverride: PurchasePresentation(
        quantity: MeasuredQuantity(
          amount: DecimalValue.parse('10'),
          unitId: meter.id,
        ),
        price: const Money.ars(120000),
      ),
    );
    await materialRepository.saveAggregate(material, [variant]);

    final product = Product(
      metadata: SyncMetadata(id: 'product-1', createdAt: now, updatedAt: now),
      name: 'Cesto grande',
      categoryId: productCategory.metadata.id,
      priceMultiplier: DecimalValue.parse('2.4'),
      photoPath: 'foto-local.jpg',
      dimensions: ProductDimensions(
        values: {
          'Diámetro': MeasuredQuantity(
            amount: DecimalValue.parse('30'),
            unitId: meter.id,
          ),
        },
      ),
      geometryProfile: GeometryProfile(
        shapeCode: GeometryShape.circle.code,
        components: const {GeometryComponent.base},
        dimensionBindings: const {GeometryParameters.diameter: 'Diámetro'},
      ),
      pricingOverrides: PricingOverrides(
        wastePercentage: DecimalValue.percent('2'),
        threadPercentage: DecimalValue.percent('7'),
        retailPercentage: DecimalValue.percent('20'),
      ),
    );
    final usages = [
      ProductMaterialUsage(
        metadata: SyncMetadata(
          id: 'usage-primary',
          createdAt: now,
          updatedAt: now,
        ),
        productId: product.metadata.id,
        materialId: material.metadata.id,
        materialVariantId: variant.metadata.id,
        consumption: MeasuredQuantity(
          amount: DecimalValue.parse('2.5'),
          unitId: meter.id,
        ),
        consumptionSource: ConsumptionSource.confirmed,
      ),
      ProductMaterialUsage(
        metadata: SyncMetadata(
          id: 'usage-complementary',
          createdAt: now,
          updatedAt: now,
        ),
        productId: product.metadata.id,
        materialId: material.metadata.id,
        consumption: MeasuredQuantity(
          amount: DecimalValue.parse('1'),
          unitId: meter.id,
        ),
        role: ProductMaterialRole.complementary,
      ),
    ];

    await productRepository.saveAggregate(product, usages);
    final restored = (await productRepository.findAll()).single;
    final restoredUsages = await productRepository.findUsages(
      restored.metadata.id,
    );
    expect(restored.name, 'Cesto grande');
    expect(restored.photoPath, 'foto-local.jpg');
    expect(restored.priceMultiplier, DecimalValue.parse('2.4'));
    expect(
      restored.dimensions!.values['Diámetro']!.amount,
      DecimalValue.parse('30'),
    );
    expect(
      restored.pricingOverrides.threadPercentage,
      DecimalValue.percent('7'),
    );
    expect(restored.geometryProfile!.shape, GeometryShape.circle);
    expect(
      restored.geometryProfile!.dimensionBindings[GeometryParameters.diameter],
      'Diámetro',
    );
    expect(restoredUsages, hasLength(2));
    expect(
      restoredUsages
          .singleWhere((usage) => usage.metadata.id == 'usage-primary')
          .consumptionSource,
      ConsumptionSource.confirmed,
    );
    expect(
      restoredUsages
          .singleWhere((usage) => usage.metadata.id == 'usage-complementary')
          .role,
      ProductMaterialRole.complementary,
    );

    expect(
      () => materialRepository.softDelete(material.metadata.id, now),
      throwsA(isA<MaterialInUseException>()),
    );
    expect(
      () => materialRepository.saveAggregate(material, const []),
      throwsA(isA<MaterialVariantInUseException>()),
    );

    await productRepository.softDelete(product.metadata.id, now);
    await materialRepository.softDelete(material.metadata.id, now);
    expect(await materialRepository.findById(material.metadata.id), isNull);
  });
}
