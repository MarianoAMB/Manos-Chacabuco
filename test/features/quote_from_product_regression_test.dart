import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/domain/materials/material_models.dart';
import 'package:manos_chacabuco/domain/products/product_models.dart';
import 'package:manos_chacabuco/features/materials/application/material_form_value.dart';
import 'package:manos_chacabuco/features/products/application/product_form_value.dart';

import '../support/test_app_harness.dart';

const _captureAuditScreenshots = bool.fromEnvironment('CAPTURE_UX_AUDIT');

void main() {
  testWidgets(
    'Windows: presupuesto desde producto muestra errores dentro del modal y permite completar el flujo',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = (await tester.runAsync(
        () => createTestAppHarness(quoteNow: () => DateTime.utc(2026, 9, 4)),
      ))!;
      addTearDown(harness.close);
      await tester.runAsync(() => _seedProduct(harness));

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Productos'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panera de prueba').last);
      await tester.pumpAndSettle();
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/product_detail_windows.png'),
        );
      }
      final detailException = tester.takeException();
      expect(detailException, isNull, reason: 'detalle del producto');
      await tester.tap(find.byKey(const Key('create-quote-from-product')));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'apertura del presupuesto',
      );
      expect(find.text('Nuevo presupuesto'), findsWidgets);
      expect(find.byKey(const Key('quote-price-warning')), findsOneWidget);
      expect(find.textContaining('No hay precio minorista'), findsOneWidget);

      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quote_customer_error_windows.png'),
        );
      }
      expect(find.byKey(const Key('quote-dialog-error')), findsOneWidget);
      expect(
        find.text('Falta el nombre del cliente para continuar.'),
        findsOneWidget,
      );
      expect(find.text('1 de 3 · Datos'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('quote-customer')),
        'María Gómez',
      );
      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(find.text('2 de 3 · Productos'), findsOneWidget);
      expect(find.byKey(const Key('quote-item-error-0')), findsOneWidget);
      expect(find.textContaining('No hay precio minorista'), findsOneWidget);

      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(find.text('2 de 3 · Productos'), findsOneWidget);
      expect(find.byKey(const Key('quote-dialog-error')), findsOneWidget);
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quote_missing_retail_windows.png'),
        );
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'precio minorista faltante',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Usar mayorista').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'cambio a mayorista');
      expect(find.byKey(const Key('quote-item-error-0')), findsNothing);
      expect(find.textContaining('c/u'), findsOneWidget);

      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'resumen');
      expect(find.text('3 de 3 · Resumen'), findsOneWidget);
      expect(find.text('Revisar datos'), findsNothing);
      expect(find.byKey(const Key('quote-total')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save-quote')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pumpAndSettle();
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quote_list_windows.png'),
        );
      }
      expect(tester.takeException(), isNull, reason: 'guardado');
      expect(harness.quotesController.quotes, hasLength(1));
    },
  );

  testWidgets(
    'el editor del ítem conserva los datos del producto y explica el único dato faltante',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = (await tester.runAsync(createTestAppHarness))!;
      addTearDown(harness.close);
      await tester.runAsync(() => _seedProduct(harness));

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Productos'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panera de prueba').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-quote-from-product')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quote-customer')),
        'María Gómez',
      );
      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Personalizar'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quote-item-name')))
            .controller!
            .text,
        'Panera de prueba',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quote-item-quantity')))
            .controller!
            .text,
        '1',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quote-item-multiplier')))
            .controller!
            .text,
        '2.00',
      );
      expect(find.text('Cordón de prueba'), findsOneWidget);
      final calculationError = find.byKey(
        const Key('quote-item-calculation-error'),
      );
      await tester.ensureVisible(calculationError);
      expect(calculationError, findsOneWidget);
      expect(
        tester.widget<Text>(calculationError).data,
        contains('falta definir el porcentaje minorista'),
      );
      expect(
        find.textContaining(
          'Completá nombre, cantidad, materiales y multiplicador',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android: el mismo presupuesto desde producto mantiene visibles los errores y el precio',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = (await tester.runAsync(
        () => createTestAppHarness(quoteNow: () => DateTime.utc(2026, 9, 4)),
      ))!;
      addTearDown(harness.close);
      await tester.runAsync(() => _seedProduct(harness));

      await tester.pumpWidget(harness.app);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Productos'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Panera de prueba').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-quote-from-product')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quote-dialog-error')), findsOneWidget);
      expect(find.text('1 de 3 · Datos'), findsOneWidget);
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quote_customer_error_mobile.png'),
        );
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'error visible en Android',
      );

      await tester.enterText(
        find.byKey(const Key('quote-customer')),
        'María Gómez',
      );
      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(find.text('2 de 3 · Productos'), findsOneWidget);
      expect(find.byKey(const Key('quote-dialog-error')), findsOneWidget);
      if (_captureAuditScreenshots) {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/quote_missing_retail_mobile.png'),
        );
      }
      expect(
        tester.takeException(),
        isNull,
        reason: 'precio minorista faltante en Android',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Usar mayorista').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'mayorista en Android');
      await tester.tap(find.byKey(const Key('next-quote-step')));
      await tester.pumpAndSettle();
      expect(find.text('3 de 3 · Resumen'), findsOneWidget);
      expect(find.text('Revisar datos'), findsNothing);
      expect(find.byKey(const Key('quote-total')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}


Future<void> _seedProduct(TestAppHarness harness) async {
  final gram = harness.materialsController.units.firstWhere(
    (unit) => unit.code == 'gram',
  );
  await harness.materialsController.save(
    MaterialFormValue(
      name: 'Cordón de prueba',
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
  final materialId =
      harness.materialsController.materials.single.material.metadata.id;
  await harness.productsController.save(
    ProductFormValue(
      name: 'Panera de prueba',
      categoryId: harness.productsController.categories.first.metadata.id,
      priceMultiplier: DecimalValue.parse('2'),
      usages: [
        ProductUsageFormValue(
          materialId: materialId,
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
}
