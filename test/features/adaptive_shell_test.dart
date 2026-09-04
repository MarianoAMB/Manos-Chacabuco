import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app_harness.dart';

void main() {
  for (final size in const [Size(320, 700), Size(390, 844), Size(768, 900)]) {
    testWidgets('se adapta sin desbordes en móvil ${size.width.toInt()} px', (
      tester,
    ) async {
      await _setSurface(tester, size);
      final harness = (await tester.runAsync(createTestAppHarness))!;
      addTearDown(harness.close);

      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('¿Qué querés hacer?'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Más'),
        ),
      );
      await _pumpTransition(tester, milliseconds: 300);
      await tester.tap(find.text('Listas de precios').last);
      await _pumpTransition(tester);
      expect(find.text('Crear lista minorista'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Productos'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Todavía no cargaste productos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Materias'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Materias primas'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Presup.'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Todavía no creaste presupuestos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Más'),
        ),
      );
      await _pumpTransition(tester, milliseconds: 300);
      await tester.tap(find.text('Calculadora').last);
      await _pumpTransition(tester);
      expect(find.text('¿Qué querés calcular?'), findsOneWidget);
      expect(
        find.text('Todavía no hay productos de referencia'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Más'),
        ),
      );
      await _pumpTransition(tester, milliseconds: 300);
      await tester.tap(find.text('Configuración'));
      await _pumpTransition(tester);
      expect(find.text('Cálculos y precios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [Size(1024, 768), Size(1440, 900)]) {
    testWidgets('se adapta sin desbordes en Windows ${size.width.toInt()} px', (
      tester,
    ) async {
      await _setSurface(tester, size);
      final harness = (await tester.runAsync(createTestAppHarness))!;
      addTearDown(harness.close);

      await tester.pumpWidget(harness.app);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Listas de precios'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Listas de precios'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Crear lista mayorista'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Productos'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Todavía no cargaste productos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Materias primas'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('No cargaste materias primas todavía'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Presupuestos'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Todavía no creaste presupuestos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Calculadora'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('¿Qué querés calcular?'), findsOneWidget);
      expect(
        find.text('Todavía no hay productos de referencia'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Configuración'),
        ),
      );
      await _pumpTransition(tester);
      expect(find.text('Cálculos y precios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _pumpTransition(
  WidgetTester tester, {
  int milliseconds = 500,
}) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: milliseconds));
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
