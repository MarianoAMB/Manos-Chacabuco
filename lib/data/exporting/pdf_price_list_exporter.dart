// ignore_for_file: prefer_initializing_formals

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

import '../../core/formatting/argentine_number_formatter.dart';
import '../../domain/price_lists/price_list_models.dart';
import '../../domain/repositories/price_list_exporters.dart';
import '../../domain/services/price_list_file_namer.dart';
import '../../domain/services/price_list_paginator.dart';

final class PdfPriceListExporter implements PriceListPdfExporter {
  const PdfPriceListExporter({
    PriceListPaginator paginator = const PriceListPaginator(),
    PriceListFileNamer fileNamer = const PriceListFileNamer(),
  }) : _paginator = paginator,
       _fileNamer = fileNamer;

  final PriceListPaginator _paginator;
  final PriceListFileNamer _fileNamer;

  static final _ink = PdfColor.fromHex('#2B2522');
  static final _muted = PdfColor.fromHex('#6E625C');
  static final _canvas = PdfColor.fromHex('#FAF7F2');
  static final _surface = PdfColor.fromHex('#FFFDFC');
  static final _terracotta = PdfColor.fromHex('#985343');
  static final _terracottaSoft = PdfColor.fromHex('#F3DDD6');
  static final _sageSoft = PdfColor.fromHex('#DDE8DE');
  static final _outline = PdfColor.fromHex('#E4DBD2');

