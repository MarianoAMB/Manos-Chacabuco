import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/core/app_info.dart';

void main() {
  test('nombre y versión visibles coinciden con la metadata de plataforma', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final androidManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final windowsResources = File('windows/runner/Runner.rc')
        .readAsStringSync();

    expect(AppInfo.name, 'Manos Chacabuco');
    expect(
      pubspec,
      contains('version: ${AppInfo.version}+${AppInfo.buildNumber}'),
    );
    expect(androidManifest, contains('android:label="${AppInfo.name}"'));
    expect(
      windowsResources,
      contains('VALUE "ProductName", "${AppInfo.name}"'),
    );
  });
}
