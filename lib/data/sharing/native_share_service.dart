import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/price_lists/price_list_models.dart';
import '../../domain/repositories/price_list_exporters.dart';

final class NativeShareService implements ShareService {
  const NativeShareService();

  @override
  Future<void> share(List<GeneratedPriceListFile> files, {String? text}) async {
    if (files.isEmpty) return;
    final temporary = await getTemporaryDirectory();
    final directory = Directory(paths.join(temporary.path, 'manos_share'));
    await directory.create(recursive: true);
    final shared = <XFile>[];
    for (final generated in files) {
      final file = File(
        paths.join(directory.path, paths.basename(generated.name)),
      );
      await file.writeAsBytes(generated.bytes, flush: true);
      shared.add(
        XFile(file.path, mimeType: generated.mimeType, name: generated.name),
      );
    }
    await SharePlus.instance.share(
      ShareParams(files: shared, text: text, subject: 'Manos Chacabuco'),
    );
  }
}
