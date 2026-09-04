import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/design_system/components/app_empty_state.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('crea una materia prima desde el flujo móvil', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);

    await tester.pumpWidget(harness.app);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Materias'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('No cargaste materias primas todavía'), findsOneWidget);
    final addMaterialAction = find.descendant(
      of: find.byType(AppEmptyState),
      matching: find.text('Agregar materia prima'),
    );
    await tester.ensureVisible(addMaterialAction);
    await tester.pump();
    await tester.tap(addMaterialAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Nueva materia prima'), findsOneWidget);
    expect(find.text('Costo calculado'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(_fieldWithLabel('Nombre'), 'Cordón de prueba');
    await tester.enterText(_fieldWithLabel('Precio de compra'), '35.000');
    await tester.enterText(_fieldWithLabel('Cantidad comprada'), '2.100');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(harness.materialsController.activeCount, 1);
    expect(find.text('Cordón de prueba'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Finder _fieldWithLabel(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextFormField));
