import 'dart:typed_data';

final class SpreadsheetCell {
  const SpreadsheetCell({this.value, this.formula});

  final Object? value;
  final String? formula;

  bool get isEmpty => value == null && (formula == null || formula!.isEmpty);
  String? get text {
    final current = value;
    if (current == null) return null;
    final result = '$current'.trim();
    return result.isEmpty ? null : result;
  }

  double? get number {
    final current = value;
    if (current is num) return current.toDouble();
    if (current is! String) return null;
    final source = current.trim();
    if (source.contains(',')) {
      return double.tryParse(source.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(source);
  }
}

final class SpreadsheetRow {
  const SpreadsheetRow({required this.index, required this.cells});

  final int index;
  final Map<String, SpreadsheetCell> cells;

  SpreadsheetCell cell(String column) =>
      cells[column] ?? const SpreadsheetCell();
}

final class SpreadsheetSheet {
  const SpreadsheetSheet({required this.name, required this.rows});

  final String name;
  final List<SpreadsheetRow> rows;
}

final class SpreadsheetWorkbook {
  const SpreadsheetWorkbook({required this.sheets});

  final List<SpreadsheetSheet> sheets;

  SpreadsheetSheet? sheetNamed(String name) =>
      sheets.where((sheet) => sheet.name == name).firstOrNull;
}

abstract interface class XlsxWorkbookLoader {
  SpreadsheetWorkbook read(Uint8List bytes);
}