  @override
  Future<GeneratedPriceListFile> export(PriceListDocument document) async {
    final pages = _paginator.paginate(
      document,
      target: PriceListRenderTarget.pdf,
    );
    if (pages.isEmpty) {
      throw StateError('Elegí al menos un producto con precio.');
    }
    final pdf = pw.Document(
      title: '${document.businessName} - ${document.type.title}',
      author: document.businessName,
      creator: 'Manos Chacabuco',
    );
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final logo = await _loadImage(document.logoPath, maxWidth: 360);
    for (final page in pages) {
      final photos = <String, pw.ImageProvider?>{};
      if (document.showPhotos) {
        for (final item in page.items) {
          final path = item.photoPath;
          if (path != null && !photos.containsKey(path)) {
            photos[path] = await _loadImage(path, maxWidth: 720);
          }
        }
      }
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 26),
          theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
          build: (_) => pw.Container(
            color: _canvas,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _header(document, logo),
                if (document.wholesaleMinimum != null) ...[
                  pw.SizedBox(height: 8),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _sageSoft,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Compra mínima mayorista: ${ArgentineNumberFormatter.commercialMoney(document.wholesaleMinimum!)}',
                      style: pw.TextStyle(
                        color: _ink,
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                pw.SizedBox(height: 13),
                pw.Expanded(
                  child: document.showPhotos
                      ? _photoContent(page, photos)
                      : _editorialContent(page),
                ),
                _footer(document, page.number, pages.length),
              ],
            ),
          ),
        ),
      );
    }
    final bytes = await pdf.save();
    return GeneratedPriceListFile(
      name: _fileNamer.pdf(document),
      mimeType: 'application/pdf',
      bytes: bytes,
      pageCount: pages.length,
    );
  }

  pw.Widget _header(PriceListDocument document, pw.ImageProvider? logo) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) ...[
            pw.Container(
              width: 52,
              height: 52,
              decoration: pw.BoxDecoration(
                color: _surface,
                borderRadius: pw.BorderRadius.circular(12),
                border: pw.Border.all(color: _outline),
              ),
              padding: const pw.EdgeInsets.all(5),
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 13),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  document.businessName.toUpperCase(),
                  style: pw.TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  document.type.title,
                  style: pw.TextStyle(
                    color: _terracotta,
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (document.showUpdatedDate)
            pw.Text(
              'Actualizado: ${_date(document.generatedAt)}',
              style: pw.TextStyle(color: _muted, fontSize: 9),
            ),
        ],
      );

  pw.Widget _photoContent(
    PriceListPage page,
    Map<String, pw.ImageProvider?> photos,
  ) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final group in page.groups) ...[
        if (group.name != null) _category(group.name!),
        pw.Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in group.items)
              _photoCard(
                item,
                item.photoPath == null ? null : photos[item.photoPath],
              ),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
    ],
  );

  pw.Widget _photoCard(PriceListItem item, pw.ImageProvider? photo) =>
      pw.Container(
        width: 253,
        height: 180,
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          color: _surface,
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: _outline),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              height: 88,
              decoration: pw.BoxDecoration(
                color: _terracottaSoft,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: photo == null
                  ? pw.Center(
                      child: pw.Text(
                        'Sin foto',
                        style: pw.TextStyle(
                          color: _terracotta,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    )
                  : pw.ClipRRect(
                      horizontalRadius: 8,
                      verticalRadius: 8,
                      child: pw.Image(photo, fit: pw.BoxFit.cover),
                    ),
            ),
            pw.SizedBox(height: 7),
            pw.Text(
              item.name,
              maxLines: 1,
              style: pw.TextStyle(
                color: _ink,
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (_details(item) case final String details) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                details,
                maxLines: 1,
                style: pw.TextStyle(color: _muted, fontSize: 8),
              ),
            ],
            pw.Spacer(),
            pw.Text(
              ArgentineNumberFormatter.commercialMoney(item.price),
              style: pw.TextStyle(
                color: _terracotta,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );

  pw.Widget _editorialContent(PriceListPage page) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < 2; index++) ...[
        pw.Expanded(
          child: index < page.editorialColumns.length
              ? _editorialColumn(page.editorialColumns[index])
              : pw.SizedBox(),
        ),
        if (index == 0) pw.SizedBox(width: 22),
      ],
    ],
  );

  pw.Widget _editorialColumn(PriceListColumn column) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final group in column.groups) ...[
        if (group.name != null) _editorialCategory(group.name!),
        for (final item in group.items) _editorialItem(item),
        pw.SizedBox(height: 8),
      ],
    ],
  );

  pw.Widget _editorialItem(PriceListItem item) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 7, bottom: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _outline, width: 0.7)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                item.name,
                maxLines: 2,
                style: pw.TextStyle(
                  color: _ink,
                  fontSize: 10.2,
                  fontWeight: pw.FontWeight.bold,
                  lineSpacing: 1.5,
                ),
              ),
              if (_details(item) case final String details) ...[
                pw.SizedBox(height: 2),
                pw.Text(
                  details,
                  maxLines: 2,
                  style: pw.TextStyle(color: _muted, fontSize: 7.8),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          ArgentineNumberFormatter.commercialMoney(item.price),
          style: pw.TextStyle(
            color: _terracotta,
            fontSize: 11.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  pw.Widget _editorialCategory(String name) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 2, bottom: 2),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: pw.BoxDecoration(
      color: _terracottaSoft,
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Text(
      name.toUpperCase(),
      style: pw.TextStyle(
        color: _terracotta,
        fontSize: 8.2,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.8,
      ),
    ),
  );

  pw.Widget _category(String name) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6, top: 2),
    child: pw.Text(
      name.toUpperCase(),
      style: pw.TextStyle(
        color: _ink,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 1,
      ),
    ),
  );

  pw.Widget _footer(PriceListDocument document, int page, int pageCount) =>
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              document.footerNote ?? '',
              maxLines: 2,
              style: pw.TextStyle(color: _muted, fontSize: 8),
            ),
          ),
          pw.Text(
            '$page de $pageCount',
            style: pw.TextStyle(color: _muted, fontSize: 8),
          ),
        ],
      );

  String? _details(PriceListItem item) {
    final parts = [
      item.dimensionsText,
      item.materialText,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<pw.ImageProvider?> _loadImage(
    String? path, {
    required int maxWidth,
  }) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final decoded = image.decodeImage(await file.readAsBytes());
      if (decoded == null) return null;
      final resized = decoded.width > maxWidth
          ? image.copyResize(decoded, width: maxWidth)
          : decoded;
      final bytes = Uint8List.fromList(image.encodeJpg(resized, quality: 86));
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
