import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/data/repositories/sqlite_historical_import_repository.dart';
import 'package:manos_chacabuco/domain/importing/spreadsheet_models.dart';
import 'package:manos_chacabuco/features/importing/application/historical_import_controller.dart';
import 'package:manos_chacabuco/features/importing/presentation/historical_import_screen.dart';

import '../support/historical_import_fixture.dart';
import '../support/test_app_harness.dart';

void main() {
  testWidgets('muestra preview y solicita confirmación antes de importar', (
    tester,
  ) async {
    final harness = (await tester.runAsync(createTestAppHarness))!;
    addTearDown(harness.close);
    final temporary = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('historical-import-ui-'),
    ))!;
    addTearDown(() => temporary.delete(recursive: true));
    final source = File('${temporary.path}${Platform.pathSeparator}sheet.xlsx');
    await tester.runAsync(() => source.writeAsBytes(const [1]));
    final controller = HistoricalImportController(
      repository: SqliteHistoricalImportRepository(harness.database),
      workbookLoader: const _FixtureWorkbookLoader(),
      materialsController: harness.materialsController,
      productsController: harness.productsController,
      settingsController: harness.settingsController,
    );
    await tester.runAsync(() => controller.analyzeFile(source.path));

    await tester.pumpWidget(
      MaterialApp(home: HistoricalImportScreen(controller: controller)),
    );
    await tester.pump();

    expect(find.text('Resumen del análisis'), findsOneWidget);
    expect(find.text('Referencias para estimación'), findsOneWidget);
    expect(find.text('Comparación con la planilla'), findsOneWidget);
    expect(find.text('Importar datos seguros'), findsOneWidget);

    await tester.ensureVisible(find.text('Importar datos seguros'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Importar datos seguros'));
    await tester.pump();
    expect(find.text('¿Importar los datos seguros?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pump();
  });
}

final class _FixtureWorkbookLoader implements XlsxWorkbookLoader {
  const _FixtureWorkbookLoader();

  @override
  SpreadsheetWorkbook read(Uint8List bytes) => historicalImportFixture();
}
