// ignore_for_file: prefer_initializing_formals

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;

import '../../core/design_system/app_colors.dart';
import '../../core/formatting/argentine_number_formatter.dart';
import '../../domain/price_lists/price_list_models.dart';
import '../../domain/repositories/price_list_exporters.dart';
import '../../domain/services/price_list_file_namer.dart';
import '../../domain/services/price_list_paginator.dart';

final class PngPriceListExporter implements PriceListImageExporter {
  const PngPriceListExporter({
    PriceListPaginator paginator = const PriceListPaginator(),
    PriceListFileNamer fileNamer = const PriceListFileNamer(),
  }) : _paginator = paginator,
       _fileNamer = fileNamer;

  static const width = 1080;
  static const height = 1350;
  static Future<void>? _fontLoading;
  final PriceListPaginator _paginator;
  final PriceListFileNamer _fileNamer;

  @override
  Future<List<GeneratedPriceListFile>> export(
    PriceListDocument document,
  ) async {
    await _ensureFontLoaded();
    final pages = _paginator.paginate(
      document,
      target: PriceListRenderTarget.image,
    );
    if (pages.isEmpty) {
      throw StateError('Elegí al menos un producto con precio.');
    }
    final result = <GeneratedPriceListFile>[];
    for (final page in pages) {
      final bytes = await _renderPage(document, page, pages.length);
      result.add(
        GeneratedPriceListFile(
          name: _fileNamer.image(document, page.number),
          mimeType: 'image/png',
          bytes: bytes,
          pageCount: pages.length,
        ),
      );
    }
    return result;
  }

