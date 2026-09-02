import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/product_photo_store.dart';

final class LocalProductPhotoStore implements ProductPhotoStore {
  LocalProductPhotoStore._(this._directory, this._uuid);

  final Directory _directory;
  final Uuid _uuid;

  static Future<LocalProductPhotoStore> openDefault({
    Uuid uuid = const Uuid(),
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(paths.join(support.path, 'product_photos'));
    await directory.create(recursive: true);
    return LocalProductPhotoStore._(directory, uuid);
  }

  @override
  Future<String> importFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('Foto no encontrada');
    }
    final extension = paths.extension(source.path).toLowerCase();
    final reference = '${_uuid.v4()}${_safeExtension(extension)}';
    await source.copy(absolutePath(reference));
    return reference;
  }

  @override
  Future<String?> duplicate(String? reference) async {
    if (reference == null) return null;
    final source = File(absolutePath(reference));
    if (!await source.exists()) return null;
    return importFile(source.path);
  }

  @override
  Future<void> delete(String reference) async {
    final file = File(absolutePath(reference));
    if (await file.exists()) await file.delete();
  }

  @override
  String absolutePath(String reference) {
    final safeName = paths.basename(reference);
    if (safeName != reference) {
      throw ArgumentError('Referencia de foto inválida');
    }
    return paths.join(_directory.path, safeName);
  }

  String _safeExtension(String extension) => switch (extension) {
    '.jpg' || '.jpeg' || '.png' || '.webp' || '.gif' => extension,
    _ => '.jpg',
  };
}
