import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/pricing/pricing_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/quotes/quote_models.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';
import 'package:manos_chacabuco/features/quotes/application/quote_form_value.dart';

import '../support/test_app_harness.dart';

void main() {
  test(
    'escala dos colores, conserva costo ponderado y no modifica original',
    () async {
      final harness = await createTestAppHarness();
      addTearDown(harness.close);
      await harness.settingsController.save(
        harness.settingsController.settings.copyWith(
          defaultRetailPercentage: DecimalValue.percent('20'),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      );
      final data = await _seedReference(harness);
      final reference = harness.productsController.products.single;
      final target = _targetProduct(
        reference.product,
        data.centimeterId,
        height: '32.5',
      );

      final estimate = harness.productsController.estimateFromProduct(
        reference: reference,
        targetProduct: target,
      );

      expect(estimate.ratio, closeTo(1.5, 0.000001));
      expect(estimate.usages, hasLength(2));
      expect(
        estimate.usages
            .firstWhere((usage) => usage.materialVariantId == data.naturalId)
            .consumption
            .amount,
        DecimalValue.parse('150'),
      );
      expect(
        estimate.usages
            .firstWhere((usage) => usage.materialVariantId == data.blackId)
            .consumption
            .amount,
        DecimalValue.parse('450'),
      );
      expect(
        estimate.usages.every(
          (usage) => usage.consumptionSource == ConsumptionSource.estimated,
        ),
        isTrue,
      );
      expect(
        estimate.calculation.cost.primaryMaterials,
        const Money.ars(1050000),
      );
      expect(estimate.calculation.cost.thread, const Money.ars(63000));
      expect(estimate.calculation.cost.waste, const Money.ars(15750));
      expect(estimate.calculation.cost.totalCost, const Money.ars(1128750));
      expect(
        estimate.calculation.pricing.wholesalePrice,
        const Money.ars(2257500),
      );
      expect(
        estimate.calculation.pricing.retailPrice,
        const Money.ars(2709000),
      );
      expect(
        reference.usages
            .firstWhere((usage) => usage.materialVariantId == data.naturalId)
            .consumption
            .amount,
        DecimalValue.parse('100'),
      );
      expect(
        reference.usages
            .firstWhere((usage) => usage.materialVariantId == data.blackId)
            .consumption
            .amount,
        DecimalValue.parse('300'),
      );

      final newPiece = harness.productsController.estimateNewPiece(
        targetProduct: target,
        materialId: data.materialId,
        materialVariantId: data.blackId,
      );
      expect(newPiece, isNotNull);
      expect(
        newPiece!.usages.single.consumption.amount,
        DecimalValue.parse('600'),
      );
      expect(newPiece.estimates.single.references, hasLength(1));
    },
  );

  test(
    'presupuesto aplica estimación sólo al guardar y conserva producto base',
    () async {
      final harness = await createTestAppHarness();
      addTearDown(harness.close);
      await harness.settingsController.save(
        harness.settingsController.settings.copyWith(
          defaultRetailPercentage: DecimalValue.percent('20'),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      );
      final data = await _seedReference(harness);
      final reference = harness.productsController.products.single;
      final originalFormItem = harness.quotesController.itemFromProduct(
        reference,
      );
      final original = await harness.quotesController.save(
        QuoteFormValue(
          customerName: 'Cliente',
          date: DateTime.utc(2026, 9, 2),
          validityDays: 15,
          validUntil: DateTime.utc(2026, 9, 17),
          priceType: QuotePriceType.retail,
          items: [originalFormItem],
        ),
      );
      final historicalSnapshot = original.items.single.snapshot;
      final target = _targetProduct(
        reference.product,
        data.centimeterId,
        height: '32.5',
      );
      final estimation = harness.productsController.estimateFromProduct(
        reference: reference,
        targetProduct: target,
      );

      expect(
        harness.quotesController.quotes.single.items.single.snapshot,
        same(historicalSnapshot),
      );
      expect(harness.productsController.products.single.usages, hasLength(2));

      final editedItem =
          QuoteItemFormValue.fromItem(
            original.items.single,
            original.adjustmentsFor(original.items.single.metadata.id),
          ).copyWith(
            dimensions: target.dimensions,
            geometryProfile: target.geometryProfile,
            usages: [
              for (final usage in estimation.usages)
                ProductUsageFormValue(
                  materialId: usage.materialId,
                  materialVariantId: usage.materialVariantId,
                  consumption: usage.consumption,
                  role: usage.role,
                  consumptionSource: usage.consumptionSource,
                ),
            ],
            clearExistingSnapshot: true,
          );
      final saved = await harness.quotesController.save(
        QuoteFormValue(
          id: original.quote.metadata.id,
          customerName: original.quote.customerName,
          date: original.quote.date,
          validityDays: original.quote.validityDays,
          validUntil: original.quote.validUntil,
          priceType: original.quote.priceType,
          items: [editedItem],
        ),
      );

      expect(saved.items.single.snapshot, isNot(same(historicalSnapshot)));
      expect(
        saved.items.single.usages
            .firstWhere((usage) => usage.materialVariantId == data.naturalId)
            .consumption
            .amount,
        DecimalValue.parse('150'),
      );
      expect(
        saved.items.single.usages
            .firstWhere((usage) => usage.materialVariantId == data.blackId)
            .consumption
            .amount,
        DecimalValue.parse('450'),
      );
      final originalUsages = harness.productsController.products.single.usages;
      expect(
        originalUsages
            .firstWhere((usage) => usage.materialVariantId == data.naturalId)
            .consumption
            .amount,
        DecimalValue.parse('100'),
      );
      expect(
        originalUsages
            .firstWhere((usage) => usage.materialVariantId == data.blackId)
            .consumption
            .amount,
        DecimalValue.parse('300'),
      );
      expect(
        saved.items.single.unitPrice,
        isNot(original.items.single.unitPrice),
      );
    },
  );
}

final class _SeedData {
  const _SeedData({
    required this.materialId,
    required this.naturalId,
    required this.blackId,
    required this.centimeterId,
  });

  final String materialId;
  final String naturalId;
  final String blackId;
  final String centimeterId;
}

Future<_SeedData> _seedReference(TestAppHarness harness) async {
  final gram = harness.materialsController.units.firstWhere(
    (unit) => unit.code == 'gram',
  );
  final centimeter = harness.materialsController.units.firstWhere(
    (unit) => unit.code == 'centimeter',
  );
  await harness.materialsController.save(
    MaterialFormValue(
      name: 'Cordón PP',
      categoryId: harness.materialsController.categories.first.metadata.id,
      purchase: _presentation(gram.id, 1000000),
      consumptionUnitId: gram.id,
      isActive: true,
      variants: [
        VariantFormValue(
          name: 'Natural',
          purchase: _presentation(gram.id, 1000000),
          isActive: true,
        ),
        VariantFormValue(
          name: 'Negro',
          purchase: _presentation(gram.id, 2000000),
          isActive: true,
        ),
      ],
    ),
  );
  final material = harness.materialsController.materials.single;
  final natural = material.variants.firstWhere(
    (value) => value.name == 'Natural',
  );
  final black = material.variants.firstWhere((value) => value.name == 'Negro');
  await harness.productsController.save(
    ProductFormValue(
      name: 'Cesto 20×20',
      categoryId: harness.productsController.categories.first.metadata.id,
      dimensions: ProductDimensions(
        shapeCode: GeometryShape.cylinder.code,
        values: {
          'Diámetro': MeasuredQuantity(
            amount: DecimalValue.parse('20'),
            unitId: centimeter.id,
          ),
          'Alto': MeasuredQuantity(
            amount: DecimalValue.parse('20'),
            unitId: centimeter.id,
          ),
        },
      ),
      geometryProfile: GeometryProfile(
        shapeCode: GeometryShape.cylinder.code,
        components: const {GeometryComponent.base, GeometryComponent.lateral},
        dimensionBindings: const {
          GeometryParameters.diameter: 'Diámetro',
          GeometryParameters.height: 'Alto',
        },
      ),
      priceMultiplier: DecimalValue.parse('2'),
      usages: [
        ProductUsageFormValue(
          materialId: material.material.metadata.id,
          materialVariantId: natural.metadata.id,
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('100'),
            unitId: gram.id,
          ),
          role: ProductMaterialRole.primary,
          consumptionSource: ConsumptionSource.confirmed,
        ),
        ProductUsageFormValue(
          materialId: material.material.metadata.id,
          materialVariantId: black.metadata.id,
          consumption: MeasuredQuantity(
            amount: DecimalValue.parse('300'),
            unitId: gram.id,
          ),
          role: ProductMaterialRole.primary,
          consumptionSource: ConsumptionSource.confirmed,
        ),
      ],
    ),
  );
  return _SeedData(
    materialId: material.material.metadata.id,
    naturalId: natural.metadata.id,
    blackId: black.metadata.id,
    centimeterId: centimeter.id,
  );
}

Product _targetProduct(
  Product source,
  String centimeterId, {
  required String height,
}) {
  final now = DateTime.utc(2026, 9, 2);
  return Product(
    metadata: SyncMetadata(id: 'target', createdAt: now, updatedAt: now),
    name: 'Cesto nuevo',
    categoryId: source.categoryId,
    dimensions: ProductDimensions(
      shapeCode: GeometryShape.cylinder.code,
      values: {
        'Diámetro': MeasuredQuantity(
          amount: DecimalValue.parse('20'),
          unitId: centimeterId,
        ),
        'Alto': MeasuredQuantity(
          amount: DecimalValue.parse(height),
          unitId: centimeterId,
        ),
      },
    ),
    geometryProfile: source.geometryProfile,
    priceMultiplier: source.priceMultiplier,
    pricingOverrides: const PricingOverrides(),
  );
}

PurchasePresentation _presentation(String unitId, int priceMinor) =>
    PurchasePresentation(
      quantity: MeasuredQuantity(
        amount: DecimalValue.parse('1000'),
        unitId: unitId,
      ),
      price: Money.ars(priceMinor),
    );
