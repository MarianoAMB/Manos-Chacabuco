// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_info.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/sync_contracts.dart';
import '../../domain/sync/sync_models.dart';

final class SqliteSyncStore
    implements LocalSyncStore, SyncAccountStore, DeviceSyncLocalStore {
  SqliteSyncStore({
    required AppDatabase database,
    required Directory photoDirectory,
    required Directory logoDirectory,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _database = database,
       _photoDirectory = photoDirectory,
       _logoDirectory = logoDirectory,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final AppDatabase _database;
  final Directory _photoDirectory;
  final Directory _logoDirectory;
  final Uuid _uuid;
  final DateTime Function() _now;

  static const _deviceNameKey = 'sync_device_name';
  static const _deviceSnapshotsKey = 'sync_device_snapshots';

  static Future<SqliteSyncStore> openDefault(AppDatabase database) async {
    final support = await getApplicationSupportDirectory();
    final photos = Directory(paths.join(support.path, 'product_photos'));
    final logos = Directory(paths.join(support.path, 'business_assets'));
    await photos.create(recursive: true);
    await logos.create(recursive: true);
    return SqliteSyncStore(
      database: database,
      photoDirectory: photos,
      logoDirectory: logos,
    );
  }

  @override
  Future<String> deviceId() async {
    final rows = await _database.database.query(
      'sync_state',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['device_id'],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.single['value'] is String) {
      return rows.single['value']! as String;
    }
    final value = _uuid.v4();
    await _database.database.insert('sync_state', {
      'key': 'device_id',
      'value': value,
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return value;
  }

  @override
  Future<SyncDeviceSnapshot> buildCurrentDeviceSnapshot({
    required List<SyncDeviceChange> recentChanges,
  }) async {
    final id = await deviceId();
    final cached = await loadDeviceSnapshots();
    final previousOwn = cached.where((snapshot) => snapshot.deviceId == id);
    final changesById = <String, SyncDeviceChange>{
      if (previousOwn.isNotEmpty)
        for (final change in previousOwn.first.recentChanges)
          change.changeId: change,
      for (final change in recentChanges) change.changeId: change,
    };
    final effectiveChanges = changesById.values.toList(growable: false)
      ..sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    final counts = await Future.wait<int>([
      _activeCount('products'),
      _activeCount('materials'),
      _activeCount('quotes', hasActiveFlag: false),
    ]);
    return SyncDeviceSnapshot(
      deviceId: id,
      name: await _deviceName(id),
      platform: _platformName,
      appVersion: AppInfo.version,
      lastSyncedAt: _now().toUtc(),
      summary: SyncDataSummary(
        products: counts[0],
        materials: counts[1],
        quotes: counts[2],
      ),
      recentChanges: List<SyncDeviceChange>.unmodifiable(
        effectiveChanges.take(50),
      ),
      isCurrent: true,
    );
  }

  @override
  Future<List<SyncDeviceSnapshot>> loadDeviceSnapshots() async {
    final rows = await _database.database.query(
      'sync_state',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_deviceSnapshotsKey],
      limit: 1,
    );
    if (rows.isEmpty || rows.single['value'] is! String) return const [];
    try {
      final decoded = jsonDecode(rows.single['value']! as String);
      if (decoded is! List) return const [];
      final currentId = await deviceId();
      return [
        for (final item in decoded)
          if (item is Map)
            SyncDeviceSnapshot.fromJson(Map<String, Object?>.from(item))
                .copyWith(isCurrent: item['deviceId'] == currentId),
      ];
    } on Object {
      // A damaged optional cache must never prevent the local database opening.
      return const [];
    }
  }

  @override
  Future<void> saveDeviceSnapshots(List<SyncDeviceSnapshot> snapshots) async {
    await _database.database.insert('sync_state', {
      'key': _deviceSnapshotsKey,
      'value': jsonEncode([
        for (final snapshot in snapshots) snapshot.toJson(),
      ]),
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> renameCurrentDevice(String name) async {
    final value = name.trim();
    if (value.isEmpty || value.length > 50) {
      throw ArgumentError.value(
        name,
        'name',
        'Usá un nombre de entre 1 y 50 caracteres.',
      );
    }
    final id = await deviceId();
    await _database.database.insert('sync_state', {
      'key': _deviceNameKey,
      'value': value,
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final snapshots = await loadDeviceSnapshots();
    final hasCurrent = snapshots.any((snapshot) => snapshot.deviceId == id);
    final updated = [
      for (final snapshot in snapshots)
        snapshot.deviceId == id ? snapshot.copyWith(name: value) : snapshot,
      if (!hasCurrent)
        await buildCurrentDeviceSnapshot(recentChanges: const []),
    ];
    await saveDeviceSnapshots(updated);
  }

  @override
  Future<Set<String>> processedChangeIds() async {
    final rows = await _database.database.query(
      'sync_remote_changes',
      columns: const ['change_id'],
    );
    return rows.map((row) => row['change_id']! as String).toSet();
  }

  @override
  Future<List<PendingSyncEnvelope>> pending({int limit = 100}) async {
    final conflictRows = await _database.database.query(
      'sync_conflicts',
      columns: const ['entity_type', 'entity_id'],
      where: 'resolved_at IS NULL',
    );
    final blocked = {
      for (final row in conflictRows)
        '${row['entity_type']}\u0000${row['entity_id']}',
    };
    final rows = await _database.database.query(
      'sync_outbox',
      where: 'acknowledged_at IS NULL',
      orderBy: 'occurred_at, rowid',
    );
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final key = '${row['entity_type']}\u0000${row['entity_id']}';
      if (blocked.contains(key)) continue;
      grouped.putIfAbsent(key, () => []).add(row);
    }
    final result = <PendingSyncEnvelope>[];
    for (final entries in grouped.values.take(limit)) {
      final latest = entries.last;
      final entityType = latest['entity_type']! as String;
      final entityId = latest['entity_id']! as String;
      final payload = await _snapshot(entityType, entityId);
      final root = payload['root'];
      final rootMap = root is Map ? root : null;
      final deletedAtValue = rootMap?['deleted_at'] as String?;
      final isDelete = root == null || deletedAtValue != null;
      final state = await _entityState(entityType, entityId);
      final assets = await _assetReferences(entityType, payload);
      String? metadataBaseRevision;
      final resolvedRevisionSet = <String>{};
      for (final row in entries) {
        final metadata = _outboxMetadata(row['payload_json']);
        if (metadata['baseRevision'] case final String revision
            when revision.isNotEmpty) {
          metadataBaseRevision = revision;
        }
        for (final value
            in (metadata['resolvedRevisions'] as List<Object?>?) ?? const []) {
          if (value is String && value.isNotEmpty) {
            resolvedRevisionSet.add(value);
          }
        }
      }
      final resolvedRevisions = resolvedRevisionSet.toList(growable: false);
      final occurredAt = DateTime.parse(latest['occurred_at']! as String)
          .toUtc();
      result.add(
        PendingSyncEnvelope(
          outboxIds: [for (final row in entries) row['id']! as String],
          envelope: SyncEnvelope.create(
            changeId: latest['id']! as String,
            deviceId: await deviceId(),
            entityType: entityType,
            entityId: entityId,
            operation: isDelete ? SyncOperation.delete : SyncOperation.upsert,
            payload: payload,
            occurredAt: occurredAt,
            deletedAt: isDelete
                ? deletedAtValue == null
                      ? occurredAt
                      : DateTime.parse(deletedAtValue)
                : null,
            baseRevision: metadataBaseRevision ?? state?.baseRevision,
            resolvedRevisions: resolvedRevisions,
            assets: assets,
          ),
        ),
      );
    }
    if (result.isEmpty) return result;
    final snapshot = await buildCurrentDeviceSnapshot(
      recentChanges: [
        for (final pending in result)
          SyncDeviceChange.fromEnvelope(pending.envelope),
      ],
    );
    return [
      for (final pending in result)
        PendingSyncEnvelope(
          envelope: pending.envelope.withDeviceSnapshot(snapshot),
          outboxIds: pending.outboxIds,
        ),
    ];
  }

  @override
  Future<RemoteIntegrationResult> integrateRemote(
    SyncEnvelope envelope, {
    required Future<Uint8List?> Function(SyncAssetReference asset)
    downloadAsset,
  }) async {
    if (envelope.syncSchemaVersion != SyncEnvelope.currentSchemaVersion) {
      throw UnsupportedError('La versión remota no es compatible.');
    }
    if (await _isProcessed(envelope.changeId)) {
      return RemoteIntegrationResult.ignored;
    }

    final ownDevice = envelope.deviceId == await deviceId();
    if (ownDevice) {
      await _acknowledgeOwnRemote(envelope);
      return RemoteIntegrationResult.ignored;
    }

    for (final asset in envelope.assets) {
      await _ensureAsset(asset, downloadAsset);
    }
    final existingCandidates = await _unresolvedConflictCandidates(
      envelope.entityType,
      envelope.entityId,
    );
    if (existingCandidates.any(
      (candidate) =>
          candidate.envelope.changeId == envelope.changeId ||
          candidate.envelope.revision == envelope.revision,
    )) {
      await _markProcessed(envelope);
      return RemoteIntegrationResult.ignored;
    }
    if (existingCandidates.isNotEmpty) {
      final existingEnvelopes = [
        for (final candidate in existingCandidates) candidate.envelope,
      ];
      final isOlderThanExisting = existingEnvelopes.any(
        (candidate) =>
            candidate.baseRevision == envelope.revision ||
            candidate.resolvedRevisions.contains(envelope.revision),
      );
      if (isOlderThanExisting) {
        await _markProcessed(envelope);
        return RemoteIntegrationResult.ignored;
      }
      final supersededConflictIds = [
        for (final candidate in existingCandidates)
          if (envelope.baseRevision == candidate.envelope.revision ||
              envelope.resolvedRevisions.contains(candidate.envelope.revision))
            candidate.id,
      ];
      final state = await _entityState(envelope.entityType, envelope.entityId);
      final localPending = await _pendingFor(
        envelope.entityType,
        envelope.entityId,
      );
      final resolvedHeads = <String>{
        if (envelope.baseRevision case final String revision) revision,
        ...envelope.resolvedRevisions,
      };
      final conflictHeads = <String>{
        if (state?.baseRevision case final String revision) revision,
        for (final candidate in existingEnvelopes) candidate.revision,
      };
      if (!localPending &&
          conflictHeads.isNotEmpty &&
          conflictHeads.every(resolvedHeads.contains)) {
        await _applyAndRecord(
          envelope,
          clearPending: true,
          resolveConflicts: true,
        );
        return RemoteIntegrationResult.applied;
      }
      await _createConflict(
        envelope,
        await _snapshot(envelope.entityType, envelope.entityId),
        supersededConflictIds: supersededConflictIds,
      );
      return RemoteIntegrationResult.conflict;
    }
    final state = await _entityState(envelope.entityType, envelope.entityId);
    if (state?.baseRevision == envelope.revision) {
      await _markProcessed(envelope);
      return RemoteIntegrationResult.ignored;
    }

    final followsBase =
        envelope.baseRevision == state?.baseRevision ||
        envelope.resolvedRevisions.contains(state?.baseRevision);
    final localPending = await _pendingFor(
      envelope.entityType,
      envelope.entityId,
    );
    final localPayload = await _snapshot(
      envelope.entityType,
      envelope.entityId,
    );
    if (_comparableHash(localPayload) == _comparableHash(envelope.payload)) {
      await _applyAndRecord(envelope, clearPending: true);
      return RemoteIntegrationResult.applied;
    }
    if (followsBase && !localPending) {
      await _applyAndRecord(envelope);
      return RemoteIntegrationResult.applied;
    }

    await _createConflict(envelope, localPayload);
    return RemoteIntegrationResult.conflict;
  }

  @override
  Future<Uint8List?> readAsset(SyncAssetReference asset) async {
    final file = File(_assetPath(asset));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return syncHashBytes(bytes) == asset.hash ? bytes : null;
  }

  @override
  Future<void> markPushed(PendingSyncEnvelope pending) async {
    final envelope = pending.envelope;
    final timestamp = _timestamp(_now());
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'sync_outbox',
        {'acknowledged_at': timestamp},
        where:
            'id IN (${List.filled(pending.outboxIds.length, '?').join(',')})',
        whereArgs: pending.outboxIds,
      );
      await _saveEntityState(transaction, envelope, status: 'synced');
      await _insertProcessed(transaction, envelope, timestamp);
    });
  }

  @override
  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(
        await _database.database.rawQuery(
          'SELECT COUNT(*) FROM sync_outbox WHERE acknowledged_at IS NULL',
        ),
      ) ??
      0;

  @override
  Future<List<SyncConflict>> conflicts() async {
    final rows = await _database.database.query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'created_at',
    );
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final key = '${row['entity_type']}\u0000${row['entity_id']}';
      grouped.putIfAbsent(key, () => []).add(row);
    }
    final result = <SyncConflict>[];
    for (final entries in grouped.values) {
      final first = entries.first;
      final envelopesByRevision = <String, SyncEnvelope>{};
      for (final row in entries) {
        final envelope = _decodeEnvelope(
          row['remote_envelope_json']! as String,
        );
        envelopesByRevision[envelope.revision] = envelope;
      }
      final envelopes = envelopesByRevision.values.toList(growable: false);
      final entityType = first['entity_type']! as String;
      final entityId = first['entity_id']! as String;
      final localPayload = await _snapshot(entityType, entityId);
      result.add(
        SyncConflict(
          id: first['id']! as String,
          entityType: entityType,
          entityId: entityId,
          localPayload: localPayload,
          remoteEnvelope: envelopes.first,
          additionalRemoteEnvelopes: envelopes.skip(1).toList(growable: false),
          createdAt: DateTime.parse(first['created_at']! as String),
          localOccurredAt: _payloadUpdatedAt(localPayload),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> resolveConflict(
    String conflictId,
    SyncConflictResolution resolution, {
    String? remoteRevision,
  }) async {
    final selectedRows = await _database.database.query(
      'sync_conflicts',
      where: 'id = ? AND resolved_at IS NULL',
      whereArgs: [conflictId],
      limit: 1,
    );
    if (selectedRows.isEmpty) return;
    final selectedRow = selectedRows.single;
    final entityType = selectedRow['entity_type']! as String;
    final entityId = selectedRow['entity_id']! as String;
    final rows = await _database.database.query(
      'sync_conflicts',
      where: 'entity_type = ? AND entity_id = ? AND resolved_at IS NULL',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at',
    );
    final envelopes = <SyncEnvelope>[
      for (final row in rows)
        _decodeEnvelope(row['remote_envelope_json']! as String),
    ];
    final selectedEnvelope = remoteRevision == null
        ? _decodeEnvelope(selectedRow['remote_envelope_json']! as String)
        : envelopes.firstWhere(
            (envelope) => envelope.revision == remoteRevision,
            orElse: () =>
                throw StateError('La versión elegida ya no está disponible.'),
          );
    final state = await _entityState(entityType, entityId);
    final selectedRemote = resolution == SyncConflictResolution.useRemote;
    final baseRevision = selectedRemote
        ? selectedEnvelope.revision
        : state?.baseRevision;
    final selectedPayload = selectedRemote
        ? selectedEnvelope.payload
        : await _snapshot(entityType, entityId);
    final resolvedRevisions = <String>{
      if (state?.baseRevision case final String revision) revision,
      for (final envelope in envelopes) ...[
        if (envelope.baseRevision case final String revision) revision,
        envelope.revision,
        ...envelope.resolvedRevisions,
      ],
    }..remove(baseRevision);
    final timestamp = _timestamp(_now());
    await _database.database.transaction((transaction) async {
      if (selectedRemote) {
        await transaction.update('sync_runtime', {
          'remote_apply': 1,
        }, where: 'singleton_id = 1');
        try {
          await _applyPayload(transaction, selectedEnvelope);
        } finally {
          await transaction.update('sync_runtime', {
            'remote_apply': 0,
          }, where: 'singleton_id = 1');
        }
        await transaction.update(
          'sync_outbox',
          {'acknowledged_at': timestamp},
          where:
              'entity_type = ? AND entity_id = ? AND acknowledged_at IS NULL',
          whereArgs: [entityType, entityId],
        );
      }
      for (final envelope in envelopes) {
        await _insertProcessed(transaction, envelope, timestamp);
      }
      await transaction.insert('sync_entity_state', {
        'entity_type': entityType,
        'entity_id': entityId,
        'base_revision': baseRevision,
        'base_hash': syncHashJson(selectedPayload),
        'sync_status': 'pendingUpload',
        'error_message': null,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.update(
        'sync_conflicts',
        {'resolved_at': timestamp},
        where: 'entity_type = ? AND entity_id = ? AND resolved_at IS NULL',
        whereArgs: [entityType, entityId],
      );
      await transaction.insert('sync_outbox', {
        'id': _uuid.v4(),
        'entity_type': entityType,
        'entity_id': entityId,
        'operation': 'upsert',
        'payload_json': jsonEncode({
          'baseRevision': baseRevision,
          'resolvedRevisions': resolvedRevisions.toList()..sort(),
        }),
        'occurred_at': timestamp,
        'acknowledged_at': null,
      });
    });
  }

  @override
  Future<void> prepareFullUploadForNewAccount() async {
    const sources = <(String, String, String)>[
      ('app_settings', 'appSettings', "'singleton'"),
      ('measurement_units', 'measurementUnit', 'id'),
      ('material_categories', 'materialCategory', 'id'),
      ('materials', 'material', 'id'),
      ('product_categories', 'productCategory', 'id'),
      ('products', 'product', 'id'),
      ('quotes', 'quote', 'id'),
      ('price_list_preferences', 'priceListPreference', 'price_type'),
      ('import_records', 'importRecord', 'id'),
      ('import_reports', 'importReport', 'id'),
    ];
    final timestamp = _timestamp(_now());
    await _database.database.transaction((transaction) async {
      await transaction.update('sync_outbox', {
        'payload_json': '{}',
      }, where: 'acknowledged_at IS NULL');
      await transaction.delete(
        'sync_outbox',
        where: 'acknowledged_at IS NOT NULL',
      );
      await transaction.delete('sync_entity_state');
      await transaction.delete('sync_remote_changes');
      await transaction.delete('sync_conflicts');
      await transaction.delete(
        'sync_state',
        where: 'key = ?',
        whereArgs: const [_deviceSnapshotsKey],
      );
      for (final source in sources) {
        await transaction.rawInsert(
          '''
          INSERT INTO sync_outbox
            (id, entity_type, entity_id, operation, payload_json, occurred_at)
          SELECT lower(hex(randomblob(16))), ?, ${source.$3}, 'upsert', '{}', ?
          FROM ${source.$1}
        ''',
          [source.$2, timestamp],
        );
      }
    });
  }

  @override
  Future<SyncAccountState> load() async {
    final rows = await _database.database.query(
      'sync_account',
      where: 'singleton_id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return const SyncAccountState.disconnected();
    final row = rows.single;
    return SyncAccountState(
      connected: (row['connected']! as int) == 1,
      email: row['email'] as String?,
      lastSyncAt: switch (row['last_sync_at']) {
        final String value => DateTime.parse(value),
        _ => null,
      },
      lastError: row['last_error'] as String?,
    );
  }

  @override
  Future<void> save(SyncAccountState state) async {
    await _database.database.insert('sync_account', {
      'singleton_id': 1,
      'email': state.email,
      'connected': state.connected ? 1 : 0,
      'last_sync_at': state.lastSyncAt?.toUtc().toIso8601String(),
      'last_error': state.lastError,
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>> _snapshot(String type, String id) async {
    Future<Map<String, Object?>?> one(
      String table,
      String key,
      Object value,
    ) async {
      final rows = await _database.database.query(
        table,
        where: '$key = ?',
        whereArgs: [value],
        limit: 1,
      );
      return rows.isEmpty ? null : Map<String, Object?>.from(rows.single);
    }

    Future<List<Map<String, Object?>>> many(
      String table,
      String key,
      Object value,
    ) async => [
      for (final row in await _database.database.query(
        table,
        where: '$key = ?',
        whereArgs: [value],
        orderBy: 'id',
      ))
        Map<String, Object?>.from(row),
    ];

    return switch (type) {
      'appSettings' => {'root': await one('app_settings', 'singleton_id', 1)},
      'measurementUnit' => {'root': await one('measurement_units', 'id', id)},
      'materialCategory' => {
        'root': await one('material_categories', 'id', id),
      },
      'material' => {
        'root': await one('materials', 'id', id),
        'variants': await many('material_variants', 'material_id', id),
      },
      'productCategory' => {'root': await one('product_categories', 'id', id)},
      'product' => {
        'root': await one('products', 'id', id),
        'usages': await many('product_material_usages', 'product_id', id),
      },
      'quote' => {
        'root': await one('quotes', 'id', id),
        'items': await many('quote_items', 'quote_id', id),
        'adjustments': await many('quote_adjustments', 'quote_id', id),
      },
      'priceListPreference' => {
        'root': await one('price_list_preferences', 'price_type', id),
      },
      'importRecord' => {'root': await one('import_records', 'id', id)},
      'importReport' => {'root': await one('import_reports', 'id', id)},
      _ => throw UnsupportedError(
        'Entidad de sincronización desconocida: $type',
      ),
    };
  }

  Future<List<SyncAssetReference>> _assetReferences(
    String type,
    Map<String, Object?> payload,
  ) async {
    final root = payload['root'];
    if (root is! Map) return const [];
    final result = <SyncAssetReference>[];
    if (type == 'product' && root['photo_path'] is String) {
      final asset = await _assetReference(
        root['photo_path']! as String,
        'productPhoto',
        _photoDirectory,
      );
      if (asset != null) result.add(asset);
    }
    if (type == 'appSettings' && root['business_logo_path'] is String) {
      final asset = await _assetReference(
        root['business_logo_path']! as String,
        'businessLogo',
        _logoDirectory,
      );
      if (asset != null) result.add(asset);
    }
    return result;
  }

  Future<SyncAssetReference?> _assetReference(
    String reference,
    String kind,
    Directory directory,
  ) async {
    if (paths.basename(reference) != reference) return null;
    final file = File(paths.join(directory.path, reference));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return SyncAssetReference(
      hash: syncHashBytes(bytes),
      reference: reference,
      kind: kind,
      extension: paths.extension(reference).toLowerCase(),
    );
  }

  Future<void> _ensureAsset(
    SyncAssetReference asset,
    Future<Uint8List?> Function(SyncAssetReference asset) download,
  ) async {
    final destination = File(_assetPath(asset));
    if (await destination.exists()) {
      final existing = await destination.readAsBytes();
      if (syncHashBytes(existing) == asset.hash) return;
    }
    final bytes = await download(asset);
    if (bytes == null || syncHashBytes(bytes) != asset.hash) {
      throw StateError('La foto o el logo recibido está incompleto.');
    }
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.syncing');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  String _assetPath(SyncAssetReference asset) {
    if (paths.basename(asset.reference) != asset.reference) {
      throw ArgumentError('Referencia de archivo inválida.');
    }
    final directory = switch (asset.kind) {
      'productPhoto' => _photoDirectory,
      'businessLogo' => _logoDirectory,
      _ => throw UnsupportedError('Tipo de archivo desconocido.'),
    };
    return paths.join(directory.path, asset.reference);
  }

  Future<bool> _pendingFor(String type, String id) async =>
      (Sqflite.firstIntValue(
            await _database.database.rawQuery(
              '''
                SELECT COUNT(*) FROM sync_outbox
                WHERE entity_type = ? AND entity_id = ?
                  AND acknowledged_at IS NULL
              ''',
              [type, id],
            ),
          ) ??
          0) >
      0;

  Future<bool> _isProcessed(String changeId) async =>
      (Sqflite.firstIntValue(
            await _database.database.rawQuery(
              'SELECT COUNT(*) FROM sync_remote_changes WHERE change_id = ?',
              [changeId],
            ),
          ) ??
          0) >
      0;

  Future<List<({String id, SyncEnvelope envelope})>>
  _unresolvedConflictCandidates(String entityType, String entityId) async {
    final rows = await _database.database.query(
      'sync_conflicts',
      columns: const ['id', 'remote_envelope_json'],
      where: 'entity_type = ? AND entity_id = ? AND resolved_at IS NULL',
      whereArgs: [entityType, entityId],
    );
    return [
      for (final row in rows)
        (
          id: row['id']! as String,
          envelope: _decodeEnvelope(row['remote_envelope_json']! as String),
        ),
    ];
  }

  SyncEnvelope _decodeEnvelope(String encoded) => SyncEnvelope.fromJson(
    Map<String, Object?>.from(jsonDecode(encoded) as Map),
  );

  Future<_EntityState?> _entityState(String type, String id) async {
    final rows = await _database.database.query(
      'sync_entity_state',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [type, id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _EntityState(
      baseRevision: rows.single['base_revision'] as String?,
      baseHash: rows.single['base_hash'] as String?,
    );
  }

  Future<void> _applyAndRecord(
    SyncEnvelope envelope, {
    bool clearPending = false,
    bool resolveConflicts = false,
  }) async {
    final timestamp = _timestamp(_now());
    await _database.database.transaction((transaction) async {
      await transaction.update('sync_runtime', {
        'remote_apply': 1,
      }, where: 'singleton_id = 1');
      try {
        await _applyPayload(transaction, envelope);
      } finally {
        await transaction.update('sync_runtime', {
          'remote_apply': 0,
        }, where: 'singleton_id = 1');
      }
      if (clearPending) {
        await transaction.update(
          'sync_outbox',
          {'acknowledged_at': timestamp},
          where:
              'entity_type = ? AND entity_id = ? AND acknowledged_at IS NULL',
          whereArgs: [envelope.entityType, envelope.entityId],
        );
      }
      if (resolveConflicts) {
        await transaction.update(
          'sync_conflicts',
          {'resolved_at': timestamp},
          where: 'entity_type = ? AND entity_id = ? AND resolved_at IS NULL',
          whereArgs: [envelope.entityType, envelope.entityId],
        );
      }
      await _saveEntityState(transaction, envelope, status: 'synced');
      await _insertProcessed(transaction, envelope, timestamp);
    });
  }

  Future<void> _applyPayload(
    DatabaseExecutor executor,
    SyncEnvelope envelope,
  ) async {
    final root = _mapOrNull(envelope.payload['root']);
    if (root == null) {
      final target = _rootTarget(envelope.entityType);
      await executor.delete(
        target.table,
        where: '${target.key} = ?',
        whereArgs: [target.key == 'singleton_id' ? 1 : envelope.entityId],
      );
      return;
    }
    switch (envelope.entityType) {
      case 'appSettings':
        await _upsert(executor, 'app_settings', 'singleton_id', 1, root);
      case 'measurementUnit':
        await _upsert(
          executor,
          'measurement_units',
          'id',
          envelope.entityId,
          root,
        );
      case 'materialCategory':
        await _upsert(
          executor,
          'material_categories',
          'id',
          envelope.entityId,
          root,
        );
      case 'material':
        await _upsert(executor, 'materials', 'id', envelope.entityId, root);
        await _replaceChildren(
          executor,
          'material_variants',
          'material_id',
          envelope.entityId,
          envelope.payload['variants'],
        );
      case 'productCategory':
        await _upsert(
          executor,
          'product_categories',
          'id',
          envelope.entityId,
          root,
        );
      case 'product':
        await _upsert(executor, 'products', 'id', envelope.entityId, root);
        await _replaceChildren(
          executor,
          'product_material_usages',
          'product_id',
          envelope.entityId,
          envelope.payload['usages'],
        );
      case 'quote':
        await _upsert(executor, 'quotes', 'id', envelope.entityId, root);
        await _replaceChildren(
          executor,
          'quote_items',
          'quote_id',
          envelope.entityId,
          envelope.payload['items'],
        );
        await _replaceChildren(
          executor,
          'quote_adjustments',
          'quote_id',
          envelope.entityId,
          envelope.payload['adjustments'],
        );
      case 'priceListPreference':
        await _upsert(
          executor,
          'price_list_preferences',
          'price_type',
          envelope.entityId,
          root,
        );
      case 'importRecord':
        await _upsert(
          executor,
          'import_records',
          'id',
          envelope.entityId,
          root,
        );
      case 'importReport':
        await _upsert(
          executor,
          'import_reports',
          'id',
          envelope.entityId,
          root,
        );
      default:
        throw UnsupportedError('Entidad remota desconocida.');
    }
  }

  Future<void> _replaceChildren(
    DatabaseExecutor executor,
    String table,
    String parentKey,
    String parentId,
    Object? value,
  ) async {
    if (value is! List) return;
    final rows = [
      for (final item in value) Map<String, Object?>.from(item! as Map),
    ];
    final ids = [for (final row in rows) row['id']!];
    await executor.delete(
      table,
      where: ids.isEmpty
          ? '$parentKey = ?'
          : '$parentKey = ? AND id NOT IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: [parentId, ...ids],
    );
    for (final row in rows) {
      await _upsert(executor, table, 'id', row['id']!, row);
    }
  }

  Future<void> _upsert(
    DatabaseExecutor executor,
    String table,
    String key,
    Object value,
    Map<String, Object?> row,
  ) async {
    final updated = await executor.update(
      table,
      row,
      where: '$key = ?',
      whereArgs: [value],
    );
    if (updated == 0) await executor.insert(table, row);
  }

  _RootTarget _rootTarget(String type) => switch (type) {
    'appSettings' => const _RootTarget('app_settings', 'singleton_id'),
    'measurementUnit' => const _RootTarget('measurement_units', 'id'),
    'materialCategory' => const _RootTarget('material_categories', 'id'),
    'material' => const _RootTarget('materials', 'id'),
    'productCategory' => const _RootTarget('product_categories', 'id'),
    'product' => const _RootTarget('products', 'id'),
    'quote' => const _RootTarget('quotes', 'id'),
    'priceListPreference' => const _RootTarget(
      'price_list_preferences',
      'price_type',
    ),
    'importRecord' => const _RootTarget('import_records', 'id'),
    'importReport' => const _RootTarget('import_reports', 'id'),
    _ => throw UnsupportedError('Entidad remota desconocida.'),
  };

  Future<void> _acknowledgeOwnRemote(SyncEnvelope envelope) async {
    final timestamp = _timestamp(_now());
    await _database.database.transaction((transaction) async {
      await transaction.update(
        'sync_outbox',
        {'acknowledged_at': timestamp},
        where: '''
          entity_type = ? AND entity_id = ? AND acknowledged_at IS NULL
          AND occurred_at <= ?
        ''',
        whereArgs: [
          envelope.entityType,
          envelope.entityId,
          envelope.occurredAt.toUtc().toIso8601String(),
        ],
      );
      await _saveEntityState(transaction, envelope, status: 'synced');
      await _insertProcessed(transaction, envelope, timestamp);
    });
  }

  Future<void> _createConflict(
    SyncEnvelope envelope,
    Map<String, Object?> localPayload, {
    List<String> supersededConflictIds = const [],
  }) async {
    final timestamp = _timestamp(_now());
    final currentState = await _entityState(
      envelope.entityType,
      envelope.entityId,
    );
    await _database.database.transaction((transaction) async {
      if (supersededConflictIds.isNotEmpty) {
        await transaction.update(
          'sync_conflicts',
          {'resolved_at': timestamp},
          where:
              'id IN (${List.filled(supersededConflictIds.length, '?').join(',')})',
          whereArgs: supersededConflictIds,
        );
      }
      await transaction.insert('sync_conflicts', {
        'id': _uuid.v4(),
        'entity_type': envelope.entityType,
        'entity_id': envelope.entityId,
        'local_payload_json': jsonEncode(localPayload),
        'remote_envelope_json': envelope.encode(),
        'created_at': timestamp,
        'resolved_at': null,
      });
      await transaction.insert('sync_entity_state', {
        'entity_type': envelope.entityType,
        'entity_id': envelope.entityId,
        'base_revision': currentState?.baseRevision,
        'base_hash': syncHashJson(localPayload),
        'sync_status': 'conflict',
        'error_message': null,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _insertProcessed(transaction, envelope, timestamp);
    });
  }

  Future<void> _markProcessed(SyncEnvelope envelope) async {
    await _database.database.insert('sync_remote_changes', {
      'change_id': envelope.changeId,
      'revision': envelope.revision,
      'processed_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _saveEntityState(
    DatabaseExecutor executor,
    SyncEnvelope envelope, {
    required String status,
  }) async {
    await executor.insert('sync_entity_state', {
      'entity_type': envelope.entityType,
      'entity_id': envelope.entityId,
      'base_revision': envelope.revision,
      'base_hash': envelope.payloadHash,
      'sync_status': status,
      'error_message': null,
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _insertProcessed(
    DatabaseExecutor executor,
    SyncEnvelope envelope,
    String timestamp,
  ) async {
    await executor.insert('sync_remote_changes', {
      'change_id': envelope.changeId,
      'revision': envelope.revision,
      'processed_at': timestamp,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> _activeCount(String table, {bool hasActiveFlag = true}) async =>
      Sqflite.firstIntValue(
        await _database.database.rawQuery(
          'SELECT COUNT(*) FROM $table '
          'WHERE deleted_at IS NULL${hasActiveFlag ? ' AND is_active = 1' : ''}',
        ),
      ) ??
      0;

  Future<String> _deviceName(String id) async {
    final rows = await _database.database.query(
      'sync_state',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_deviceNameKey],
      limit: 1,
    );
    final stored = rows.isEmpty ? null : rows.single['value'];
    if (stored is String) {
      final trimmed = stored.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    final compactId = id.replaceAll('-', '');
    final suffix =
        (compactId.length <= 4 ? compactId : compactId.substring(0, 4))
            .toUpperCase();
    final hostname = Platform.localHostname.trim();
    final generated = Platform.isWindows && hostname.isNotEmpty
        ? 'PC $hostname'
        : Platform.isWindows
        ? 'PC $suffix'
        : Platform.isAndroid
        ? 'Android $suffix'
        : '${Platform.operatingSystem} $suffix';
    await _database.database.insert('sync_state', {
      'key': _deviceNameKey,
      'value': generated,
      'updated_at': _timestamp(_now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return generated;
  }

  String get _platformName => Platform.isWindows
      ? 'Windows'
      : Platform.isAndroid
      ? 'Android'
      : Platform.operatingSystem;

  Map<String, Object?> _outboxMetadata(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } on Object {
      return const {};
    }
  }

  DateTime? _payloadUpdatedAt(Map<String, Object?> payload) {
    final root = payload['root'];
    if (root is! Map || root['updated_at'] is! String) return null;
    return DateTime.tryParse(root['updated_at']! as String)?.toUtc();
  }

  Map<String, Object?>? _mapOrNull(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;

  String _comparableHash(Map<String, Object?> payload) =>
      syncHashJson(_withoutLocalTimestamps(payload));

  Object? _withoutLocalTimestamps(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'created_at' && entry.key != 'updated_at')
            entry.key.toString(): _withoutLocalTimestamps(entry.value),
      };
    }
    if (value is List) {
      return [for (final item in value) _withoutLocalTimestamps(item)];
    }
    return value;
  }

  String _timestamp(DateTime value) => value.toUtc().toIso8601String();
}

final class _EntityState {
  const _EntityState({required this.baseRevision, required this.baseHash});

  final String? baseRevision;
  final String? baseHash;
}

final class _RootTarget {
  const _RootTarget(this.table, this.key);

  final String table;
  final String key;
}
