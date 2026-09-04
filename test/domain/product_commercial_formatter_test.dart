import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/common/sync_metadata.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/domain/services/product_commercial_formatter.dart';

void main() {
  const formatter = ProductCommercialFormatter();
  const centimeter = MeasurementUnit(
    id: 'cm',
    code: 'centimeter',
    name: 'Centímetros',
    symbol: 'cm',
    dimension: MeasurementDimension.length,
    baseUnitFactor: DecimalValue.scaled(10000),
  );

  test('compacta diámetro y alto con formato comercial', () {
    final text = formatter.dimensions(
      ProductDimensions(
        values: {
          'Diámetro': MeasuredQuantity(
            amount: DecimalValue.parse('20'),
            unitId: 'cm',
          ),
          'Alto': MeasuredQuantity(
            amount: DecimalValue.parse('18'),
            unitId: 'cm',
          ),
        },
      ),
      const [centimeter],
    );
    expect(text, 'Ø 20 × 18 cm');
  });

  test('muestra sólo materiales principales y resume variantes', () {
    final now = DateTime.utc(2026, 9, 3);
    final material = Material(
      metadata: SyncMetadata(id: 'm', createdAt: now, updatedAt: now),
      name: 'Cordón de algodón N°7',
      categoryId: 'cordones',
      purchase: PurchasePresentation(
        quantity: MeasuredQuantity(
          amount: DecimalValue.parse('1000'),
          unitId: 'g',
        ),
        price: const Money.ars(100000),
      ),
      consumptionUnitId: 'g',
    );
    final variant = MaterialVariant(
      metadata: SyncMetadata(id: 'v', createdAt: now, updatedAt: now),
      materialId: 'm',
      name: 'Natural',
    );
    final usages = [
      _usage(
        now,
        id: 'principal',
        role: ProductMaterialRole.primary,
        variant: 'v',
      ),
      _usage(now, id: 'avio', role: ProductMaterialRole.complementary),
    ];

    expect(
      formatter.primaryMaterials(
        usages: usages,
        materials: [material],
        variants: [variant],
      ),
      'Cordón de algodón N°7 · Natural',
    );
  });
}

ProductMaterialUsage _usage(
  DateTime now, {
  required String id,
  required ProductMaterialRole role,
  String? variant,
}) => ProductMaterialUsage(
  metadata: SyncMetadata(id: id, createdAt: now, updatedAt: now),
  productId: 'p',
  materialId: 'm',
  materialVariantId: variant,
  consumption: MeasuredQuantity(amount: DecimalValue.parse('1'), unitId: 'g'),
  role: role,
);
