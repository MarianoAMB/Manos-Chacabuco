import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/data/sync/windows_protected_token_store.dart';
import 'package:path/path.dart' as paths;

void main() {
  test(
    'Windows cifra, recupera y elimina el refresh token con DPAPI',
    () async {
      if (!Platform.isWindows) return;
      final root = await Directory.systemTemp.createTemp('manos-dpapi-');
      addTearDown(() => root.delete(recursive: true));
      final store = WindowsProtectedTokenStore(rootDirectory: () async => root);
      const token = 'refresh-token-no-debe-quedar-en-claro';

      await store.write(token);
      final encrypted = await File(
        paths.join(root.path, 'sync', 'google_oauth.dpapi'),
      ).readAsBytes();

      expect(String.fromCharCodes(encrypted), isNot(contains(token)));
      expect(await store.read(), token);
      await store.delete();
      expect(await store.read(), isNull);
    },
  );
}
