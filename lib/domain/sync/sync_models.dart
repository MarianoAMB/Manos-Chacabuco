import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum SyncOperation { upsert, delete }

enum SyncConnectionStatus {
  notConfigured,
  disconnected,
  offline,
  syncing,
  pending,
  synchronized,
  conflict,
  error,
}

enum SyncConflictResolution { useLocal, useRemote }

final class SyncAssetReference {
  const SyncAssetReference({
    required this.hash,
    required this.reference,
    required this.kind,
    required this.extension,
  });

  final String hash;
  final String reference;
  final String kind;
  final String extension;

  Map<String, Object?> toJson() => {
    'hash': hash,
    'reference': reference,
    'kind': kind,
    'extension': extension,
  };

  factory SyncAssetReference.fromJson(Map<String, Object?> json) =>
      SyncAssetReference(
        hash: json['hash']! as String,
        reference: json['reference']! as String,
        kind: json['kind']! as String,
        extension: json['extension']! as String,
      );
}

final class SyncEnvelope {
  const SyncEnvelope({
    required this.syncSchemaVersion,
    required this.changeId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.payloadHash,
    required this.occurredAt,
    required this.revision,
    required this.assets,
    this.baseRevision,
    this.deletedAt,
    this.resolvedRevisions = const [],
  });

  static const currentSchemaVersion = 1;

  final int syncSchemaVersion;
  final String changeId;
  final String deviceId;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, Object?> payload;
  final String payloadHash;
  final DateTime occurredAt;
  final DateTime? deletedAt;
  final String? baseRevision;
  final String revision;
  final List<String> resolvedRevisions;
  final List<SyncAssetReference> assets;

  factory SyncEnvelope.create({
    required String changeId,
    required String deviceId,
    required String entityType,
    required String entityId,
    required SyncOperation operation,
    required Map<String, Object?> payload,
    required DateTime occurredAt,
    required List<SyncAssetReference> assets,
    String? baseRevision,
    DateTime? deletedAt,
    List<String> resolvedRevisions = const [],
  }) {
    final payloadHash = syncHashJson(payload);
    final revision = syncHashJson({
      'schemaVersion': currentSchemaVersion,
      'changeId': changeId,
      'deviceId': deviceId,
      'entityType': entityType,
      'entityId': entityId,
      'operation': operation.name,
      'payloadHash': payloadHash,
      'baseRevision': baseRevision,
      'deletedAt': deletedAt?.toUtc().toIso8601String(),
      'resolvedRevisions': [...resolvedRevisions]..sort(),
      'assets': [for (final asset in assets) asset.toJson()],
    });
    return SyncEnvelope(
      syncSchemaVersion: currentSchemaVersion,
      changeId: changeId,
      deviceId: deviceId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: payload,
      payloadHash: payloadHash,
      occurredAt: occurredAt.toUtc(),
      deletedAt: deletedAt?.toUtc(),
      baseRevision: baseRevision,
      revision: revision,
      resolvedRevisions: List.unmodifiable(resolvedRevisions),
      assets: List.unmodifiable(assets),
    );
  }

  Map<String, Object?> toJson() => {
    'syncSchemaVersion': syncSchemaVersion,
    'changeId': changeId,
    'deviceId': deviceId,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation.name,
    'payload': payload,
    'payloadHash': payloadHash,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'baseRevision': baseRevision,
    'revision': revision,
    'resolvedRevisions': resolvedRevisions,
    'assets': [for (final asset in assets) asset.toJson()],
  };

  factory SyncEnvelope.fromJson(Map<String, Object?> json) {
    final version = json['syncSchemaVersion']! as int;
    if (version != currentSchemaVersion) {
      throw UnsupportedError(
        'La versión de sincronización $version no es compatible.',
      );
    }
    return SyncEnvelope(
      syncSchemaVersion: version,
      changeId: json['changeId']! as String,
      deviceId: json['deviceId']! as String,
      entityType: json['entityType']! as String,
      entityId: json['entityId']! as String,
      operation: SyncOperation.values.byName(json['operation']! as String),
      payload: Map<String, Object?>.from(json['payload']! as Map),
      payloadHash: json['payloadHash']! as String,
      occurredAt: DateTime.parse(json['occurredAt']! as String).toUtc(),
      deletedAt: switch (json['deletedAt']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      baseRevision: json['baseRevision'] as String?,
      revision: json['revision']! as String,
      resolvedRevisions: List<String>.from(
        (json['resolvedRevisions'] as List<Object?>?) ?? const [],
      ),
      assets: [
        for (final item
            in (json['assets'] as List<Object?>?) ?? const <Object?>[])
          SyncAssetReference.fromJson(Map<String, Object?>.from(item! as Map)),
      ],
    );
  }

  String encode() => jsonEncode(toJson());
}

final class PendingSyncEnvelope {
  const PendingSyncEnvelope({required this.envelope, required this.outboxIds});

  final SyncEnvelope envelope;
  final List<String> outboxIds;
}

final class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.localPayload,
    required this.remoteEnvelope,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Map<String, Object?> localPayload;
  final SyncEnvelope remoteEnvelope;
  final DateTime createdAt;

  String get entityLabel => switch (entityType) {
    'product' => 'producto',
    'material' => 'materia prima',
    'quote' => 'presupuesto',
    'appSettings' => 'configuración',
    'productCategory' || 'materialCategory' => 'categoría',
    'priceListPreference' => 'preferencia de lista',
    _ => 'dato',
  };

  String get title {
    final root = localPayload['root'];
    if (root is Map) {
      final name =
          root['name'] ?? root['customer_name'] ?? root['business_name'];
      if (name is String && name.trim().isNotEmpty) return name;
    }
    return 'Cambio en $entityLabel';
  }
}

final class SyncRunResult {
  const SyncRunResult({
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
  });

  final int uploaded;
  final int downloaded;
  final int conflicts;
}

String syncHashBytes(Uint8List bytes) => sha256.convert(bytes).toString();

String syncHashJson(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalize(value)))).toString();

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return [for (final item in value) _canonicalize(item)];
  return value;
}