  Future<Uint8List> _renderPage(
    PriceListDocument document,
    PriceListPage page,
    int pageCount,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1080, 1350),
      Paint()..color = AppColors.canvas,
    );
    final loadedImages = <ui.Image>[];
    try {
      final logo = await _loadImage(document.logoPath, 180, 180);
      if (logo != null) loadedImages.add(logo);
      _drawHeader(canvas, document, logo);
      if (document.showPhotos) {
        await _drawPhotoContent(canvas, page, loadedImages);
      } else {
        _drawEditorialContent(canvas, page);
      }
      _drawFooter(canvas, document, page.number, pageCount);

      final picture = recorder.endRecording();
      final output = await picture.toImage(width, height);
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      output.dispose();
      if (data == null) throw StateError('No se pudo codificar la imagen.');
      return data.buffer.asUint8List();
    } finally {
      for (final image in loadedImages) {
        image.dispose();
      }
    }
  }

  void _drawHeader(Canvas canvas, PriceListDocument document, ui.Image? logo) {
    const left = 52.0;
    if (logo != null) {
      _drawCoverImage(
        canvas,
        logo,
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(left, 45, 106, 106),
          const Radius.circular(20),
        ),
      );
    }
    final textLeft = logo == null ? left : 182.0;
    _text(
      canvas,
      document.businessName.toUpperCase(),
      Offset(textLeft, 51),
      width: logo == null ? 680 : 550,
      size: 30,
      weight: FontWeight.w800,
      letterSpacing: 1.2,
    );
    _text(
      canvas,
      document.type.title,
      Offset(textLeft, 96),
      width: 520,
      size: 25,
      weight: FontWeight.w700,
      color: AppColors.terracotta,
    );
    if (document.showUpdatedDate) {
      _text(
        canvas,
        'Actualizado: ${_date(document.generatedAt)}',
        const Offset(760, 61),
        width: 266,
        size: 17,
        color: AppColors.mutedInk,
        align: TextAlign.right,
      );
    }
    if (document.wholesaleMinimum != null) {
      final box = RRect.fromRectAndRadius(
        const Rect.fromLTWH(52, 169, 976, 48),
        const Radius.circular(14),
      );
      canvas.drawRRect(box, Paint()..color = AppColors.sageSoft);
      _text(
        canvas,
        'Compra mínima mayorista: ${ArgentineNumberFormatter.commercialMoney(document.wholesaleMinimum!)}',
        const Offset(72, 181),
        width: 936,
        size: 19,
        weight: FontWeight.w700,
      );
    }
  }

  Future<void> _drawPhotoContent(
    Canvas canvas,
    PriceListPage page,
    List<ui.Image> loadedImages,
  ) async {
    var y = 238.0;
    const left = 52.0;
    const gap = 24.0;
    const cardWidth = 476.0;
    const cardHeight = 400.0;
    for (final group in page.groups) {
      if (group.name != null) {
        _category(canvas, group.name!, y);
        y += 42;
      }
      for (var index = 0; index < group.items.length; index += 2) {
        for (var column = 0; column < 2; column++) {
          final itemIndex = index + column;
          if (itemIndex >= group.items.length) break;
          final item = group.items[itemIndex];
          final x = left + column * (cardWidth + gap);
          final photo = await _loadImage(item.photoPath, 720, 480);
          if (photo != null) loadedImages.add(photo);
          _drawPhotoCard(
            canvas,
            item,
            photo,
            Rect.fromLTWH(x, y, cardWidth, cardHeight),
          );
        }
        y += cardHeight + 20;
      }
      y += 4;
    }
  }

  void _drawPhotoCard(
    Canvas canvas,
    PriceListItem item,
    ui.Image? photo,
    Rect rect,
  ) {
    final card = RRect.fromRectAndRadius(rect, const Radius.circular(24));
    canvas.drawRRect(card, Paint()..color = AppColors.surface);
    canvas.drawRRect(
      card,
      Paint()
        ..color = AppColors.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final photoRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + 16, rect.top + 16, rect.width - 32, 224),
      const Radius.circular(17),
    );
    if (photo != null) {
      _drawCoverImage(canvas, photo, photoRect);
    } else {
      canvas.drawRRect(photoRect, Paint()..color = AppColors.terracottaSoft);
      _text(
        canvas,
        'Sin foto',
        Offset(photoRect.left, photoRect.top + 92),
        width: photoRect.width,
        size: 24,
        weight: FontWeight.w800,
        color: AppColors.terracotta,
        align: TextAlign.center,
      );
    }
    _text(
      canvas,
      item.name,
      Offset(rect.left + 20, rect.top + 255),
      width: rect.width - 40,
      size: 22,
      weight: FontWeight.w700,
      maxLines: 2,
    );
    final details = _details(item);
    if (details != null) {
      _text(
        canvas,
        details,
        Offset(rect.left + 20, rect.top + 312),
        width: rect.width - 40,
        size: 16,
        color: AppColors.mutedInk,
        maxLines: 1,
      );
    }
    _text(
      canvas,
      ArgentineNumberFormatter.commercialMoney(item.price),
      Offset(rect.left + 20, rect.bottom - 54),
      width: rect.width - 40,
      size: 29,
      weight: FontWeight.w800,
      color: AppColors.terracotta,
    );
  }

  void _drawEditorialContent(Canvas canvas, PriceListPage page) {
    const columnWidth = 474.0;
    const columnGap = 28.0;
    for (var columnIndex = 0; columnIndex < 2; columnIndex++) {
      if (columnIndex >= page.editorialColumns.length) break;
      final x = 52.0 + columnIndex * (columnWidth + columnGap);
      var y = 238.0;
      for (final group in page.editorialColumns[columnIndex].groups) {
        if (group.name != null) {
          final categoryBox = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, columnWidth, 38),
            const Radius.circular(10),
          );
          canvas.drawRRect(
            categoryBox,
            Paint()..color = AppColors.terracottaSoft,
          );
          _text(
            canvas,
            group.name!.toUpperCase(),
            Offset(x + 14, y + 9),
            width: columnWidth - 28,
            size: 16,
            weight: FontWeight.w800,
            color: AppColors.terracotta,
            letterSpacing: 1.1,
          );
          y += 46;
        }
        for (final item in group.items) {
          _drawEditorialItem(canvas, item, x, y, columnWidth);
          y += 88;
        }
        y += 8;
      }
    }
  }

  void _drawEditorialItem(
    Canvas canvas,
    PriceListItem item,
    double x,
    double y,
    double width,
  ) {
    canvas.drawLine(
      Offset(x, y + 79),
      Offset(x + width, y + 79),
      Paint()
        ..color = AppColors.outline
        ..strokeWidth = 1.5,
    );
    _text(
      canvas,
      item.name,
      Offset(x, y + 8),
      width: 285,
      size: 19,
      weight: FontWeight.w700,
      maxLines: 2,
    );
    final details = _details(item);
    if (details != null) {
      _text(
        canvas,
        details,
        Offset(x, y + 52),
        width: 295,
        size: 13,
        color: AppColors.mutedInk,
        maxLines: 1,
      );
    }
    _text(
      canvas,
      ArgentineNumberFormatter.commercialMoney(item.price),
      Offset(x + 298, y + 20),
      width: width - 298,
      size: 22,
      weight: FontWeight.w800,
      color: AppColors.terracotta,
      align: TextAlign.right,
    );
  }

  void _category(Canvas canvas, String name, double y) {
    _text(
      canvas,
      name.toUpperCase(),
      Offset(54, y),
      width: 970,
      size: 18,
      weight: FontWeight.w800,
      letterSpacing: 1.3,
    );
  }

  void _drawFooter(
    Canvas canvas,
    PriceListDocument document,
    int page,
    int pageCount,
  ) {
    canvas.drawLine(
      const Offset(52, 1270),
      const Offset(1028, 1270),
      Paint()
        ..color = AppColors.outline
        ..strokeWidth = 2,
    );
    if (document.footerNote != null) {
      _text(
        canvas,
        document.footerNote!,
        const Offset(52, 1284),
        width: 800,
        size: 15,
        color: AppColors.mutedInk,
        maxLines: 2,
      );
    }
    _text(
      canvas,
      '$page de $pageCount',
      const Offset(880, 1284),
      width: 148,
      size: 15,
      color: AppColors.mutedInk,
      align: TextAlign.right,
    );
  }

  void _drawCoverImage(Canvas canvas, ui.Image image, RRect target) {
    final destination = target.outerRect;
    final sourceRatio = image.width / image.height;
    final targetRatio = destination.width / destination.height;
    late Rect source;
    if (sourceRatio > targetRatio) {
      final cropWidth = image.height * targetRatio;
      source = Rect.fromLTWH(
        (image.width - cropWidth) / 2,
        0,
        cropWidth,
        image.height.toDouble(),
      );
    } else {
      final cropHeight = image.width / targetRatio;
      source = Rect.fromLTWH(
        0,
        (image.height - cropHeight) / 2,
        image.width.toDouble(),
        cropHeight,
      );
    }
    canvas.save();
    canvas.clipRRect(target);
    canvas.drawImageRect(image, source, destination, Paint());
    canvas.restore();
  }

  Future<ui.Image?> _loadImage(String? path, int width, int height) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: width,
        targetHeight: height,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    required double width,
    required double size,
    Color color = AppColors.ink,
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    TextAlign align = TextAlign.left,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'PriceListRoboto',
          letterSpacing: letterSpacing,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(minWidth: width, maxWidth: width);
    painter.paint(canvas, offset);
  }

  Future<void> _ensureFontLoaded() {
    final loading = _fontLoading;
    if (loading != null) return loading;
    final next = () async {
      final loader = FontLoader('PriceListRoboto')
        ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
      await loader.load();
    }();
    _fontLoading = next;
    return next;
  }

  String? _details(PriceListItem item) {
    final values = [
      item.dimensionsText,
      item.materialText,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    return values.isEmpty ? null : values.join(' · ');
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}
