import 'dart:typed_data';

import '../../core/sync/sync_contracts.dart';
import '../../domain/sync/sync_models.dart';

final class FakeRemoteSyncStore
    implements RemoteSyncStore, DeviceSyncRemoteStore {
  final Map<String, SyncEnvelope> _changes = {};
  final Map<String, Uint8List> _assets = {};
  final Map<String, SyncDeviceSnapshot> _deviceSnapshots = {};

  bool failNextRequest = false;
  int downloadedChangeCount = 0;
  int uploadedChangeCount = 0;
  int downloadedAssetCount = 0;
  int uploadedAssetCount = 0;

  List<SyncEnvelope> get allChanges => List.unmodifiable(_changes.values);
  List<SyncDeviceSnapshot> get allDeviceSnapshots =>
      List.unmodifiable(_deviceSnapshots.values);

  @override
  Future<List<SyncEnvelope>> pull({required Set<String> knownChangeIds}) async {
    _maybeFail();
    final result = _changes.values
        .where((change) => !knownChangeIds.contains(change.changeId))
        .toList(growable: false);
    downloadedChangeCount += result.length;
    return result;
  }

  @override
  Future<void> push(SyncEnvelope envelope) async {
    _maybeFail();
    if (_changes.containsKey(envelope.changeId)) return;
    _changes[envelope.changeId] = envelope;
    uploadedChangeCount++;
  }

  @override
  Future<bool> hasAsset(String hash) async {
    _maybeFail();
    return _assets.containsKey(hash);
  }

  @override
  Future<void> uploadAsset(SyncAssetReference asset, Uint8List bytes) async {
    _maybeFail();
    if (_assets.containsKey(asset.hash)) return;
    _assets[asset.hash] = Uint8List.fromList(bytes);
    uploadedAssetCount++;
  }

  @override
  Future<Uint8List?> downloadAsset(SyncAssetReference asset) async {
    _maybeFail();
    final bytes = _assets[asset.hash];
    if (bytes == null) return null;
    downloadedAssetCount++;
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> publishDeviceSnapshot(SyncDeviceSnapshot snapshot) async {
    _maybeFail();
    _deviceSnapshots[snapshot.deviceId] = snapshot.copyWith(
      lastSyncedAt: DateTime.now().toUtc(),
      isCurrent: false,
    );
  }

  @override
  Future<List<SyncDeviceSnapshot>> fetchDeviceSnapshots() async {
    _maybeFail();
    return [
      for (final snapshot in _deviceSnapshots.values)
        snapshot.copyWith(isCurrent: false),
    ];
  }

  void _maybeFail() {
    if (!failNextRequest) return;
    failNextRequest = false;
    throw const RemoteSyncException('Google Drive no está disponible ahora.');
  }
}

final class RemoteSyncException implements Exception {
  const RemoteSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}
