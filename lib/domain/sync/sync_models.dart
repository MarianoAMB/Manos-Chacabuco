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

final class SyncDataSummary {
  const SyncDataSummary({
    this.products = 0,
    this.materials = 0,
    this.quotes = 0,
  });

  final int products;
  final int materials;
  final int quotes;

  Map<String, Object?> toJson() => {
    'products': products,
    'materials': materials,
    'quotes': quotes,
  };

  factory SyncDataSummary.fromJson(Map<String, Object?> json) =>
      SyncDataSummary(
        products: (json['products'] as num?)?.toInt() ?? 0,
        materials: (json['materials'] as num?)?.toInt() ?? 0,
        quotes: (json['quotes'] as num?)?.toInt() ?? 0,
      );
}

final class SyncDeviceChange {
  const SyncDeviceChange({
    required this.changeId,
    required this.revision,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.occurredAt,
    this.label,
  });

  final String changeId;
  final String revision;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final DateTime occurredAt;
  final String? label;

  factory SyncDeviceChange.fromEnvelope(SyncEnvelope envelope) =>
      SyncDeviceChange(
        changeId: envelope.changeId,
        revision: envelope.revision,
        entityType: envelope.entityType,
        entityId: envelope.entityId,
        operation: envelope.operation,
        occurredAt: envelope.occurredAt,
        label: _syncPayloadLabel(envelope.entityType, envelope.payload),
      );

  Map<String, Object?> toJson() => {
    'changeId': changeId,
    'revision': revision,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    if (label != null) 'label': label,
  };

  factory SyncDeviceChange.fromJson(Map<String, Object?> json) =>
      SyncDeviceChange(
        changeId: json['changeId']! as String,
        revision: (json['revision'] as String?) ?? '',
        entityType: json['entityType']! as String,
        entityId: json['entityId']! as String,
        operation: SyncOperation.values.byName(json['operation']! as String),
        occurredAt: DateTime.parse(json['occurredAt']! as String).toUtc(),
        label: json['label'] as String?,
      );
}

final class SyncDeviceSnapshot {
  const SyncDeviceSnapshot({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.appVersion,
    required this.summary,
    this.lastSyncedAt,
    this.recentChanges = const [],
    this.isCurrent = false,
  });

  static const currentSchemaVersion = 1;

  final String deviceId;
  final String name;
  final String platform;
  final String appVersion;
  final DateTime? lastSyncedAt;
  final SyncDataSummary summary;
  final List<SyncDeviceChange> recentChanges;

  /// Estado local de presentación. Nunca se persiste en Google Drive.
  final bool isCurrent;

  SyncDeviceSnapshot copyWith({
    String? deviceId,
    String? name,
    String? platform,
    String? appVersion,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    SyncDataSummary? summary,
    List<SyncDeviceChange>? recentChanges,
    bool? isCurrent,
  }) => SyncDeviceSnapshot(
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    appVersion: appVersion ?? this.appVersion,
    lastSyncedAt: clearLastSyncedAt ? null : lastSyncedAt ?? this.lastSyncedAt,
    summary: summary ?? this.summary,
    recentChanges: recentChanges ?? this.recentChanges,
    isCurrent: isCurrent ?? this.isCurrent,
  );

  Map<String, Object?> toJson() => {
    'syncDeviceSchemaVersion': currentSchemaVersion,
    'deviceId': deviceId,
    'name': name,
    'platform': platform,
    'appVersion': appVersion,
    'lastSyncedAt': lastSyncedAt?.toUtc().toIso8601String(),
    'summary': summary.toJson(),
    'recentChanges': [for (final change in recentChanges) change.toJson()],
  };

