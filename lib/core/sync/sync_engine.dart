// ignore_for_file: prefer_initializing_formals

import '../../domain/sync/sync_models.dart';
import 'sync_contracts.dart';

final class SyncEngine {
  SyncEngine({
    required LocalSyncStore local,
    required RemoteSyncStore remote,
    void Function(String stage)? onStage,
  }) : _local = local,
       _remote = remote,
       _onStage = onStage;

  final LocalSyncStore _local;
  final RemoteSyncStore _remote;
  final void Function(String stage)? _onStage;
  bool _running = false;

  Future<SyncRunResult> synchronize() async {
    if (_running) {
      return const SyncRunResult(uploaded: 0, downloaded: 0, conflicts: 0);
    }
    _running = true;
    try {
      var downloaded = 0;
      var conflictCount = 0;
      _onStage?.call('Preparando los datos locales');
      final known = await _local.processedChangeIds();
      _onStage?.call('Leyendo los archivos de Google Drive');
      final remoteChanges = await _remote.pull(knownChangeIds: known);
      for (final envelope in _ordered(remoteChanges)) {
        _onStage?.call('Procesando ${_entityLabel(envelope.entityType)}');
        final result = await _local.integrateRemote(
          envelope,
          downloadAsset: _remote.downloadAsset,
        );
        if (result == RemoteIntegrationResult.applied) downloaded++;
        if (result == RemoteIntegrationResult.conflict) conflictCount++;
      }

      var uploaded = 0;
      final uploadedEnvelopes = <SyncEnvelope>[];
      final localDevices = _local is DeviceSyncLocalStore
          ? _local as DeviceSyncLocalStore
          : null;
      final remoteDevices = _remote is DeviceSyncRemoteStore
          ? _remote as DeviceSyncRemoteStore
          : null;
      _onStage?.call('Preparando los cambios de este dispositivo');
      final sendingDevice = localDevices == null || remoteDevices == null
          ? null
          : await localDevices.buildCurrentDeviceSnapshot(
              recentChanges: const [],
            );
      while (true) {
        final pending = await _local.pending();
        if (pending.isEmpty) break;
        for (final change in pending) {
          final envelope = sendingDevice == null
              ? change.envelope
              : change.envelope.withDeviceSnapshot(sendingDevice);
          final effectiveChange = identical(envelope, change.envelope)
              ? change
              : PendingSyncEnvelope(
                  envelope: envelope,
                  outboxIds: change.outboxIds,
                );
          for (final asset in envelope.assets) {
            _onStage?.call('Subiendo una foto o un logo');
            if (!await _remote.hasAsset(asset.hash)) {
              final bytes = await _local.readAsset(asset);
              if (bytes == null) {
                throw StateError(
                  'No se encontró un archivo local para sincronizar.',
                );
              }
              await _remote.uploadAsset(asset, bytes);
            }
          }
          _onStage?.call('Subiendo un cambio a Google Drive');
          await _remote.push(envelope);
          await _local.markPushed(effectiveChange);
          uploadedEnvelopes.add(envelope);
          uploaded++;
        }
      }

      if (localDevices != null && remoteDevices != null) {
        _onStage?.call('Actualizando la lista de dispositivos');
        final recentChanges = [
          for (final envelope in uploadedEnvelopes)
            SyncDeviceChange.fromEnvelope(envelope),
        ]..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
        final current = await localDevices.buildCurrentDeviceSnapshot(
          recentChanges: recentChanges.take(50).toList(growable: false),
        );
        await remoteDevices.publishDeviceSnapshot(current);
        final currentId = await _local.deviceId();
        final snapshots =
            [
              for (final snapshot in await remoteDevices.fetchDeviceSnapshots())
                snapshot.copyWith(isCurrent: snapshot.deviceId == currentId),
            ]..sort((left, right) {
              if (left.isCurrent != right.isCurrent) {
                return left.isCurrent ? -1 : 1;
              }
              final leftTime = left.lastSyncedAt;
              final rightTime = right.lastSyncedAt;
              if (leftTime == null) return rightTime == null ? 0 : 1;
              if (rightTime == null) return -1;
              return rightTime.compareTo(leftTime);
            });
        await localDevices.saveDeviceSnapshots(snapshots);
      }
      return SyncRunResult(
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflictCount,
      );
    } finally {
      _running = false;
    }
  }

  List<SyncEnvelope> _ordered(List<SyncEnvelope> changes) {
    final byRevision = {for (final change in changes) change.revision: change};
    final depthCache = <String, int>{};
    int depth(SyncEnvelope change, Set<String> visiting) {
      final cached = depthCache[change.revision];
      if (cached != null) return cached;
      if (!visiting.add(change.revision)) return 0;
      var result = 0;
      final dependencies = <String>{
        if (change.baseRevision case final String revision) revision,
        ...change.resolvedRevisions,
      };
      for (final revision in dependencies) {
        final parent = byRevision[revision];
        if (parent == null) continue;
        final candidate = depth(parent, visiting) + 1;
        if (candidate > result) result = candidate;
      }
      visiting.remove(change.revision);
      depthCache[change.revision] = result;
      return result;
    }

    final result = [...changes];
    result.sort((left, right) {
      final priority = _priority(left.entityType)
          .compareTo(_priority(right.entityType));
      if (priority != 0) return priority;
      final leftDepth = depth(left, <String>{});
      final rightDepth = depth(right, <String>{});
      if (leftDepth != rightDepth) return leftDepth.compareTo(rightDepth);
      return left.changeId.compareTo(right.changeId);
    });
    return result;
  }

  int _priority(String type) => switch (type) {
    'measurementUnit' => 0,
    'materialCategory' || 'productCategory' => 1,
    'material' => 2,
    'product' => 3,
    'quote' => 4,
    _ => 5,
  };

  String _entityLabel(String type) => switch (type) {
    'appSettings' => 'la configuración',
    'measurementUnit' => 'una unidad de medida',
    'materialCategory' => 'una categoría de materia prima',
    'material' => 'una materia prima',
    'productCategory' => 'una categoría de producto',
    'product' => 'un producto o su foto',
    'quote' => 'un presupuesto',
    'priceListPreference' => 'una preferencia de lista de precios',
    'importRecord' => 'un registro de importación',
    'importReport' => 'un informe de importación',
    _ => 'datos de la app',
  };
}
