import 'dart:io';

import 'package:flutter/material.dart';

import '../app_colors.dart';

final class AppFileImage extends StatelessWidget {
  const AppFileImage({
    required this.path,
    super.key,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.fallback,
    this.semanticLabel,
  });

  final String? path;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget? fallback;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final replacement =
        fallback ??
        const ColoredBox(
          color: AppColors.terracottaSoft,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: AppColors.terracottaDark,
            ),
          ),
        );
    final source = path;
    if (source == null || !_exists(source)) return replacement;
    return Image.file(
      File(source),
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => replacement,
    );
  }

  bool _exists(String source) {
    try {
      return File(source).existsSync();
    } on FileSystemException {
      return false;
    }
  }
}
