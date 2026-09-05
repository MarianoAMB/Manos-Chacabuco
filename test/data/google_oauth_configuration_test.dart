import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:manos_chacabuco/data/sync/google_oauth_configuration.dart';

void main() {
  const desktopClientId = '123456789-desktop.apps.googleusercontent.com';
  const webClientId = '123456789-web.apps.googleusercontent.com';

  test('Windows importa el JSON de una aplicación de escritorio', () {
    final configuration = const GoogleSyncConfiguration().withSetupInput('''
      {
        "installed": {
          "client_id": "$desktopClientId",
          "client_secret": "desktop-secret"
        }
      }
      ''', platform: 'windows');

    expect(configuration.desktopClientId, desktopClientId);
    expect(configuration.desktopClientSecret, 'desktop-secret');
  });

  test('Android acepta el JSON web o el Client ID pegado', () {
    final fromJson = const GoogleSyncConfiguration().withSetupInput(
      '''{"web":{"client_id":"$webClientId"}}''',
      platform: 'android',
    );
    final fromText = const GoogleSyncConfiguration().withSetupInput(
      webClientId,
      platform: 'android',
    );

    expect(fromJson.androidServerClientId, webClientId);
    expect(fromText.androidServerClientId, webClientId);
  });

  test('rechaza ejemplos y archivos del tipo incorrecto', () {
    expect(
      () => const GoogleSyncConfiguration().withSetupInput(
        '{"web":{"client_id":"$webClientId"}}',
        platform: 'windows',
      ),
      throwsFormatException,
    );
    expect(
      () => const GoogleSyncConfiguration().withSetupInput(
        'REEMPLAZAR.apps.googleusercontent.com',
        platform: 'android',
      ),
      throwsFormatException,
    );
  });

  test('guarda la configuración para el próximo inicio de la app', () async {
    final root = await Directory.systemTemp.createTemp('manos-oauth-config-');
    addTearDown(() => root.delete(recursive: true));
    final store = GoogleOAuthConfigurationStore(
      rootDirectory: () async => root,
    );
    const expected = GoogleSyncConfiguration(
      androidServerClientId: webClientId,
      desktopClientId: desktopClientId,
      desktopClientSecret: 'desktop-secret',
    );

    await store.write(expected);
    final restored = await store.read();

    expect(restored?.androidServerClientId, webClientId);
    expect(restored?.desktopClientId, desktopClientId);
    expect(restored?.desktopClientSecret, 'desktop-secret');
  });

  test('la credencial incluida reemplaza una configuración manual antigua', () {
    const saved = GoogleSyncConfiguration(
      androidServerClientId: 'old-web.apps.googleusercontent.com',
      desktopClientId: 'old-desktop.apps.googleusercontent.com',
      desktopClientSecret: 'old-secret',
    );
    const bundled = GoogleSyncConfiguration(
      androidServerClientId: webClientId,
      desktopClientId: desktopClientId,
      desktopClientSecret: 'bundled-secret',
    );

    final merged = saved.overlay(bundled);

    expect(merged.androidServerClientId, webClientId);
    expect(merged.desktopClientId, desktopClientId);
    expect(merged.desktopClientSecret, 'bundled-secret');
  });
}
