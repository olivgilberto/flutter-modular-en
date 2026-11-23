import 'dart:convert';

/// What a queue operation asks of the backend (chapter 12).
enum TaskOperationKind { create, update, archive }

/// A row of `outbox_pending_operations`, as the send reads it.
final class TaskOperation {
  const TaskOperation({
    required this.id,
    required this.entityId,
    required this.kind,
    required this.payload,
    this.baseVersion,
  });

  /// Reads the queue row. A malformed row is a `FormatException`; the
  /// service turns it into a `LocalDatabaseError`.
  factory TaskOperation.fromMap(Map<String, Object?> row) {
    final payload = switch (row['payload']) {
      final String json => jsonDecode(json),
      _ => null,
    };
    final kind = switch (row['operation']) {
      final String name => TaskOperationKind.values.asNameMap()[name],
      _ => null,
    };
    return switch (row) {
      {
        'id': final String id,
        'entity_id': final String entityId,
        'base_version': final int? baseVersion,
      }
          when kind != null && payload is Map<String, Object?> =>
        TaskOperation(
          id: id,
          entityId: entityId,
          kind: kind,
          payload: payload,
          baseVersion: baseVersion,
        ),
      _ => throw const FormatException('malformed queue operation'),
    };
  }

  /// Also the `Idempotency-Key` and the body's `operationId`.
  final String id;
  final String entityId;
  final TaskOperationKind kind;

  /// What changed, as the service wrote it.
  final Map<String, Object?> payload;

  /// The server version the user acted on; `null` for a creation.
  final int? baseVersion;

  /// The same operation, based on the version the task's previous one received.
  TaskOperation rebasedOn(int version) => TaskOperation(
    id: id,
    entityId: entityId,
    kind: kind,
    payload: payload,
    baseVersion: kind == TaskOperationKind.create ? null : version,
  );
}
