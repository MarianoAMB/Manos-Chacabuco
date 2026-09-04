import 'dart:convert';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../core/sync/sync_contracts.dart';
import '../../domain/sync/sync_models.dart';

final class GoogleDriveRemoteSyncStore implements RemoteSyncStore {
  GoogleDriveRemoteSyncStore(http.Client client)
    : _api = drive.DriveApi(client);

  static const appDataScope = drive.DriveApi.driveAppdataScope;
  static const _changePrefix = 'mc-change-';
  static const _assetPrefix = 'mc-asset-';

  final drive.DriveApi _api;

  @override
  Future<List<SyncEnvelope>> pull({required Set<String> knownChangeIds}) async {
    final files = await _list("name contains '$_changePrefix'");
    final result = <SyncEnvelope>[];
    for (final file in files) {
      final name = file.name;
      final id = file.id;
      if (name == null || id == null || !name.endsWith('.json')) continue;
      final changeId = name.substring(
        _changePrefix.length,
        name.length - '.json'.length,
      );
      if (knownChangeIds.contains(changeId)) continue;
      final bytes = await _download(id);
      result.add(
        SyncEnvelope.fromJson(
          Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> push(SyncEnvelope envelope) async {
    final name = '$_changePrefix${envelope.changeId}.json';
    if (await _exists(name)) return;
    final bytes = Uint8List.fromList(utf8.encode(envelope.encode()));
    await _upload(
      name,
      'application/json',
      bytes,
      appProperties: {
        'kind': 'entityChange',
        'entityType': envelope.entityType,
        'entityId': envelope.entityId,
        'revision': envelope.revision,
      },
    );
  }

  @override
  Future<bool> hasAsset(String hash) => _exists('$_assetPrefix$hash');

  @override
  Future<void> uploadAsset(SyncAssetReference asset, Uint8List bytes) async {
    final name = '$_assetPrefix${asset.hash}${asset.extension}';
    if (await _exists(name)) return;
    await _upload(
      name,
      'application/octet-stream',
      bytes,
      appProperties: {'kind': asset.kind, 'hash': asset.hash},
    );
  }

  @override
  Future<Uint8List?> downloadAsset(SyncAssetReference asset) async {
    final files = await _list("name contains '$_assetPrefix${asset.hash}'");
    for (final file in files) {
      if (file.name?.startsWith('$_assetPrefix${asset.hash}') != true) continue;
      if (file.id case final String id) return _download(id);
    }
    return null;
  }

  Future<bool> _exists(String nameOrPrefix) async {
    final files = await _list("name contains '${_escape(nameOrPrefix)}'");
    return files.any((file) => file.name?.startsWith(nameOrPrefix) == true);
  }

  Future<List<drive.File>> _list(String query) async {
    final result = <drive.File>[];
    String? pageToken;
    do {
      final page = await _api.files.list(
        spaces: 'appDataFolder',
        q: query,
        pageSize: 1000,
        pageToken: pageToken,
        $fields: 'nextPageToken,files(id,name,appProperties)',
      );
      result.addAll(page.files ?? const []);
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return result;
  }

  Future<void> _upload(
    String name,
    String mimeType,
    Uint8List bytes, {
    required Map<String, String> appProperties,
  }) async {
    await _api.files.create(
      drive.File(
        name: name,
        parents: const ['appDataFolder'],
        mimeType: mimeType,
        appProperties: appProperties,
      ),
      uploadMedia: drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: mimeType,
      ),
      $fields: 'id',
    );
  }

  Future<Uint8List> _download(String fileId) async {
    final media = await _api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String _escape(String value) => value.replaceAll("'", "\\'");
}
