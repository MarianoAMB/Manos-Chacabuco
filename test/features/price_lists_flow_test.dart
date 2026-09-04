import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/decimal_value.dart';
import 'package:manos_chacabuco/features/price_lists/presentation/price_lists_screen.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('abre Minorista, selecciona, cambia opciones y exporta', (
    tester,
  ) async {
    await _setSurface(tester, const Size(390, 844));
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.runAsync(() => _seedProducts(harness, count: 10));

    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Más'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Listas de precios').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('create-retail-list')));
    await tester.tap(find.byKey(const Key('create-retail-list')));
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 50; attempt++) {
        if (harness.priceListsController.config != null) return;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(find.text('Lista Minorista'), findsWidgets);
    expect(find.text('10 productos listos para exportar'), findsOneWidget);
    expect(find.text('Vista previa'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('export-price-list')));
    await tester.tap(find.byKey(const Key('export-price-list')));
    await tester.pumpAndSettle();
    expect(find.text('Con fotos'), findsOneWidget);
    expect(find.text('Sin fotos'), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-style-no-photos')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(harness.priceListsController.config?.showPhotos, isFalse);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Sin foto'), findsNothing);
    await tester.tap(find.byKey(const Key('export-price-list-pdf')));
    await tester.pumpAndSettle();
    expect(find.text('PDF guardado correctamente.'), findsOneWidget);

    await tester.runAsync(harness.priceListsController.sharePdf);
    expect(harness.shareService.lastFiles, hasLength(1));
    expect(harness.shareService.lastFiles.single.mimeType, 'application/pdf');

    await tester.runAsync(harness.priceListsController.shareImages);
    expect(harness.shareService.lastFiles, hasLength(2));
    expect(
      harness.shareService.lastFiles.map((file) => file.mimeType),
      everyElement('image/png'),
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 700),
    Size(390, 844),
    Size(1024, 768),
    Size(1440, 900),
  ]) {
    testWidgets('editor de lista no desborda en ${size.width.toInt()} px', (
      tester,
    ) async {
      await _setSurface(tester, size);
      final harness = (await tester.runAsync(createTestAppHarness))!;
      addTearDown(harness.close);
      await tester.runAsync(() => _seedProducts(harness, count: 4));
      await tester.runAsync(
        () => harness.priceListsController.start(PriceListType.wholesale),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PriceListsScreen(
            controller: harness.priceListsController,
            onOpenProducts: () {},
            onOpenSettings: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lista Mayorista'), findsWidgets);
      expect(find.text('Vista previa'), findsOneWidget);
      expect(find.text('Producto artesanal 1'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _seedProducts(TestAppHarness harness, {required int count}) async {
  final database = harness.database.database;
  final materialCategory = (await database.query(
    'material_categories',
    where: 'name = ?',
    whereArgs: ['Cordones'],
  )).single;
  final productCategory = (await database.query(
    'product_categories',
    where: 'name = ?',
    whereArgs: ['Maceteros'],
  )).single;
  final gram = (await database.query(
    'measurement_units',
    where: 'code = ?',
    whereArgs: ['gram'],
  )).single;
  final centimeter = (await database.query(
    'measurement_units',
    where: 'code = ?',
    whereArgs: ['centimeter'],
  )).single;
  final now = DateTime.utc(2026, 9, 3).toIso8601String();
  await database.insert('materials', {
    'id': 'price-list-material',
    'category_id': materialCategory['id'],
    'name': 'Cordón de algodón N°7',
    'purchase_quantity_scaled': DecimalValue.parse('1000').scaledValue,
    'purchase_unit_id': gram['id'],
    'purchase_price_minor': 100000,
    'currency': 'ARS',
    'consumption_unit_id': gram['id'],
    'is_active': 1,
    'created_at': now,
    'updated_at': now,
  });
  for (var index = 1; index <= count; index++) {
    await database.insert('products', {
      'id': 'price-list-product-$index',
      'category_id': productCategory['id'],
      'name': 'Producto artesanal $index',
      'dimensions_json':
          '{"Diámetro":{"amount":20000000,"unit":"${centimeter['id']}"}}',
      'price_multiplier_scaled': DecimalValue.parse('2.4').scaledValue,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await database.insert('product_material_usages', {
      'id': 'price-list-usage-$index',
      'product_id': 'price-list-product-$index',
      'material_id': 'price-list-material',
      'amount_scaled': DecimalValue.parse('${100 + index}').scaledValue,
      'unit_id': gram['id'],
      'role': 'primary',
      'consumption_source': 'confirmed',
      'calibration_eligible': 1,
      'created_at': now,
      'updated_at': now,
    });
  }
  await harness.settingsController.save(
    harness.settingsController.settings.copyWith(
      defaultRetailPercentage: DecimalValue.percent('25'),
      updatedAt: DateTime.utc(2026, 9, 3),
    ),
  );
  await harness.materialsController.load();
  await harness.productsController.load();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
