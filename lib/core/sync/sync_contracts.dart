enum SyncOperation { upsert, delete }

final class SyncChange {
  const SyncChange({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.occurredAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final SyncOperation operation;
  final Map<String, Object?> payload;
  final DateTime occurredAt;
}

final class RemoteChangeBatch {
  const RemoteChangeBatch({required this.changes, required this.nextCursor});

  final List<SyncChange> changes;
  final String? nextCursor;
}

/// Transporte remoto. Google Drive será una implementación futura.
abstract interface class SyncGateway {
  Future<RemoteChangeBatch> pull({String? afterCursor});
  Future<void> push(List<SyncChange> changes);
}

/// Persistencia local de la bandeja de salida y el cursor remoto.
abstract interface class SyncRepository {
  Future<List<SyncChange>> pending({int limit = 100});
  Future<void> acknowledge(Iterable<String> changeIds);
  Future<String?> readCursor();
  Future<void> saveCursor(String? cursor);
}
