// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_contracts.dart';
import '../../domain/sync/sync_models.dart';

final class SqliteSyncStore implements LocalSyncStore, SyncAccountStore {
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
            baseRevision: state?.baseRevision,
            assets: assets,
          ),
        ),
      );
    }
    return result;
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
    final existingConflict = Sqflite.firstIntValue(
      await _database.database.rawQuery(
        '''
          SELECT COUNT(*) FROM sync_conflicts
          WHERE entity_type = ? AND entity_id = ? AND resolved_at IS NULL
        ''',
        [envelope.entityType, envelope.entityId],
      ),
    );
    if ((existingConflict ?? 0) > 0) {
      return RemoteIntegrationResult.ignored;
    }

    for (final asset in envelope.assets) {
      await _ensureAsset(asset, downloadAsset);
    }
    final state = await _entityState(envelope.entityType, envelope.entityId);
    if (state?.baseRevision == envelope.revision) {
      await _markProcessed(envelope);
      return RemoteIntegrationResult.ignored;
    }

    final ownDevice = envelope.deviceId == await deviceId();
    if (ownDevice) {
      await _acknowledgeOwnRemote(envelope);
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
    return [
      for (final row in rows)
        SyncConflict(
          id: row['id']! as String,
          entityType: row['entity_type']! as String,
          entityId: row['entity_id']! as String,
          localPayload: Map<String, Object?>.from(
            jsonDecode(row['local_payload_json']! as String) as Map,
          ),
          remoteEnvelope: SyncEnvelope.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['remote_envelope_json']! as String) as Map,
            ),
          ),
          createdAt: DateTime.parse(row['created_at']! as String),
        ),
    ];
  }

  @override
  Future<void> resolveConflict(
    String conflictId,
    SyncConflictResolution resolution,
  ) async {
    final rows = await _database.database.query(
      'sync_conflicts',
      where: 'id = ? AND resolved_at IS NULL',
      whereArgs: [conflictId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final row = rows.single;
    final envelope = SyncEnvelope.fromJson(
      Map<String, Object?>.from(
        jsonDecode(row['remote_envelope_json']! as String) as Map,
      ),
    );
    if (resolution == SyncConflictResolution.useRemote) {
      await _applyAndRecord(envelope, clearPending: true);
    } else {
      final timestamp = _timestamp(_now());
      await _database.database.transaction((transaction) async {
        await _saveEntityState(transaction, envelope, status: 'pendingUpload');
        await _insertProcessed(transaction, envelope, timestamp);
      });
    }
    await _database.database.update(
      'sync_conflicts',
      {'resolved_at': _timestamp(_now())},
      where: 'id = ?',
      whereArgs: [conflictId],
    );
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
      await transaction.delete(
        'sync_outbox',
        where: 'acknowledged_at IS NOT NULL',
      );
      await transaction.delete('sync_entity_state');
      await transaction.delete('sync_remote_changes');
      await transaction.delete('sync_conflicts');
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
    Map<String, Object?> localPayload,
  ) async {
    final timestamp = _timestamp(_now());
    final currentState = await _entityState(
      envelope.entityType,
      envelope.entityId,
    );
    await _database.database.transaction((transaction) async {
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
