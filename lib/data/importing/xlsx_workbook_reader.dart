import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../domain/importing/spreadsheet_models.dart';

final class XlsxWorkbookReader implements XlsxWorkbookLoader {
  const XlsxWorkbookReader();

  @override
  SpreadsheetWorkbook read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _sharedStrings(archive);
    final workbook = _xml(archive, 'xl/workbook.xml');
    final relationships = _relationshipTargets(archive);
    final sheets = <SpreadsheetSheet>[];

    for (final sheet in _elements(workbook, 'sheet')) {
      final name = sheet.getAttribute('name');
      final relationshipId = sheet.attributes
          .where((attribute) => attribute.name.local == 'id')
          .map((attribute) => attribute.value)
          .firstOrNull;
      final target = relationshipId == null
          ? null
          : relationships[relationshipId];
      if (name == null || target == null) continue;
      final normalizedTarget = target.startsWith('/')
          ? target.substring(1)
          : target.startsWith('xl/')
          ? target
          : 'xl/$target';
      final sheetXml = _xml(archive, normalizedTarget);
      sheets.add(
        SpreadsheetSheet(name: name, rows: _readRows(sheetXml, sharedStrings)),
      );
    }
    return SpreadsheetWorkbook(sheets: sheets);
  }

  Map<String, String> _relationshipTargets(Archive archive) {
    final document = _xml(archive, 'xl/_rels/workbook.xml.rels');
    return {
      for (final relationship in _elements(document, 'Relationship'))
        if (relationship.getAttribute('Id') != null &&
            relationship.getAttribute('Target') != null)
          relationship.getAttribute('Id')!: relationship.getAttribute(
            'Target',
          )!,
    };
  }

  List<String> _sharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final document = XmlDocument.parse(utf8.decode(_bytes(file)));
    return [
      for (final item in _elements(document, 'si'))
        _elements(item, 't').map((element) => element.innerText).join(),
    ];
  }

  List<SpreadsheetRow> _readRows(
    XmlDocument document,
    List<String> sharedStrings,
  ) {
    final rows = <SpreadsheetRow>[];
    for (final rowElement in _elements(document, 'row')) {
      final rowIndex = int.tryParse(rowElement.getAttribute('r') ?? '');
      if (rowIndex == null) continue;
      final cells = <String, SpreadsheetCell>{};
      for (final cellElement in rowElement.children.whereType<XmlElement>()) {
        if (cellElement.name.local != 'c') continue;
        final coordinate = cellElement.getAttribute('r');
        if (coordinate == null) continue;
        final column = RegExp(r'^[A-Z]+').firstMatch(coordinate)?.group(0);
        if (column == null) continue;
        final type = cellElement.getAttribute('t');
        final formula = _firstChildText(cellElement, 'f');
        final rawValue = _firstChildText(cellElement, 'v');
        final inline = _elements(
          cellElement,
          't',
        ).map((element) => element.innerText).join();
        final value = _decodeValue(
          type: type,
          rawValue: rawValue,
          inlineValue: inline,
          sharedStrings: sharedStrings,
        );
        cells[column] = SpreadsheetCell(
          value: value,
          formula: formula == null ? null : '=$formula',
        );
      }
      if (cells.values.any((cell) => !cell.isEmpty)) {
        rows.add(SpreadsheetRow(index: rowIndex, cells: cells));
      }
    }
    return rows;
  }

  Object? _decodeValue({
    required String? type,
    required String? rawValue,
    required String inlineValue,
    required List<String> sharedStrings,
  }) {
    if (type == 'inlineStr') return inlineValue;
    if (rawValue == null) return inlineValue.isEmpty ? null : inlineValue;
    if (type == 's') {
      final index = int.tryParse(rawValue);
      return index == null || index < 0 || index >= sharedStrings.length
          ? rawValue
          : sharedStrings[index];
    }
    if (type == 'str' || type == 'e') return rawValue;
    if (type == 'b') return rawValue == '1';
    return num.tryParse(rawValue) ?? rawValue;
  }

  XmlDocument _xml(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) throw FormatException('Falta $name dentro del XLSX.');
    return XmlDocument.parse(utf8.decode(_bytes(file)));
  }

  Uint8List _bytes(ArchiveFile file) => file.content;

  String? _firstChildText(XmlElement element, String localName) => element
      .children
      .whereType<XmlElement>()
      .where((child) => child.name.local == localName)
      .map((child) => child.innerText)
      .firstOrNull;

  Iterable<XmlElement> _elements(XmlNode node, String localName) => node
      .descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName);
}
