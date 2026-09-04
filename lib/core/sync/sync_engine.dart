// ignore_for_file: prefer_initializing_formals

import '../../domain/sync/sync_models.dart';
import 'sync_contracts.dart';

final class SyncEngine {
  SyncEngine({required LocalSyncStore local, required RemoteSyncStore remote})
    : _local = local,
      _remote = remote;

  final LocalSyncStore _local;
  final RemoteSyncStore _remote;
  bool _running = false;

  Future<SyncRunResult> synchronize() async {
    if (_running) {
      return const SyncRunResult(uploaded: 0, downloaded: 0, conflicts: 0);
    }
    _running = true;
    try {
      var downloaded = 0;
      var conflictCount = 0;
      final known = await _local.processedChangeIds();
      final remoteChanges = await _remote.pull(knownChangeIds: known);
      for (final envelope in _ordered(remoteChanges)) {
        final result = await _local.integrateRemote(
          envelope,
          downloadAsset: _remote.downloadAsset,
        );
        if (result == RemoteIntegrationResult.applied) downloaded++;
        if (result == RemoteIntegrationResult.conflict) conflictCount++;
      }

      var uploaded = 0;
      while (true) {
        final pending = await _local.pending();
        if (pending.isEmpty) break;
        for (final change in pending) {
          for (final asset in change.envelope.assets) {
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
          await _remote.push(change.envelope);
          await _local.markPushed(change);
          uploaded++;
        }
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
      final parent = change.baseRevision == null
          ? null
          : byRevision[change.baseRevision];
      final result = parent == null ? 0 : depth(parent, visiting) + 1;
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
}
