import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/geometry/geometry_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('pieza nueva no inventa consumo y permite ingreso manual', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.runAsync(() async {
      final gram = harness.materialsController.units.firstWhere(
        (unit) => unit.code == 'gram',
      );
      await harness.materialsController.save(
        MaterialFormValue(
          name: 'Cordón nuevo',
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
          variants: const [],
        ),
      );
    });
    await tester.pumpWidget(harness.app);
    await _pumpUi(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Más'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculadora').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calculator-mode-newPiece')));
    await tester.pumpAndSettle();
    expect(find.text('Materia prima principal'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'formulario de pieza nueva');

    await tester.enterText(
      find.byKey(const Key('calculator-measure-diameter')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('calculator-measure-height')),
      '20',
    );
    await tester.enterText(find.byKey(const Key('calculator-multiplier')), '2');
    final material = find.byKey(const Key('calculator-material'));
    await tester.ensureVisible(material);
    await tester.tap(material);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cordón nuevo').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'selección de material');

    final calculate = find.byKey(const Key('calculate-new-piece'));
    await tester.ensureVisible(calculate);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No tenemos suficientes referencias'),
      findsOneWidget,
    );
    expect(find.text('Resultado'), findsNothing);
    expect(tester.takeException(), isNull, reason: 'sin referencias');

    final manual = find.byKey(const Key('calculator-manual-consumption'));
    await tester.ensureVisible(manual);
    await tester.enterText(manual, '400');
    await tester.ensureVisible(calculate);
    await tester.tap(calculate);
    await tester.pumpAndSettle();
    expect(find.text('Resultado'), findsOneWidget);
    expect(find.textContaining('≈ 400 g'), findsOneWidget);
    expect(find.text('Consumo ingresado manualmente'), findsOneWidget);
    expect(find.byKey(const Key('calculator-create-product')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'resultado manual');
  });

  testWidgets('producto sólo aplica la estimación después de confirmar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.runAsync(() async {
      final gram = harness.materialsController.units.firstWhere(
        (unit) => unit.code == 'gram',
      );
      final centimeter = harness.materialsController.units.firstWhere(
        (unit) => unit.code == 'centimeter',
      );
      await harness.materialsController.save(
        MaterialFormValue(
          name: 'Cordón referencia',
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
          variants: const [],
        ),
      );
      await harness.productsController.save(
        ProductFormValue(
          name: 'Cesto referencia',
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
              materialId: harness
                  .materialsController
                  .materials
                  .single
                  .material
                  .metadata
                  .id,
              consumption: MeasuredQuantity(
                amount: DecimalValue.parse('400'),
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
    await _pumpUi(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Productos'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cesto referencia').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Editar'));
    await tester.pumpAndSettle();

    final heightMeasure = find.byKey(const Key('edit-product-measure-1'));
    await tester.ensureVisible(heightMeasure);
    await tester.tap(heightMeasure);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-measure-amount')),
      '32,5',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar').last);
    await tester.pumpAndSettle();

    final estimateButton = find.byKey(const Key('estimate-product-material'));
    await tester.ensureVisible(estimateButton);
    await tester.tap(estimateButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('≈ 600 g'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar').last);
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
      DecimalValue.parse('400'),
    );

    await tester.ensureVisible(estimateButton);
    await tester.tap(estimateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply-material-estimation')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('save-product'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
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
      DecimalValue.parse('600'),
    );
    expect(
      harness
          .productsController
          .products
          .single
          .usages
          .single
          .consumptionSource,
      ConsumptionSource.estimated,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}
