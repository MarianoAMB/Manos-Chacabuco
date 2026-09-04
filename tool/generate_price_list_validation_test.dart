import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/money/money.dart';
import 'package:manos_chacabuco/data/exporting/pdf_price_list_exporter.dart';
import 'package:manos_chacabuco/data/exporting/png_price_list_exporter.dart';
import 'package:manos_chacabuco/domain/price_lists/price_list_models.dart';
import 'package:path/path.dart' as paths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('genera archivos visuales de validación', () async {
    final root = Directory.current.path;
    final pdfDirectory = Directory(paths.join(root, 'output', 'pdf'));
    final imageDirectory = Directory(paths.join(root, 'output', 'images'));
    final temporaryDirectory = Directory(paths.join(root, 'tmp', 'pdfs'));
    await pdfDirectory.create(recursive: true);
    await imageDirectory.create(recursive: true);
    await temporaryDirectory.create(recursive: true);

    final photoPath = paths.join(temporaryDirectory.path, 'catalog-photo.png');
    await File(photoPath).writeAsBytes(await _fixturePhoto());
    final photoDocument = _document(photoPath);
    final editorialDocument = _document(
      photoPath,
      showPhotos: false,
      itemsPerCategory: 12,
    );

    final pdf = await const PdfPriceListExporter().export(editorialDocument);
    await File(paths.join(pdfDirectory.path, pdf.name)).writeAsBytes(pdf.bytes);

    final images = await const PngPriceListExporter().export(photoDocument);
    for (final image in images) {
      await File(paths.join(imageDirectory.path, image.name))
          .writeAsBytes(image.bytes);
    }

    final compactWholesale = await const PngPriceListExporter().export(
      _document(
        photoPath,
        type: PriceListType.wholesale,
        showPhotos: false,
        wholesaleMinimum: const Money.ars(15000000),
        itemsPerCategory: 12,
      ),
    );
    for (final image in compactWholesale) {
      await File(paths.join(imageDirectory.path, image.name))
          .writeAsBytes(image.bytes);
    }

    expect(pdf.pageCount, 2);
    expect(images, hasLength(3));
    expect(compactWholesale, hasLength(2));
  });
}

PriceListDocument _document(
  String photoPath, {
  PriceListType type = PriceListType.retail,
  bool showPhotos = true,
  Money? wholesaleMinimum,
  int itemsPerCategory = 4,
}) {
  const categories = ['Maceteros', 'Cestos', 'Cocina y mesa'];
  final names = [
    'Macetero Córdoba natural',
    'Macetero redondo premium',
    'Portamaceta de algodón',
    'Macetero tejido artesanal',
    'Cesto organizador grande',
    'Cesto oval con manijas',
    'Contenedor multiuso',
    'Cesto bajo bicolor',
    'Panera Córdoba',
    'Bandeja desayuno',
    'Centro de mesa oval',
    'Posafuente redondo',
  ];
  return PriceListDocument(
    businessName: 'Manos Chacabuco',
    generatedAt: DateTime(2026, 9, 3),
    type: type,
    showPhotos: showPhotos,
    showUpdatedDate: true,
    wholesaleMinimum: wholesaleMinimum,
    footerNote: 'Consultar colores disponibles.',
    groups: [
      for (
        var categoryIndex = 0;
        categoryIndex < categories.length;
        categoryIndex++
      )
        PriceListGroup(
          name: categories[categoryIndex],
          items: [
            for (var offset = 0; offset < itemsPerCategory; offset++)
              PriceListItem(
                productId: 'fixture-$categoryIndex-$offset',
                name:
                    '${names[categoryIndex * 4 + (offset % 4)]}${offset < 4 ? '' : ' ${offset + 1}'}',
                categoryName: categories[categoryIndex],
                price: Money.ars(
                  (type == PriceListType.retail ? 1780000 : 1424000) +
                      (categoryIndex * itemsPerCategory + offset) * 235050,
                ),
                photoPath: switch (offset) {
                  0 || 2 => photoPath,
                  1 => paths.join(
                    Directory.current.path,
                    'foto-inexistente.png',
                  ),
                  _ => null,
                },
                dimensionsText: offset.isEven ? 'Ø 20 × 18 cm' : null,
                materialText: offset == 3 ? null : 'Cordón de algodón N°7',
              ),
          ],
        ),
    ],
  );
}

Future<List<int>> _fixturePhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1200, 800),
    Paint()..color = const Color(0xFFE8D5C6),
  );
  canvas.drawCircle(
    const Offset(600, 385),
    245,
    Paint()..color = const Color(0xFFC47D61),
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(360, 280, 480, 310),
      const Radius.circular(70),
    ),
    Paint()..color = const Color(0xFFF8EFE7),
  );
  for (var line = 0; line < 6; line++) {
    canvas.drawLine(
      Offset(405, 335 + line * 42),
      Offset(795, 335 + line * 42),
      Paint()
        ..color = const Color(0xFF985343)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1200, 800);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
