import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/database/app_database.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/core/money/precise_unit_cost.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_quote_repository.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/quotes/quote_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('persiste y reconstruye configuración, snapshots y ajustes', () async {
    final database = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    final repository = SqliteQuoteRepository(database);
    final now = DateTime.utc(2026, 9, 2, 12);
    final snapshot = QuoteItemSnapshot(
      materials: [
        QuoteMaterialSnapshot(
          materialId: 'material',
          variantId: 'black',
          materialName: 'Cordón PP',
          variantName: 'Negro',
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('300'),
            unitId: 'gram',
          ),
          unitName: 'Gramos',
          unitSymbol: 'g',
          role: ProductMaterialRole.primary,
          unitCost: const PreciseUnitCost(
            scaledMinorUnits: 5000,
            currency: 'ARS',
          ),
          cost: const Money.ars(1500),
        ),
      ],
      primaryMaterials: const Money.ars(1500),
      thread: const Money.ars(90),
      waste: const Money.ars(23),
      complementaryMaterials: Money.zeroArs,
      totalCost: const Money.ars(1613),
      threadPercentage: DecimalValue.percent('6'),
      wastePercentage: DecimalValue.percent('1.5'),
      multiplier: DecimalValue.parse('2'),
      wholesalePrice: const Money.ars(3226),
      retailPercentage: DecimalValue.percent('20'),
      retailPrice: const Money.ars(3871),
      capturedAt: now,
    );
    final item = QuoteItem(
      metadata: SyncMetadata(id: 'item', createdAt: now, updatedAt: now),
      quoteId: 'quote',
      name: 'Macetero personalizado',
      categoryId: 'category',
      personalizationDescription: 'Tapa cónica',
      dimensions: ProductDimensions(
        values: {
          'Alto': MeasuredQuantity(
            amount: DecimalValue.parse('30'),
            unitId: 'centimeter',
          ),
        },
      ),
      geometryProfile: GeometryProfile(
        shapeCode: GeometryShape.cylinder.code,
        components: const {GeometryComponent.base, GeometryComponent.lateral},
        dimensionBindings: const {GeometryParameters.height: 'Alto'},
      ),
      quantity: 3,
      priceMultiplier: DecimalValue.parse('2'),
      usages: [
        ProductMaterialUsage(
          metadata: SyncMetadata(id: 'usage', createdAt: now, updatedAt: now),
          productId: 'item',
          materialId: 'material',
          materialVariantId: 'black',
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('300'),
            unitId: 'gram',
          ),
          consumptionSource: ConsumptionSource.estimated,
        ),
      ],
      snapshot: snapshot,
      unitPrice: const Money.ars(6371),
    );
    final aggregate = QuoteAggregate(
      quote: Quote(
        metadata: SyncMetadata(id: 'quote', createdAt: now, updatedAt: now),
        customerName: 'Decoraciones Luna',
        date: DateTime.utc(2026, 9, 2),
        validityDays: 15,
        validUntil: DateTime.utc(2026, 9, 17),
        priceType: QuotePriceType.retail,
        total: const Money.ars(1811300),
        notes: 'Retira por el taller',
      ),
      items: [item],
      adjustments: [
        QuoteAdjustment(
          metadata: SyncMetadata(
            id: 'item-adjustment',
            createdAt: now,
            updatedAt: now,
          ),
          quoteId: 'quote',
          quoteItemId: 'item',
          description: 'Tapa especial',
          amount: const Money.ars(2500),
        ),
        QuoteAdjustment(
          metadata: SyncMetadata(
            id: 'general-adjustment',
            createdAt: now,
            updatedAt: now,
          ),
          quoteId: 'quote',
          description: 'Descuento acordado',
          amount: const Money.ars(-10000),
        ),
      ],
    );

    await repository.saveAggregate(aggregate);
    final restored = await repository.findById('quote');

    expect(restored, isNotNull);
    expect(restored!.quote.customerName, 'Decoraciones Luna');
    expect(restored.quote.validityDays, 15);
    expect(restored.items.single.quantity, 3);
    expect(
      restored.items.single.dimensions!.values['Alto']!.amount,
      DecimalValue.parse('30'),
    );
    expect(restored.items.single.usages.single.materialVariantId, 'black');
    expect(
      restored.items.single.usages.single.consumptionSource,
      ConsumptionSource.estimated,
    );
    expect(
      restored.items.single.geometryProfile!.shape,
      GeometryShape.cylinder,
    );
    expect(
      restored.items.single.snapshot.materials.single.materialName,
      'Cordón PP',
    );
    expect(restored.items.single.snapshot.retailPrice, const Money.ars(3871));
    expect(restored.adjustmentsFor('item').single.description, 'Tapa especial');
    expect(restored.generalAdjustments.single.amount, const Money.ars(-10000));

    await repository.softDelete('quote', DateTime.utc(2026, 9, 3));
    expect(await repository.findAll(), isEmpty);
  });
}
