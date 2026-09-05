import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

void main() {
  final sourceFile = File('assets/images/manos_chacabuco_app_icon.png');
  final decoded = image.decodeImage(sourceFile.readAsBytesSync());
  if (decoded == null) {
    throw StateError('No se pudo leer el ícono de origen.');
  }

  final edge = math.min(decoded.width, decoded.height);
  final square = image.copyCrop(
    decoded,
    x: (decoded.width - edge) ~/ 2,
    y: (decoded.height - edge) ~/ 2,
    width: edge,
    height: edge,
  );

  const androidSizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final entry in androidSizes.entries) {
    final target = image.copyResize(
      square,
      width: entry.value,
      height: entry.value,
      interpolation: image.Interpolation.cubic,
    );
    File('android/app/src/main/res/${entry.key}/ic_launcher.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(image.encodePng(target));
  }

  const windowsSizes = [16, 24, 32, 48, 64, 128, 256];
  final first = image.copyResize(
    square,
    width: windowsSizes.first,
    height: windowsSizes.first,
    interpolation: image.Interpolation.cubic,
  );
  for (final size in windowsSizes.skip(1)) {
    first.addFrame(
      image.copyResize(
        square,
        width: size,
        height: size,
        interpolation: image.Interpolation.cubic,
      ),
    );
  }
  File('windows/runner/resources/app_icon.ico')
      .writeAsBytesSync(image.encodeIco(first));
}
