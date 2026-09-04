import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('crea, abre y duplica un presupuesto en el flujo móvil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    late String gramId;
    late String centimeterId;
    late String materialId;
    late String naturalId;
    late String blackId;

    await tester.runAsync(() async {
      await harness.settingsController.save(
        harness.settingsController.settings.copyWith(
          defaultProductMultiplier: DecimalValue.parse('2'),
          defaultRetailPercentage: DecimalValue.percent('20'),
          updatedAt: DateTime.utc(2026, 9, 2),
        ),
      );
      final gram = harness.materialsController.units.firstWhere(
        (unit) => unit.code == 'gram',
      );
      final centimeter = harness.materialsController.units.firstWhere(
        (unit) => unit.code == 'centimeter',
      );
      gramId = gram.id;
      centimeterId = centimeter.id;
      await harness.materialsController.save(
        MaterialFormValue(
          name: 'Cordón para cotizar',
          categoryId: harness.materialsController.categories.first.metadata.id,
          purchase: PurchasePresentation(
            quantity: MeasuredQuantity(
              amount: DecimalValue.parse('1000'),
              unitId: gram.id,
            ),
            price: const Money.ars(1000000),
          ),
          consumptionUnitId: gram.id,
          isActive: true,
          variants: [
            VariantFormValue(
              name: 'Natural',
              purchase: PurchasePresentation(
                quantity: MeasuredQuantity(
                  amount: DecimalValue.parse('1000'),
                  unitId: gram.id,
                ),
                price: const Money.ars(1000000),
              ),
              isActive: true,
            ),
            VariantFormValue(
              name: 'Negro',
              purchase: PurchasePresentation(
                quantity: MeasuredQuantity(
                  amount: DecimalValue.parse('1000'),
                  unitId: gram.id,
                ),
                price: const Money.ars(1200000),
              ),
              isActive: true,
            ),
          ],
        ),
      );
      final material = harness.materialsController.materials.single;
      materialId = material.material.metadata.id;
      naturalId = material.variants
          .firstWhere((variant) => variant.name == 'Natural')
          .metadata
          .id;
      blackId = material.variants
          .firstWhere((variant) => variant.name == 'Negro')
          .metadata
          .id;
      await harness.productsController.save(
        ProductFormValue(
          name: 'Panera mediana',
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
            components: const {
              GeometryComponent.base,
              GeometryComponent.lateral,
            },
            dimensionBindings: const {
              GeometryParameters.diameter: 'Diámetro',
              GeometryParameters.height: 'Alto',
            },
          ),
          priceMultiplier: DecimalValue.parse('2'),
          usages: [
            ProductUsageFormValue(
              materialId: materialId,
              materialVariantId: naturalId,
              consumption: MeasuredQuantity(
                amount: DecimalValue.parse('200'),
                unitId: gram.id,
              ),
              role: ProductMaterialRole.primary,
              consumptionSource: ConsumptionSource.confirmed,
            ),
          ],
        ),
      );
    });

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Presup.'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Todavía no creaste presupuestos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-quote')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'alta paso Datos');
    await tester.enterText(
      find.byKey(const Key('quote-customer')),
      'Decoraciones Luna',
    );
    await tester.enterText(find.byKey(const Key('quote-validity-days')), '15');
    await tester.pump();
    final expectedValidUntil = harness.quotesController.engine
        .calculateValidUntil(harness.quotesController.today, 15);
    expect(find.textContaining(_date(expectedValidUntil)), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-quote-step')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'alta paso Productos');

    await tester.tap(find.byKey(const Key('quote-add-from-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Panera mediana').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'editor de ítem');
    await tester.enterText(find.byKey(const Key('quote-item-quantity')), '3');

    final heightMeasure = find.text('Alto');
    await tester.ensureVisible(heightMeasure);
    await tester.tap(heightMeasure);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quote-measure-amount')), '25');
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Cambiaste las medidas. Revisá el consumo de materiales.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull, reason: 'edición de medida');

    final estimateConsumption = find.byKey(
      const Key('estimate-quote-item-material'),
    );
    await tester.ensureVisible(estimateConsumption);
    await tester.tap(estimateConsumption);
    await tester.pumpAndSettle();
    expect(find.textContaining('≈ 240 g'), findsOneWidget);
    await tester.tap(find.byKey(const Key('apply-material-estimation')));
    await tester.pumpAndSettle();
    expect(
      harness
          .productsController
          .products
          .single
          .usages
          .single
          .consumption
          .amount,
      DecimalValue.parse('200'),
    );

    final materialLine = find.textContaining('Cordón para cotizar').last;
    await tester.ensureVisible(materialLine);
    await tester.tap(materialLine);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('usage-variant')));
    await tester.pump();
    await tester.tap(find.text('Negro').last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-product-material')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Negro'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'cambio de variante');

    final addAdjustment = find.byKey(const Key('quote-item-add-adjustment'));
    await tester.ensureVisible(addAdjustment);
    await tester.tap(addAdjustment);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('adjustment-description')),
      'Tapa especial',
    );
    await tester.enterText(find.byKey(const Key('adjustment-amount')), '2500');
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').last);
    await tester.pumpAndSettle();
    expect(find.text('Tapa especial'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'ajuste adicional');

    final saveItem = find.byKey(const Key('save-quote-item'));
    await tester.ensureVisible(saveItem);
    await tester.tap(saveItem);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 unidades'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-quote-step')));
    await tester.pumpAndSettle();
    final summaryException = tester.takeException();
    if (summaryException is FlutterError) {
      debugPrint(summaryException.toStringDeep());
    }
    expect(summaryException, isNull, reason: 'alta paso Resumen');
    expect(find.byKey(const Key('quote-total')), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-quote')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'listado guardado');

    expect(harness.quotesController.quotes, hasLength(1));
    final historicalTotal = harness.quotesController.quotes.single.quote.total;

    await tester.runAsync(() async {
      final material = harness.materialsController.materials.single.material;
      await harness.materialsController.save(
        MaterialFormValue(
          id: materialId,
          name: material.name,
          categoryId: material.categoryId,
          purchase: PurchasePresentation(
            quantity: MeasuredQuantity(
              amount: DecimalValue.parse('1000'),
              unitId: gramId,
            ),
            price: const Money.ars(2000000),
          ),
          consumptionUnitId: gramId,
          isActive: true,
          variants: [
            VariantFormValue(
              id: naturalId,
              name: 'Natural',
              purchase: PurchasePresentation(
                quantity: MeasuredQuantity(
                  amount: DecimalValue.parse('1000'),
                  unitId: gramId,
                ),
                price: const Money.ars(2000000),
              ),
              isActive: true,
            ),
            VariantFormValue(
              id: blackId,
              name: 'Negro',
              purchase: PurchasePresentation(
                quantity: MeasuredQuantity(
                  amount: DecimalValue.parse('1000'),
                  unitId: gramId,
                ),
                price: const Money.ars(2400000),
              ),
              isActive: true,
            ),
          ],
        ),
      );
    });
    await tester.pump();
    expect(harness.quotesController.quotes.single.quote.total, historicalTotal);
    expect(find.text('Decoraciones Luna'), findsWidgets);
    await tester.tap(find.text('Decoraciones Luna').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'detalle');
    expect(find.text('Válido hasta'), findsOneWidget);
    expect(find.text('15 días'), findsOneWidget);
    expect(find.byKey(const Key('quote-detail-total')), findsOneWidget);

    final recalculate = find.byKey(const Key('recalculate-quote'));
    await tester.ensureVisible(recalculate);
    await tester.tap(recalculate);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Comparar'));
    await tester.pumpAndSettle();
    expect(find.text('Total cotizado'), findsOneWidget);
    expect(find.text('Nuevo total'), findsOneWidget);
    await tester.tap(find.byKey(const Key('apply-recalculation')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(
      harness.quotesController.quotes.single.quote.total,
      isNot(historicalTotal),
    );

    await tester.tap(find.text('3 × Panera mediana'));
    await tester.pumpAndSettle();
    final convert = find.text('Guardar como producto');
    await tester.ensureVisible(convert);
    await tester.tap(convert);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revisar producto'));
    await tester.pumpAndSettle();
    final saveProduct = find.byKey(const Key('save-product'));
    await tester.ensureVisible(saveProduct);
    await tester.tap(saveProduct);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(harness.productsController.products, hasLength(2));
    expect(
      harness.productsController.products
          .where((item) => item.product.name == 'Panera mediana')
          .length,
      2,
    );
    expect(
      harness.productsController.products
          .where((item) => item.product.dimensions != null)
          .any(
            (item) =>
                item.product.dimensions!.values['Alto']?.amount ==
                DecimalValue.parse('25'),
          ),
      isTrue,
    );
    expect(centimeterId, isNotEmpty);

    final duplicate = find.byKey(const Key('duplicate-quote'));
    await tester.ensureVisible(duplicate);
    await tester.tap(duplicate);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'editor del duplicado');
    expect(find.text('Editar presupuesto'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15'), findsWidgets);
    expect(harness.quotesController.quotes, hasLength(2));
  });
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
