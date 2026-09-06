import 'dart:typed_data';

import '../../domain/sync/sync_models.dart';

abstract interface class RemoteSyncStore {
  Future<List<SyncEnvelope>> pull({required Set<String> knownChangeIds});

  Future<void> push(SyncEnvelope envelope);

  Future<bool> hasAsset(String hash);

  Future<void> uploadAsset(SyncAssetReference asset, Uint8List bytes);

  Future<Uint8List?> downloadAsset(SyncAssetReference asset);
}

abstract interface class DeviceSyncRemoteStore {
  Future<void> publishDeviceSnapshot(SyncDeviceSnapshot snapshot);

  Future<List<SyncDeviceSnapshot>> fetchDeviceSnapshots();
}

enum RemoteIntegrationResult { applied, ignored, conflict }

abstract interface class LocalSyncStore {
  Future<String> deviceId();

  Future<Set<String>> processedChangeIds();

  Future<List<PendingSyncEnvelope>> pending({int limit = 100});

  Future<RemoteIntegrationResult> integrateRemote(
    SyncEnvelope envelope, {
    required Future<Uint8List?> Function(SyncAssetReference asset)
    downloadAsset,
  });

  Future<Uint8List?> readAsset(SyncAssetReference asset);

  Future<void> markPushed(PendingSyncEnvelope pending);

  Future<int> pendingCount();

  Future<List<SyncConflict>> conflicts();

  Future<void> resolveConflict(
    String conflictId,
    SyncConflictResolution resolution, {
    String? remoteRevision,
  });

  Future<void> prepareFullUploadForNewAccount();
}

abstract interface class DeviceSyncLocalStore {
  Future<SyncDeviceSnapshot> buildCurrentDeviceSnapshot({
    required List<SyncDeviceChange> recentChanges,
  });

  Future<List<SyncDeviceSnapshot>> loadDeviceSnapshots();

  Future<void> saveDeviceSnapshots(List<SyncDeviceSnapshot> snapshots);

  Future<void> renameCurrentDevice(String name);
}

abstract interface class SyncAccountStore {
  Future<SyncAccountState> load();

  Future<void> save(SyncAccountState state);
}

final class SyncAccountState {
  const SyncAccountState({
    required this.connected,
    this.email,
    this.lastSyncAt,
    this.lastError,
  });

  const SyncAccountState.disconnected()
    : connected = false,
      email = null,
      lastSyncAt = null,
      lastError = null;

  final bool connected;
  final String? email;
  final DateTime? lastSyncAt;
  final String? lastError;

  SyncAccountState copyWith({
    bool? connected,
    String? email,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
  }) => SyncAccountState(
    connected: connected ?? this.connected,
    email: email ?? this.email,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastError: clearError ? null : lastError ?? this.lastError,
  );
}

abstract interface class SyncAuthenticatedSession {
  String get email;

  RemoteSyncStore get remoteStore;

  Future<void> close();
}

abstract interface class SyncAuthenticator {
  bool get isConfigured;

  String? get configurationMessage;

  Future<SyncAuthenticatedSession?> restore();

  Future<SyncAuthenticatedSession> connect();

  Future<void> disconnect();
}

abstract interface class ConfigurableSyncAuthenticator
    implements SyncAuthenticator {
  Future<void> configure(String setupInput);
}
