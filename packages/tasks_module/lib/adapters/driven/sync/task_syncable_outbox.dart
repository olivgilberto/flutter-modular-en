import 'package:core/core.dart';

import '../task_api_paths.dart';
import 'task_conflict_store.dart';
import 'task_operation.dart';
import 'task_outbox_queue.dart';

/// The tasks' outbox, signed up to the `core`'s `OutboxRegistry`
/// (chapter 12). It sends the operations in the order they were written and
/// gives each response an outcome: leaves the queue, stays in the queue, or
/// goes to `sync_conflicts`. Nothing leaves the queue unless the server
/// accepted it or the user saw it.
final class TaskSyncableOutbox implements SyncableOutbox {
  TaskSyncableOutbox({
    required ApiClient apiClient,
    required TaskOutboxQueue queue,
    required TaskConflictStore conflicts,
    required AppLogger logger,
  }) : _api = apiClient,
       _queue = queue,
       _conflicts = conflicts,
       _logger = logger;

  final ApiClient _api;
  final TaskOutboxQueue _queue;
  final TaskConflictStore _conflicts;
  final AppLogger _logger;
  Future<bool>? _running;

  @override
  String get name => 'tasks';

  /// Those in the queue and those waiting for a decision: none was accepted by the server.
  @override
  Future<int> pendingCount() async =>
      await _queue.pendingCount() + await _conflicts.openConflictCount();

  /// Whoever calls during a send gets the same one. This holds within an
  /// isolate; between the open app and the background, idempotency is what
  /// protects (chapter 12).
  @override
  Future<bool> sync() =>
      _running ??= _drain().whenComplete(() => _running = null);

  Future<bool> _drain() async {
    final blocked = await _conflicts.entitiesWithOpenConflict();
    // The version each task got in this round. The queue in the database
    // has already been rebased on it; the list read at the start has not.
    final accepted = <String, int>{};
    for (final queued in await _queue.pendingInOrder()) {
      // Made on a version the server already refused: waits for the user.
      if (blocked.contains(queued.entityId)) continue;
      final operation = switch (accepted[queued.entityId]) {
        final int version => queued.rebasedOn(version),
        null => queued,
      };
      try {
        final response = await _send(operation);
        if (await _complete(operation, response) case final int version) {
          accepted[operation.entityId] = version;
        }
      } on ApiError catch (error) {
        if (_shouldWait(error)) return true;
        if (_alreadyApplied(operation, error)) {
          await _queue.remove(operation.id);
          continue;
        }
        await _conflicts.moveFromQueue(
          operation,
          kind: _isVersionConflict(error)
              ? TaskConflictKind.conflict
              : TaskConflictKind.rejected,
          statusCode: error.statusCode ?? 0,
        );
        blocked.add(operation.entityId);
      }
    }
    return false;
  }

  /// The operation id goes in the body, which is what the backend stores
  /// with the change, and in the header, as transport.
  Future<Object?> _send(TaskOperation operation) {
    final path = TaskApiPaths.task(operation.entityId);
    final body = {...operation.payload, 'operationId': operation.id};
    return switch (operation.kind) {
      TaskOperationKind.create => _api.put(
        path,
        body: body,
        idempotencyKey: operation.id,
      ),
      TaskOperationKind.update || TaskOperationKind.archive => _api.patch(
        path,
        body: {...body, 'baseVersion': operation.baseVersion},
        idempotencyKey: operation.id,
      ),
    };
  }

  /// The new version comes in the response, and the task's later operations
  /// are rebased on it. Without it, the operation leaves the queue anyway,
  /// because the server applied it; the next list refresh brings the
  /// version, and the response defect goes to the crash log.
  Future<int?> _complete(TaskOperation operation, Object? response) async {
    if (response case {'version': final int version}) {
      await _queue.complete(operation, newVersion: version);
      return version;
    }
    await _queue.remove(operation.id);
    _logger.error(
      'tasks outbox response',
      const ApiError(ApiErrorKind.invalidResponse),
      StackTrace.current,
    );
    return null;
  }

  /// Wait: a transient failure, an unreadable response (we do not know if it
  /// was applied), an expired session, the server asking us to slow down,
  /// or a 409 that is not about the version, such as the same key still being processed.
  static bool _shouldWait(ApiError error) =>
      error.isTransient ||
      error.kind == ApiErrorKind.invalidResponse ||
      error.statusCode == 401 ||
      error.statusCode == 429 ||
      (error.statusCode == 409 && !_isVersionConflict(error));

  /// Archiving what no longer exists on the server is the result the
  /// operation wanted.
  static bool _alreadyApplied(TaskOperation operation, ApiError error) =>
      operation.kind == TaskOperationKind.archive && error.statusCode == 404;

  static bool _isVersionConflict(ApiError error) => switch (error) {
    ApiError(statusCode: 409, body: {'code': 'version_conflict'}) => true,
    _ => false,
  };
}
