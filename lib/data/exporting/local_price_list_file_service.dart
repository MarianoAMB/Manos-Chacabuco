import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

import '../../domain/price_lists/price_list_models.dart';
import '../../domain/repositories/price_list_exporters.dart';

final class LocalPriceListFileService implements PriceListFileService {
  const LocalPriceListFileService();

  @override
  Future<List<String>> save(
    List<GeneratedPriceListFile> files, {
    required bool askLocation,
  }) async {
    if (files.isEmpty) return const [];
    if (askLocation && Platform.isWindows) {
      return files.length == 1
          ? _saveOneWithDialog(files.single)
          : _saveManyWithDirectory(files);
    }
    final directory = await _defaultExportDirectory();
    return _writeAll(files, directory);
  }

  Future<List<String>> _saveOneWithDialog(GeneratedPriceListFile file) async {
    final location = await getSaveLocation(
      suggestedName: file.name,
      acceptedTypeGroups: [
        XTypeGroup(
          label: file.mimeType == 'application/pdf' ? 'PDF' : 'PNG',
          extensions: [paths.extension(file.name).replaceFirst('.', '')],
        ),
      ],
      confirmButtonText: 'Guardar',
      canCreateDirectories: true,
    );
    if (location == null) return const [];
    await File(location.path).writeAsBytes(file.bytes, flush: true);
    return [location.path];
  }

  Future<List<String>> _saveManyWithDirectory(
    List<GeneratedPriceListFile> files,
  ) async {
    final selected = await getDirectoryPath(
      confirmButtonText: 'Guardar acá',
      canCreateDirectories: true,
    );
    if (selected == null) return const [];
    return _writeAll(files, Directory(selected));
  }

  Future<List<String>> _writeAll(
    List<GeneratedPriceListFile> files,
    Directory directory,
  ) async {
    await directory.create(recursive: true);
    final result = <String>[];
    for (final generated in files) {
      final target = File(_availablePath(directory.path, generated.name));
      await target.writeAsBytes(generated.bytes, flush: true);
      result.add(target.path);
    }
    return result;
  }

  Future<Directory> _defaultExportDirectory() async {
    final downloads = await getDownloadsDirectory();
    final parent = downloads ?? await getApplicationDocumentsDirectory();
    return Directory(paths.join(parent.path, 'Manos Chacabuco'));
  }

  String _availablePath(String directory, String name) {
    final requested = paths.join(directory, paths.basename(name));
    if (!File(requested).existsSync()) return requested;
    final stem = paths.basenameWithoutExtension(name);
    final extension = paths.extension(name);
    var index = 2;
    while (true) {
      final candidate = paths.join(directory, '${stem}_$index$extension');
      if (!File(candidate).existsSync()) return candidate;
      index++;
    }
  }

  @override
  Future<void> openFile(String path) async {
    if (!Platform.isWindows) return;
    await Process.start('explorer.exe', [
      path,
    ], mode: ProcessStartMode.detached);
  }

  @override
  Future<void> openContainingFolder(String path) async {
    if (!Platform.isWindows) return;
    await Process.start('explorer.exe', [
      '/select,$path',
    ], mode: ProcessStartMode.detached);
  }
}
