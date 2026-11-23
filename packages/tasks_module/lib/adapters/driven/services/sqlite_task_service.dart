import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';

import '../../../domain/entities/task.dart';
import '../../../domain/entities/task_conflict.dart';
import '../../../domain/task_failure.dart';
import '../models/task_model.dart';
import '../sync/task_conflict_store.dart';
import '../sync/task_operation.dart';
import '../sync/task_outbox_queue.dart';
import 'task_local_service.dart';
import 'tasks_database_schema.dart';

/// The tasks in the module's encrypted database, opened through the
/// `LocalDatabaseFactory` port on first use: the key lives in the device's
/// secure storage, and the file stays out of backups (chapter 30).
///
/// The database port does not report changes, so the service reports its
/// own: every write it makes rereads the list for whoever observes it.
///
/// It is also the outbox and the refusals table that
/// `TaskSyncableOutbox` uses (chapter 32): they live in the same database,
/// and leaving the queue and entering the refusals table need the same
/// transaction. Queue writes do not change what the list shows, and so do
/// not notify; a new refusal does notify, for the conflicts screen
/// (chapter 34). The notification only applies to this isolate: what the
/// background writes shows up on the next read.
final class SqliteTaskService
    implements TaskLocalService, TaskOutboxQueue, TaskConflictStore {
  SqliteTaskService({
    required LocalDatabaseFactory databaseFactory,
    required String Function() newOperationId,
    required DateTime Function() now,
  }) : _databaseFactory = databaseFactory,
       _newOperationId = newOperationId,
       _now = now;

  static const _showCompletedKey = 'show_completed_tasks';
  static const _activeTasksKey = 'active_tasks';
  static const _columns = 'id, title, status, created_at, version';

  final LocalDatabaseFactory _databaseFactory;
  final String Function() _newOperationId;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();

  /// The factory keeps the open database and forgets an opening that failed
  /// (chapter 18).
  Future<LocalDatabase> get _database =>
      _databaseFactory.open(tasksDatabaseSchema);

  @override
  Stream<List<Task>> watchActiveTasks() => _watch(_activeTasks);

  @override
  Stream<List<TaskConflict>> watchConflicts() => _watch(_conflicts);

  /// Reads right away and again on every write by this service. One read
  /// at a time, in the order of the writes: an old result never arrives
  /// after a new one.
  Stream<T> _watch<T>(Future<T> Function() readAll) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    var listening = true;
    var reading = Future<void>.value();
    void read() {
      reading = reading.then((_) async {
        try {
          final result = await readAll();
          if (listening) controller.add(result);
        } on LocalDatabaseError catch (error, stackTrace) {
          if (listening) controller.addError(error, stackTrace);
        }
      });
    }

    controller = StreamController<T>(
      onListen: () {
        changes = _changes.stream.listen((_) => read());
        read();
      },
      onCancel: () {
        listening = false;
        return changes?.cancel();
      },
    );
    return controller.stream;
  }

  Future<List<Task>> _activeTasks() async {
    final rows = await (await _database).query(
      'SELECT $_columns FROM tasks '
      "WHERE status IN ('open', 'done') "
      'ORDER BY created_at DESC, id',
    );
    return [for (final row in rows) _toEntity(row)];
  }

  @override
  Future<Task?> findTask(String taskId) async {
    final rows = await (await _database).query(
      'SELECT $_columns FROM tasks WHERE id = ?',
      args: [taskId],
    );
    return rows.isEmpty ? null : _toEntity(rows.single);
  }

  /// The task and the operation that takes the change to the backend, in a
  /// single transaction: either both stay, or neither (chapter 12). A task
  /// that does not exist on the device yet is a creation; one that exists is
  /// an update, with the version the user had in front of them.
  @override
  Future<void> saveTask(Task task) async {
    final row = TaskModel.fromEntity(task).toMap();
    await (await _database).transaction((txn) async {
      final existing = await txn.query(
        'SELECT version FROM tasks WHERE id = ?',
        args: [task.id],
      );
      await txn.execute(
        'INSERT INTO tasks (id, title, status, created_at) '
        'VALUES (?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET '
        'title = excluded.title, status = excluded.status',
        args: [row['id'], row['title'], row['status'], row['created_at']],
      );
      if (existing.isEmpty) {
        await _enqueue(
          txn,
          taskId: task.id,
          operation: 'create',
          payload: {
            'title': row['title'],
            'status': row['status'],
            'createdAt': task.createdAt.toIso8601String(),
          },
        );
      } else {
        await _enqueue(
          txn,
          taskId: task.id,
          operation: 'update',
          payload: {'title': row['title'], 'status': row['status']},
          baseVersion: existing.single['version']! as int,
        );
      }
    });
    _changes.add(null);
  }

  @override
  Future<void> archiveTask(String taskId) async {
    await (await _database).transaction((txn) async {
      final existing = await txn.query(
        'SELECT version FROM tasks WHERE id = ?',
        args: [taskId],
      );
      if (existing.isEmpty) return;
      await txn.execute(
        "UPDATE tasks SET status = 'archived' WHERE id = ?",
        args: [taskId],
      );
      await _enqueue(
        txn,
        taskId: taskId,
        operation: 'archive',
        payload: {'status': 'archived'},
        baseVersion: existing.single['version']! as int,
      );
    });
    _changes.add(null);
  }

  /// The operation id becomes the send's Idempotency-Key (chapter 32).
  Future<void> _enqueue(
    LocalDatabase txn, {
    required String taskId,
    required String operation,
    required Map<String, Object?> payload,
    int? baseVersion,
  }) => txn.execute(
    'INSERT INTO outbox_pending_operations '
    '(id, entity_id, operation, payload, base_version, created_at) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    args: [
      _newOperationId(),
      taskId,
      operation,
      jsonEncode(payload),
      baseVersion,
      _now().millisecondsSinceEpoch,
    ],
  );

  /// The server cannot erase what the user did (chapter 12): a task with
  /// an operation in the queue, or with a refusal waiting for the user,
  /// stays as it is on the device, whether or not it comes in the list. The
  /// others become the backend's, and those that did not come leave the device.
  @override
  Future<void> saveActiveTasks(
    List<TaskModel> tasks, {
    required DateTime refreshedAt,
  }) async {
    await (await _database).transaction((txn) async {
      final pending = {
        for (final row in await txn.query(
          'SELECT entity_id FROM outbox_pending_operations '
          'UNION SELECT entity_id FROM sync_conflicts',
        ))
          row['entity_id']! as String,
      };
      final fresh = {for (final task in tasks) task.id};
      for (final row in await txn.query('SELECT id FROM tasks')) {
        final id = row['id']! as String;
        if (!fresh.contains(id) && !pending.contains(id)) {
          await txn.execute('DELETE FROM tasks WHERE id = ?', args: [id]);
        }
      }
      for (final task in tasks) {
        if (pending.contains(task.id)) continue;
        final row = task.toMap();
        await txn.execute(
          'INSERT INTO tasks ($_columns) VALUES (?, ?, ?, ?, ?) '
          'ON CONFLICT (id) DO UPDATE SET title = excluded.title, '
          'status = excluded.status, version = excluded.version',
          args: [
            row['id'],
            row['title'],
            row['status'],
            row['created_at'],
            row['version'],
          ],
        );
      }
      await txn.execute(
        'INSERT OR REPLACE INTO sync_state (key, refreshed_at) VALUES (?, ?)',
        args: [_activeTasksKey, refreshedAt.millisecondsSinceEpoch],
      );
    });
    _changes.add(null);
  }

  @override
  Future<DateTime?> lastRefreshedAt() async {
    final rows = await (await _database).query(
      'SELECT refreshed_at FROM sync_state WHERE key = ?',
      args: [_activeTasksKey],
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      rows.single['refreshed_at']! as int,
      isUtc: true,
    );
  }

  @override
  Future<List<TaskOperation>> pendingInOrder() async {
    final rows = await (await _database).query(
      'SELECT id, entity_id, operation, payload, base_version '
      'FROM outbox_pending_operations ORDER BY rowid',
    );
    return [for (final row in rows) _toOperation(row)];
  }

  @override
  Future<int> pendingCount() => _count('outbox_pending_operations');

  @override
  Future<void> complete(
    TaskOperation operation, {
    required int newVersion,
  }) async {
    await (await _database).transaction((txn) async {
      final queued = await txn.query(
        'SELECT rowid AS position FROM outbox_pending_operations WHERE id = ?',
        args: [operation.id],
      );
      if (queued.isEmpty) return;
      await txn.execute(
        'DELETE FROM outbox_pending_operations WHERE id = ?',
        args: [operation.id],
      );
      // Never backwards: a list refresh may have brought a newer version
      // before this response.
      await txn.execute(
        'UPDATE tasks SET version = max(version, ?) WHERE id = ?',
        args: [newVersion, operation.entityId],
      );
      await txn.execute(
        'UPDATE outbox_pending_operations SET base_version = ? '
        "WHERE entity_id = ? AND rowid > ? AND operation <> 'create'",
        args: [newVersion, operation.entityId, queued.single['position']],
      );
    });
  }

  @override
  Future<void> remove(String operationId) async {
    await (await _database).execute(
      'DELETE FROM outbox_pending_operations WHERE id = ?',
      args: [operationId],
    );
  }

  @override
  Future<Set<String>> entitiesWithOpenConflict() async {
    final rows = await (await _database).query(
      'SELECT DISTINCT entity_id FROM sync_conflicts',
    );
    return {for (final row in rows) row['entity_id']! as String};
  }

  @override
  Future<int> openConflictCount() => _count('sync_conflicts');

  /// The operation goes as it was sent, with the base version the server
  /// refused: that is what the resolution screen needs to show.
  @override
  Future<void> moveFromQueue(
    TaskOperation operation, {
    required TaskConflictKind kind,
    required int statusCode,
  }) async {
    await (await _database).transaction((txn) async {
      await txn.execute(
        'DELETE FROM outbox_pending_operations WHERE id = ?',
        args: [operation.id],
      );
      await txn.execute(
        'INSERT INTO sync_conflicts (id, operation_id, entity_id, kind, '
        'status_code, operation, payload, base_version, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (operation_id) DO NOTHING',
        args: [
          _newOperationId(),
          operation.id,
          operation.entityId,
          kind.name,
          statusCode,
          operation.kind.name,
          jsonEncode(operation.payload),
          operation.baseVersion,
          _now().millisecondsSinceEpoch,
        ],
      );
    });
    // This isolate's conflicts screen starts showing it (chapter 34).
    _changes.add(null);
  }

  Future<int> _count(String table) async {
    final rows = await (await _database).query(
      'SELECT COUNT(*) AS total FROM $table',
    );
    return rows.single['total']! as int;
  }

  /// Written by the app itself: if it is malformed, it is a database defect.
  TaskOperation _toOperation(Map<String, Object?> row) {
    try {
      return TaskOperation.fromMap(row);
    } on FormatException catch (error) {
      throw LocalDatabaseError('invalid queue operation: ${error.message}');
    }
  }

  Future<List<TaskConflict>> _conflicts() async {
    final rows = await (await _database).query(
      'SELECT c.id AS conflict_id, c.kind, c.created_at AS conflict_at, '
      't.id, t.title, t.status, t.created_at, t.version '
      'FROM sync_conflicts c JOIN tasks t ON t.id = c.entity_id '
      'ORDER BY c.created_at, c.rowid',
    );
    return [
      for (final row in rows)
        TaskConflict(
          id: row['conflict_id']! as String,
          reason: row['kind'] == 'conflict'
              ? TaskConflictReason.versionConflict
              : TaskConflictReason.rejected,
          task: _toEntity(row),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row['conflict_at']! as int,
            isUtc: true,
          ),
        ),
    ];
  }

  @override
  Future<void> keepLocalVersion(
    String conflictId, {
    required String taskId,
    required int? serverVersion,
  }) async {
    await (await _database).transaction((txn) async {
      final rows = await txn.query(
        'SELECT $_columns FROM tasks WHERE id = ?',
        args: [taskId],
      );
      if (rows.isEmpty) return;
      final local = TaskModel.fromMap(rows.single);
      await _forget(txn, conflictId: conflictId, taskId: taskId);
      final archived = local.status == 'archived';
      if (serverVersion == null && archived) {
        // Deleted there and archived here: both versions agree that it left
        // the list, and there is nothing to send.
        await txn.execute('DELETE FROM tasks WHERE id = ?', args: [taskId]);
        return;
      }
      if (serverVersion == null) {
        // Deleted on the server: the user's version comes back as a creation,
        // with the same id, through the same idempotent PUT.
        await txn.execute(
          'UPDATE tasks SET version = 0 WHERE id = ?',
          args: [taskId],
        );
        await _enqueue(
          txn,
          taskId: taskId,
          operation: 'create',
          payload: {
            'title': local.title,
            'status': local.status,
            'createdAt': DateTime.fromMillisecondsSinceEpoch(
              local.createdAt,
              isUtc: true,
            ).toIso8601String(),
          },
        );
        return;
      }
      await txn.execute(
        'UPDATE tasks SET version = ? WHERE id = ?',
        args: [serverVersion, taskId],
      );
      await _enqueue(
        txn,
        taskId: taskId,
        operation: archived ? 'archive' : 'update',
        payload: archived
            ? {'status': 'archived'}
            : {'title': local.title, 'status': local.status},
        baseVersion: serverVersion,
      );
    });
    _changes.add(null);
  }

  @override
  Future<void> acceptServerVersion(
    String conflictId, {
    required String taskId,
    required TaskModel? server,
  }) async {
    await (await _database).transaction((txn) async {
      await _forget(txn, conflictId: conflictId, taskId: taskId);
      if (server == null) {
        await txn.execute('DELETE FROM tasks WHERE id = ?', args: [taskId]);
        return;
      }
      final row = server.toMap();
      await txn.execute(
        'INSERT INTO tasks ($_columns) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET title = excluded.title, '
        'status = excluded.status, version = excluded.version',
        args: [
          row['id'],
          row['title'],
          row['status'],
          row['created_at'],
          row['version'],
        ],
      );
    });
    _changes.add(null);
  }

  @override
  Future<void> discardConflict(
    String conflictId, {
    required String taskId,
  }) async {
    await (await _database).transaction((txn) async {
      await _forget(txn, conflictId: conflictId, taskId: taskId);
      // Expired: the next opening shows the device and refreshes behind the scenes.
      await txn.execute(
        'INSERT OR REPLACE INTO sync_state (key, refreshed_at) VALUES (?, 0)',
        args: [_activeTasksKey],
      );
    });
    _changes.add(null);
  }

  /// The conflict and the task's operations that were waiting for it: they
  /// were made on the version the server refused, and the decision replaces them.
  Future<void> _forget(
    LocalDatabase txn, {
    required String conflictId,
    required String taskId,
  }) async {
    await txn.execute(
      'DELETE FROM sync_conflicts WHERE id = ?',
      args: [conflictId],
    );
    await txn.execute(
      'DELETE FROM outbox_pending_operations WHERE entity_id = ?',
      args: [taskId],
    );
  }

  /// Until the user chooses, done tasks are shown.
  @override
  Future<bool> showCompletedTasks() async {
    final rows = await (await _database).query(
      'SELECT value FROM preferences WHERE key = ?',
      args: [_showCompletedKey],
    );
    return rows.isEmpty || rows.single['value'] == '1';
  }

  @override
  Future<void> saveShowCompletedTasks(bool show) async {
    await (await _database).execute(
      'INSERT OR REPLACE INTO preferences (key, value) VALUES (?, ?)',
      args: [_showCompletedKey, show ? '1' : '0'],
    );
  }

  /// In a transaction: either everything goes, or nothing.
  @override
  Future<void> deleteAll() async {
    await (await _database).transaction((txn) async {
      await txn.execute('DELETE FROM tasks');
      await txn.execute('DELETE FROM outbox_pending_operations');
      await txn.execute('DELETE FROM sync_conflicts');
      await txn.execute('DELETE FROM sync_state');
      await txn.execute('DELETE FROM preferences');
    });
    _changes.add(null);
  }

  /// Closes the change notifications, at the end of the session scope.
  Future<void> dispose() => _changes.close();

  /// The data was written by the app itself: a title the domain rejects, or
  /// a malformed row, is not the user's fault (chapter 9).
  Task _toEntity(Map<String, Object?> row) {
    try {
      return TaskModel.fromMap(row).toEntity();
    } on FormatException catch (error) {
      throw LocalDatabaseError('invalid stored task: ${error.message}');
    } on TaskFailure {
      throw const LocalDatabaseError('stored task with an invalid title');
    }
  }
}
