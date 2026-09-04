import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/app/manos_chacabuco_app.dart';
import 'package:manos_chacabuco/core/design_system/components/app_file_image.dart';

import '../support/test_app_harness.dart';

void main() {
  testWidgets('Configuración advierte sólo cuando hay cambios sin guardar', (
    tester,
  ) async {
    await _mobileSurface(tester);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await _openMoreDestination(tester, 'Configuración');
    await tester.enterText(
      find.byKey(const Key('business-name-field')),
      'Nombre todavía no guardado',
    );
    await _tapMobileDestination(tester, 'Productos');

    expect(find.text('Tenés cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Configuración'), findsWidgets);
    expect(find.text('Nombre todavía no guardado'), findsOneWidget);

    await _tapMobileDestination(tester, 'Productos');
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no cargaste productos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Producto no se cierra por accidente después de editar', (
    tester,
  ) async {
    await _mobileSurface(tester);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await _tapMobileDestination(tester, 'Productos');
    final createProductButton = find.text('Crear primer producto');
    await tester.ensureVisible(createProductButton);
    await tester.tap(createProductButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-name')),
      'Producto pendiente',
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.text('Tenés cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Producto pendiente'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no cargaste productos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Presupuesto advierte antes de perder cambios', (tester) async {
    await _mobileSurface(tester);
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    await tester.pumpWidget(harness.app);
    await tester.pumpAndSettle();

    await _tapMobileDestination(tester, 'Presup.');
    await tester.tap(find.byKey(const Key('add-quote')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quote-customer')),
      'Cliente pendiente',
    );
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();

    expect(find.text('Tenés cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Salir sin guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no creaste presupuestos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una imagen dañada muestra reemplazo sin romper la pantalla', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('manos-image-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final corrupt = File('${directory.path}${Platform.pathSeparator}foto.jpg');
    corrupt.writeAsBytesSync([0, 1, 2, 3, 4]);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final fileImage = AppFileImage(
              path: corrupt.path,
              fallback: const ColoredBox(
                key: Key('image-fallback'),
                color: Colors.orange,
              ),
            ).build(context);
            expect(fileImage, isA<Image>());
            return (fileImage as Image).errorBuilder!(
              context,
              StateError('imagen dañada'),
              StackTrace.current,
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('image-fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el arranque y el error inicial usan mensajes comprensibles', (
    tester,
  ) async {
    await tester.pumpWidget(const BootstrapLoadingApp());
    expect(find.text('Preparando tus datos…'), findsOneWidget);

    await tester.pumpWidget(const BootstrapFailureApp());
    expect(find.text('No pudimos abrir tus datos locales'), findsOneWidget);
    expect(find.textContaining('SQLiteException'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mobileSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapMobileDestination(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMoreDestination(WidgetTester tester, String label) async {
  await _tapMobileDestination(tester, 'Más');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}
