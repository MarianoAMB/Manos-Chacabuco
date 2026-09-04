import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';

final class GoogleSyncConfiguration {
  const GoogleSyncConfiguration({
    this.androidServerClientId = const String.fromEnvironment(
      'MANOS_GOOGLE_ANDROID_SERVER_CLIENT_ID',
    ),
    this.desktopClientId = const String.fromEnvironment(
      'MANOS_GOOGLE_DESKTOP_CLIENT_ID',
    ),
  });

  final String androidServerClientId;
  final String desktopClientId;

  GoogleSyncConfiguration overlay(GoogleSyncConfiguration saved) =>
      GoogleSyncConfiguration(
        androidServerClientId: saved.androidServerClientId.trim().isEmpty
            ? androidServerClientId
            : saved.androidServerClientId.trim(),
        desktopClientId: saved.desktopClientId.trim().isEmpty
            ? desktopClientId
            : saved.desktopClientId.trim(),
      );

  GoogleSyncConfiguration withSetupInput(
    String input, {
    required String platform,
  }) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('No se ingresó la identificación de Google.');
    }

    Map<String, Object?>? root;
    if (trimmed.startsWith('{')) {
      try {
        root = Map<String, Object?>.from(jsonDecode(trimmed) as Map);
      } on Object {
        throw const FormatException(
          'El archivo elegido no es una credencial válida de Google.',
        );
      }
    }

    if (platform == 'windows') {
      final installed = _map(root?['installed']);
      final clientId = _firstString([
        installed?['client_id'],
        root?['MANOS_GOOGLE_DESKTOP_CLIENT_ID'],
        root?['desktopClientId'],
        if (root == null) trimmed,
      ]);
      _validateClientId(
        clientId,
        invalidMessage: 'Elegí el JSON de una credencial Google de tipo "Aplicación de escritorio".',
      );
      return GoogleSyncConfiguration(
        androidServerClientId: androidServerClientId,
        desktopClientId: clientId!,
      );
    }

    if (platform == 'android') {
      final web = _map(root?['web']);
      final clientId = _firstString([
        web?['client_id'],
        root?['MANOS_GOOGLE_ANDROID_SERVER_CLIENT_ID'],
        root?['androidServerClientId'],
        root?['client_id'],
        if (root == null) trimmed,
      ]);
      _validateClientId(
        clientId,
        invalidMessage: 'Elegí el JSON de una credencial Google de tipo "Aplicación web" o pegá su Client ID.',
      );
      return GoogleSyncConfiguration(
        androidServerClientId: clientId!,
        desktopClientId: desktopClientId,
      );
    }

    throw UnsupportedError(
      'Google Drive está disponible solamente en Android y Windows.',
    );
  }

  Map<String, Object?> toJson() => {
    'androidServerClientId': androidServerClientId,
    'desktopClientId': desktopClientId,
  };

  factory GoogleSyncConfiguration.fromJson(Map<String, Object?> json) =>
      GoogleSyncConfiguration(
        androidServerClientId: json['androidServerClientId'] as String? ?? '',
        desktopClientId: json['desktopClientId'] as String? ?? '',
      );

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;

  static String? _firstString(List<Object?> values) {
    for (final value in values) {
      if (value case final String text when text.trim().isNotEmpty) {
        return text.trim();
      }
    }
    return null;
  }

  static void _validateClientId(
    String? value, {
    required String invalidMessage,
  }) {
    final clientId = value?.trim() ?? '';
    if (clientId.contains('REEMPLAZAR') ||
        !clientId.endsWith('.apps.googleusercontent.com') ||
        clientId.contains(RegExp(r'\s'))) {
      throw FormatException(invalidMessage);
    }
  }
}

final class GoogleOAuthConfigurationStore {
  GoogleOAuthConfigurationStore({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _rootDirectory;

  Future<GoogleSyncConfiguration?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final json = Map<String, Object?>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      return GoogleSyncConfiguration.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> write(GoogleSyncConfiguration configuration) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(configuration.toJson()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<File> _file() async {
    final root = await _rootDirectory();
    return File(paths.join(root.path, 'sync', 'google_oauth_client.json'));
  }
}
