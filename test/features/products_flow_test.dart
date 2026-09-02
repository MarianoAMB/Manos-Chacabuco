import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('crea un producto y muestra su precio en el flujo móvil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    final meter = harness.materialsController.units.firstWhere(
      (unit) => unit.code == 'meter',
    );
    await tester.runAsync(
      () => harness.materialsController.save(
        MaterialFormValue(
          name: 'Cordón de prueba',
          categoryId: harness.materialsController.categories.first.metadata.id,
          purchase: PurchasePresentation(
            quantity: MeasuredQuantity(
              amount: DecimalValue.parse('10'),
              unitId: meter.id,
            ),
            price: const Money.ars(100000),
          ),
          consumptionUnitId: meter.id,
          isActive: true,
          variants: const [],
        ),
      ),
    );

    await tester.pumpWidget(harness.app);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Productos'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Todavía no cargaste productos'), findsOneWidget);

    final createProduct = find.text('Crear primer producto');
    await tester.ensureVisible(createProduct);
    await tester.tap(createProduct);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nuevo producto'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('product-name')),
      'Cesto móvil',
    );
    await tester.enterText(find.byKey(const Key('product-multiplier')), '2');

    final addMaterial = find.byKey(const Key('add-product-material'));
    await tester.ensureVisible(addMaterial);
    await tester.tap(addMaterial);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('usage-material')));
    await tester.pump();
    await tester.tap(find.text('Cordón de prueba').last);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('usage-amount')), '2');
    await tester.tap(find.byKey(const Key('save-product-material')));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('save-product')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(harness.productsController.activeCount, 1);
    expect(find.text('Cesto móvil'), findsWidgets);
    expect(find.textContaining('Mayorista'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