  factory SyncDeviceSnapshot.fromJson(Map<String, Object?> json) {
    final version = (json['syncDeviceSchemaVersion'] as num?)?.toInt() ?? 1;
    if (version > currentSchemaVersion) {
      throw UnsupportedError(
        'La versión de información del dispositivo $version no es compatible.',
      );
    }
    final summary = json['summary'];
    return SyncDeviceSnapshot(
      deviceId: (json['deviceId'] ?? json['id'])! as String,
      name: (json['name'] as String?) ?? 'Dispositivo',
      platform: (json['platform'] as String?) ?? 'unknown',
      appVersion: (json['appVersion'] as String?) ?? '',
      lastSyncedAt: switch (json['lastSyncedAt']) {
        final String value => DateTime.parse(value).toUtc(),
        _ => null,
      },
      summary: summary is Map
          ? SyncDataSummary.fromJson(Map<String, Object?>.from(summary))
          : const SyncDataSummary(),
      recentChanges: [
        for (final item
            in (json['recentChanges'] as List<Object?>?) ?? const <Object?>[])
          SyncDeviceChange.fromJson(Map<String, Object?>.from(item! as Map)),
      ],
    );
  }
}

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
    this.deviceName,
    this.devicePlatform,
    this.deviceAppVersion,
    this.deviceSummary,
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
  final String? deviceName;
  final String? devicePlatform;
  final String? deviceAppVersion;
  final SyncDataSummary? deviceSummary;

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
    String? deviceName,
    String? devicePlatform,
    String? deviceAppVersion,
    SyncDataSummary? deviceSummary,
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
      deviceName: deviceName,
      devicePlatform: devicePlatform,
      deviceAppVersion: deviceAppVersion,
      deviceSummary: deviceSummary,
    );
  }

  SyncEnvelope withDeviceSnapshot(SyncDeviceSnapshot snapshot) => SyncEnvelope(
    syncSchemaVersion: syncSchemaVersion,
    changeId: changeId,
    deviceId: deviceId,
    entityType: entityType,
    entityId: entityId,
    operation: operation,
    payload: payload,
    payloadHash: payloadHash,
    occurredAt: occurredAt,
    revision: revision,
    assets: assets,
    baseRevision: baseRevision,
    deletedAt: deletedAt,
    resolvedRevisions: resolvedRevisions,
    deviceName: snapshot.name,
    devicePlatform: snapshot.platform,
    deviceAppVersion: snapshot.appVersion,
    deviceSummary: snapshot.summary,
  );

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
    if (deviceName != null) 'deviceName': deviceName,
    if (devicePlatform != null) 'devicePlatform': devicePlatform,
    if (deviceAppVersion != null) 'deviceAppVersion': deviceAppVersion,
    if (deviceSummary != null) 'deviceSummary': deviceSummary!.toJson(),
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
      deviceName: json['deviceName'] as String?,
      devicePlatform: json['devicePlatform'] as String?,
      deviceAppVersion: json['deviceAppVersion'] as String?,
      deviceSummary: switch (json['deviceSummary']) {
        final Map value => SyncDataSummary.fromJson(
          Map<String, Object?>.from(value),
        ),
        _ => null,
      },
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
    this.additionalRemoteEnvelopes = const [],
    this.localOccurredAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Map<String, Object?> localPayload;
  final SyncEnvelope remoteEnvelope;
  final List<SyncEnvelope> additionalRemoteEnvelopes;
  final DateTime createdAt;
  final DateTime? localOccurredAt;

  List<SyncEnvelope> get remoteEnvelopes {
    final byRevision = <String, SyncEnvelope>{
      remoteEnvelope.revision: remoteEnvelope,
      for (final envelope in additionalRemoteEnvelopes)
        envelope.revision: envelope,
    };
    return List.unmodifiable(byRevision.values);
  }

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
    if (entityType == 'appSettings') return 'La configuración';
    final root = localPayload['root'];
    if (root is Map) {
      final name = root['name'] ?? root['customer_name'];
      if (name is String && name.trim().isNotEmpty) return name;
    }
    return 'Cambio en $entityLabel';
  }
}

String? _syncPayloadLabel(String entityType, Map<String, Object?> payload) {
  if (entityType == 'appSettings') return 'Configuración';
  final root = payload['root'];
  if (root is! Map) return null;
  final value = root['name'] ?? root['customer_name'] ?? root['description'];
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
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
