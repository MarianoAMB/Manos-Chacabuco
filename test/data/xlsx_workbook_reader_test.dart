import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/data/importing/xlsx_workbook_reader.dart';
import 'package:manos_chacabuco/domain/importing/spreadsheet_models.dart';

void main() {
  test('lee valores y fórmulas del XLSX real sin Internet', () async {
    final fixture = File('work/precio_manos_chacabuco.xlsx');
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'El XLSX real debe quedar disponible para el dry run local.',
    );

    final workbook = const XlsxWorkbookReader().read(
      await fixture.readAsBytes(),
    );
    final sheet = workbook.sheetNamed('Hoja 1')!;
    final header = sheet.rows.firstWhere((row) => row.index == 1);
    final macetero = sheet.rows.firstWhere((row) => row.index == 30);

    expect(header.cell('A').text, 'Materia prima');
    expect(header.cell('E').text, 'Deco');
    expect(macetero.cell('E').text, 'Macetero 20x20 algodón y PPP');
    expect(macetero.cell('F').number, 400);
    expect(macetero.cell('G').formula, '=(F30*B6)/C6');
  });

  test(
    'interpreta coma decimal y miles argentinos sin romper decimales XLSX',
    () {
      expect(const SpreadsheetCell(value: '1910,23').number, 1910.23);
      expect(const SpreadsheetCell(value: '35.438,98').number, 35438.98);
      expect(const SpreadsheetCell(value: '1.5').number, 1.5);
    },
  );
}
