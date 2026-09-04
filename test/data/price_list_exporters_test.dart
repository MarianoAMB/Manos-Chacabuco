import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/exporting/pdf_price_list_exporter.dart';
import 'package:manos_chacabuco/data/exporting/png_price_list_exporter.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';
import 'package:manos_chacabuco/domain/services/price_list_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF es válido, A4 y multipágina para una lista larga', () async {
    final file = await const PdfPriceListExporter().export(
      _document(count: 14, showPhotos: true),
    );

    expect(ascii.decode(file.bytes.take(5).toList()), '%PDF-');
    expect(file.bytes.length, greaterThan(1500));
    expect(file.mimeType, 'application/pdf');
    expect(file.pageCount, 3);
    expect(file.name, 'Manos_Chacabuco_Lista_Minorista_2026-09-03.pdf');
  });

  test('PNG corto genera una imagen 1080x1350', () async {
    final files = await const PngPriceListExporter().export(
      _document(count: 4, showPhotos: true),
    );
    final decoded = image.decodePng(files.single.bytes);

    expect(files, hasLength(1));
    expect(decoded?.width, 1080);
    expect(decoded?.height, 1350);
    expect(files.single.mimeType, 'image/png');
  });

  test('PNG largo se divide en varias imágenes legibles', () async {
    final files = await const PngPriceListExporter().export(
      _document(count: 10, showPhotos: true),
    );

    expect(files, hasLength(3));
    expect(files.map((file) => file.name), [
      'Manos_Chacabuco_Lista_Minorista_2026-09-03_01.png',
      'Manos_Chacabuco_Lista_Minorista_2026-09-03_02.png',
      'Manos_Chacabuco_Lista_Minorista_2026-09-03_03.png',
    ]);
    expect(files.every((file) => image.decodePng(file.bytes) != null), isTrue);
  });

  test('PDF sin fotos usa su paginación editorial de dos columnas', () async {
    final document = _document(count: 30, showPhotos: false);
    final pages = const PriceListPaginator().paginate(
      document,
      target: PriceListRenderTarget.pdf,
    );
    final file = await const PdfPriceListExporter().export(document);

    expect(pages, hasLength(2));
    expect(pages.first.editorialColumns, hasLength(2));
    expect(pages.last.editorialColumns, hasLength(2));
    expect(
      (pages.last.editorialColumns.first.items.length -
              pages.last.editorialColumns.last.items.length)
          .abs(),
      lessThanOrEqualTo(1),
    );
    expect(
      pages
          .expand((page) => page.editorialColumns)
          .expand((column) => column.groups)
          .every((group) => group.items.isNotEmpty),
      isTrue,
    );
    expect(
      pages.expand((page) => page.items).map((item) => item.productId).toSet(),
      hasLength(30),
    );
    expect(file.pageCount, 2);
    expect(ascii.decode(file.bytes.take(5).toList()), '%PDF-');
  });

  test('PNG sin fotos mantiene dos columnas y 1080 px', () async {
    final document = _document(count: 22, showPhotos: false);
    final pages = const PriceListPaginator().paginate(
      document,
      target: PriceListRenderTarget.image,
    );
    final files = await const PngPriceListExporter().export(document);

    expect(pages, hasLength(2));
    expect(pages.first.editorialColumns, hasLength(2));
    expect(files, hasLength(2));
    for (final file in files) {
      final decoded = image.decodePng(file.bytes);
      expect(decoded?.width, 1080);
      expect(decoded?.height, 1350);
    }
  });
}

PriceListDocument _document({required int count, required bool showPhotos}) =>
    PriceListDocument(
      businessName: 'Manos Chacabuco',
      generatedAt: DateTime(2026, 9, 3),
      type: PriceListType.retail,
      showPhotos: showPhotos,
      showUpdatedDate: true,
      footerNote: 'Consultar colores disponibles.',
      groups: [
        PriceListGroup(
          name: 'Maceteros',
          items: [
            for (var index = 1; index <= count; index++)
              PriceListItem(
                productId: 'p$index',
                name: 'Macetero artesanal $index',
                categoryName: 'Maceteros',
                price: Money.ars(2000000 + index * 10000),
                photoPath: index == 1 ? 'foto-que-ya-no-existe.png' : null,
                dimensionsText: 'Ø 20 × 18 cm',
                materialText: 'Cordón de algodón N°7',
              ),
          ],
        ),
      ],
    );
