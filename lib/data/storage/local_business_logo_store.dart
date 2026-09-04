import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/repositories/business_logo_store.dart';

final class LocalBusinessLogoStore implements BusinessLogoStore {
  LocalBusinessLogoStore._(this._directory, this._uuid);

  final Directory _directory;
  final Uuid _uuid;

  factory LocalBusinessLogoStore.inDirectory(
    Directory directory, {
    Uuid uuid = const Uuid(),
  }) => LocalBusinessLogoStore._(directory, uuid);

  static Future<LocalBusinessLogoStore> openDefault({
    Uuid uuid = const Uuid(),
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(paths.join(support.path, 'business_assets'));
    await directory.create(recursive: true);
    return LocalBusinessLogoStore._(directory, uuid);
  }

  @override
  Future<String> importFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const FileSystemException('Logo no encontrado');
    }
    final extension = _safeExtension(
      paths.extension(source.path).toLowerCase(),
    );
    final reference = 'logo-${_uuid.v4()}$extension';
    await source.copy(absolutePath(reference));
    return reference;
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
      throw ArgumentError('Referencia de logo inválida');
    }
    return paths.join(_directory.path, safeName);
  }

  String _safeExtension(String extension) => switch (extension) {
    '.jpg' || '.jpeg' || '.png' || '.webp' => extension,
    _ => '.png',
  };
}
