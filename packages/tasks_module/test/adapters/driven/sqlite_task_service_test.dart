import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks_module/adapters/driven/models/task_model.dart';
import 'package:tasks_module/adapters/driven/services/sqlite_task_service.dart';
import 'package:tasks_module/adapters/driven/services/tasks_database_schema.dart';
import 'package:tasks_module/adapters/driven/sync/task_conflict_store.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/entities/task_conflict.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

import '../../support/ffi_local_database.dart';

Task _task(
  String id,
  String title, {
  int minute = 0,
  TaskStatus status = TaskStatus.open,
}) => Task(
  id: id,
  title: TaskTitle.parse(title),
  createdAt: DateTime.utc(2026, 10, 27, 9, minute),
  status: status,
);

TaskModel _remote(
  String id,
  String title, {
  int minute = 0,
  String status = 'open',
  int version = 1,
}) => TaskModel(
  id: id,
  title: title,
  status: status,
  createdAt: DateTime.utc(2026, 10, 27, 9, minute).millisecondsSinceEpoch,
  version: version,
);

List<String> _titles(List<Task> tasks) => [
  for (final task in tasks) task.title.value,
];

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  late FfiLocalDatabaseFactory factory;
  late SqliteTaskService service;
  late int nextOperation;

  setUp(() {
    nextOperation = 0;
    factory = FfiLocalDatabaseFactory();
    service = SqliteTaskService(
      databaseFactory: factory,
      newOperationId: () => 'op-${++nextOperation}',
      now: () => now,
    );
  });

  tearDown(() async {
    await service.dispose();
    await factory.close();
  });

  /// The queue, in send order, read straight from the database.
  Future<List<Map<String, Object?>>> operations() async {
    final db = await factory.rawDatabase(tasksDatabaseSchema);
    return [
      for (final row in await db.rawQuery(
        'SELECT * FROM outbox_pending_operations ORDER BY rowid',
      ))
        {...row, 'payload': jsonDecode(row['payload']! as String)},
    ];
  }

  test('writes and finds a task', () async {
    await service.saveTask(_task('t-1', 'Buy bread'));

    final found = await service.findTask('t-1');
    expect(found?.title.value, 'Buy bread');
    expect(found?.createdAt, DateTime.utc(2026, 10, 27, 9));
    expect(await service.findTask('t-9'), isNull);
  });

  test('writing again updates the title and status, never the creation '
      'date', () async {
    await service.saveTask(_task('t-1', 'Buy bread'));
    await service.saveTask(
      _task(
        't-1',
        'Buy whole wheat bread',
        minute: 30,
        status: TaskStatus.done,
      ),
    );

    final found = await service.findTask('t-1');
    expect(found?.title.value, 'Buy whole wheat bread');
    expect(found?.status, TaskStatus.done);
    expect(found?.createdAt, DateTime.utc(2026, 10, 27, 9));
  });

  test('every write queues, in the same transaction, the operation the '
      'backend needs to receive', () async {
    await service.saveTask(_task('t-1', 'Buy bread'));
    await service.saveActiveTasks([
      _remote('t-2', 'Pay the power bill', version: 7),
    ], refreshedAt: now);
    await service.saveTask(
      _task('t-2', 'Pay the power bill', status: TaskStatus.done),
    );
    await service.archiveTask('t-2');
    await service.archiveTask('t-9');

    expect(await operations(), [
      {
        'id': 'op-1',
        'entity_id': 't-1',
        'operation': 'create',
        'payload': {
          'title': 'Buy bread',
          'status': 'open',
          'createdAt': '2026-10-27T09:00:00.000Z',
        },
        'base_version': null,
        'created_at': now.millisecondsSinceEpoch,
      },
      {
        'id': 'op-2',
        'entity_id': 't-2',
        'operation': 'update',
        'payload': {'title': 'Pay the power bill', 'status': 'done'},
        'base_version': 7,
        'created_at': now.millisecondsSinceEpoch,
      },
      {
        'id': 'op-3',
        'entity_id': 't-2',
        'operation': 'archive',
        'payload': {'status': 'archived'},
        'base_version': 7,
        'created_at': now.millisecondsSinceEpoch,
      },
    ]);
  });

  group('the queue, from the sender\'s side', () {
    /// Each task's version, read straight from the database.
    Future<Map<String, int>> versions() async {
      final db = await factory.rawDatabase(tasksDatabaseSchema);
      return {
        for (final row in await db.rawQuery('SELECT id, version FROM tasks'))
          row['id']! as String: row['version']! as int,
      };
    }

    test('reads the operations in the order they were written', () async {
      await service.saveTask(_task('t-1', 'Buy bread'));
      await service.archiveTask('t-1');

      final pending = await service.pendingInOrder();
      expect([for (final op in pending) op.id], ['op-1', 'op-2']);
      expect(pending.first.payload['title'], 'Buy bread');
      expect(pending.last.baseVersion, 0);
      expect(await service.pendingCount(), 2);
    });

    test(
      'accepted, the operation leaves the queue, the task stores the new version, and '
      'the same task\'s later ones are rebased on it',
      () async {
        await service.saveActiveTasks([
          _remote('t-2', 'Pay the power bill', version: 7),
        ], refreshedAt: now);
        await service.saveTask(_task('t-1', 'Buy bread'));
        await service.saveTask(_task('t-1', 'Buy whole wheat bread'));
        await service.saveTask(
          _task('t-2', 'Pay the power bill', status: TaskStatus.done),
        );
        final created = (await service.pendingInOrder()).first;

        await service.complete(created, newVersion: 1);
        // The other isolate had already confirmed the same operation: nothing changes.
        await service.complete(created, newVersion: 1);

        expect(await versions(), {'t-1': 1, 't-2': 7});
        expect(
          [for (final op in await operations()) (op['id'], op['base_version'])],
          [('op-2', 1), ('op-3', 7)],
        );
      },
    );

    test('the task\'s version never goes backwards', () async {
      await service.saveTask(_task('t-1', 'Buy bread'));
      final created = (await service.pendingInOrder()).single;
      final db = await factory.rawDatabase(tasksDatabaseSchema);
      await db.rawUpdate("UPDATE tasks SET version = 5 WHERE id = 't-1'");

      await service.complete(created, newVersion: 1);

      expect(await versions(), {'t-1': 5});
    });

    test(
      'refused, the operation leaves the queue and becomes a refusal only once, and the '
      'list refresh does not touch the task',
      () async {
        await service.saveActiveTasks([
          _remote('t-1', 'Buy bread', version: 3),
        ], refreshedAt: now);
        await service.saveTask(
          _task('t-1', 'Buy bread', status: TaskStatus.done),
        );
        final update = (await service.pendingInOrder()).single;

        await service.moveFromQueue(
          update,
          kind: TaskConflictKind.conflict,
          statusCode: 409,
        );
        await service.moveFromQueue(
          update,
          kind: TaskConflictKind.conflict,
          statusCode: 409,
        );
        await service.saveActiveTasks([
          _remote('t-1', 'Buy bread', version: 4),
        ], refreshedAt: now);

        expect(await operations(), isEmpty);
        expect(await service.pendingCount(), 0);
        expect(await service.openConflictCount(), 1);
        expect(await service.entitiesWithOpenConflict(), {'t-1'});
        expect((await service.findTask('t-1'))?.status, TaskStatus.done);
        final db = await factory.rawDatabase(tasksDatabaseSchema);
        final conflict = (await db.rawQuery(
          'SELECT * FROM sync_conflicts',
        )).single;
        expect(conflict['operation_id'], 'op-1');
        expect(conflict['kind'], 'conflict');
        expect(conflict['status_code'], 409);
        expect(conflict['operation'], 'update');
        expect(conflict['base_version'], 3);
        expect(jsonDecode(conflict['payload']! as String), {
          'title': 'Buy bread',
          'status': 'done',
        });
      },
    );

    test('take out of the queue without touching the task', () async {
      await service.saveTask(_task('t-1', 'Buy bread'));
      await service.remove('op-1');
      await service.remove('op-1');

      expect(await operations(), isEmpty);
      expect(await versions(), {'t-1': 0});
    });

    test('a malformed operation is a LocalDatabaseError', () async {
      final database = await factory.open(tasksDatabaseSchema);
      await database.execute(
        'INSERT INTO outbox_pending_operations VALUES '
        "('op-9', 't-1', 'create', 'not json', NULL, 0)",
      );

      await expectLater(
        service.pendingInOrder(),
        throwsA(isA<LocalDatabaseError>()),
      );
    });
  });

  test('the observed list arrives right away and again on every write, newest '
      'first and without the archived ones', () async {
    final lists = <List<String>>[];
    final subscription = service.watchActiveTasks().listen(
      (tasks) => lists.add(_titles(tasks)),
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await service.saveTask(_task('t-1', 'Buy bread', minute: 1));
    await pumpEventQueue();
    await service.saveTask(
      _task('t-2', 'Pay the power bill', minute: 2, status: TaskStatus.done),
    );
    await pumpEventQueue();
    await service.archiveTask('t-1');
    await pumpEventQueue();

    expect(lists, [
      <String>[],
      ['Buy bread'],
      ['Pay the power bill', 'Buy bread'],
      ['Pay the power bill'],
    ]);
    expect((await service.findTask('t-1'))?.status, TaskStatus.archived);
  });

  test('the backend\'s list replaces the device\'s, with the server '
      'version, and notifies observers', () async {
    await service.saveActiveTasks([
      _remote('t-1', 'Buy bread', minute: 1),
      _remote('t-2', 'Pay the power bill', minute: 2),
    ], refreshedAt: now);
    final lists = <List<String>>[];
    final subscription = service.watchActiveTasks().listen(
      (tasks) => lists.add(_titles(tasks)),
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await service.saveActiveTasks([
      _remote('t-2', 'Pay the electricity bill', minute: 2, version: 2),
    ], refreshedAt: now);
    await pumpEventQueue();

    expect(lists, [
      ['Pay the power bill', 'Buy bread'],
      ['Pay the electricity bill'],
    ]);
    expect(await service.findTask('t-1'), isNull);
    expect(await operations(), isEmpty);
  });

  test('the server neither erases nor overwrites a task with an operation in '
      'the queue', () async {
    await service.saveActiveTasks([
      _remote('t-1', 'Buy bread', minute: 1),
      _remote('t-2', 'Pay the power bill', minute: 2),
    ], refreshedAt: now);
    // Done offline: a new task, a done one, and an archived one.
    await service.saveTask(_task('t-3', 'Call the school', minute: 3));
    await service.saveTask(
      _task('t-1', 'Buy bread', minute: 1, status: TaskStatus.done),
    );
    await service.archiveTask('t-2');

    // The backend has not received any of this yet.
    await service.saveActiveTasks([
      _remote('t-1', 'Buy bread', minute: 1, version: 3),
      _remote('t-2', 'Pay the power bill', minute: 2, version: 3),
    ], refreshedAt: now);

    expect((await service.findTask('t-1'))?.status, TaskStatus.done);
    expect((await service.findTask('t-2'))?.status, TaskStatus.archived);
    expect((await service.findTask('t-3'))?.title.value, 'Call the school');
    expect(await operations(), hasLength(3));
  });

  test(
    'the time of the last refresh only exists after the first one',
    () async {
      expect(await service.lastRefreshedAt(), isNull);

      await service.saveActiveTasks([], refreshedAt: now);

      final refreshedAt = await service.lastRefreshedAt();
      expect(refreshedAt, now);
      expect(refreshedAt?.isUtc, isTrue);
    },
  );

  test('done tasks are shown until the user chooses', () async {
    expect(await service.showCompletedTasks(), isTrue);

    await service.saveShowCompletedTasks(false);
    expect(await service.showCompletedTasks(), isFalse);
    await service.saveShowCompletedTasks(true);
    expect(await service.showCompletedTasks(), isTrue);
  });

  test(
    'erasing everything takes the tasks, the queue, the refusals, the refresh '
    'time, and the preferences, and notifies observers',
    () async {
      await service.saveActiveTasks([
        _remote('t-1', 'Buy bread'),
      ], refreshedAt: now);
      await service.saveTask(_task('t-2', 'Pay the power bill'));
      await service.saveTask(_task('t-3', 'Call the school'));
      await service.moveFromQueue(
        (await service.pendingInOrder()).last,
        kind: TaskConflictKind.rejected,
        statusCode: 422,
      );
      await service.saveShowCompletedTasks(false);
      final lists = <List<String>>[];
      final subscription = service.watchActiveTasks().listen(
        (tasks) => lists.add(_titles(tasks)),
      );
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await service.deleteAll();
      await pumpEventQueue();

      expect(lists.last, isEmpty);
      expect(await service.findTask('t-1'), isNull);
      expect(await operations(), isEmpty);
      expect(await service.openConflictCount(), 0);
      expect(await service.lastRefreshedAt(), isNull);
      expect(await service.showCompletedTasks(), isTrue);
    },
  );

  test('a row the domain rejects arrives as LocalDatabaseError, in the '
      'lookup and in the observed list', () async {
    // Written straight to the database, as an old version or a bug would leave it.
    final database = await factory.open(tasksDatabaseSchema);
    await database.execute(
      "INSERT INTO tasks VALUES ('t-1', '   ', 'open', 0, 0)",
    );

    await expectLater(
      service.findTask('t-1'),
      throwsA(isA<LocalDatabaseError>()),
    );
    await expectLater(
      service.watchActiveTasks(),
      emitsError(isA<LocalDatabaseError>()),
    );
  });

  test('the database rejects a status outside the list', () async {
    final database = await factory.open(tasksDatabaseSchema);
    await expectLater(
      database.execute(
        "INSERT INTO tasks VALUES ('t-1', 'x', 'deleted', 0, 0)",
      ),
      throwsA(isA<LocalDatabaseError>()),
    );
  });

  group('the refusals, from the decider\'s side (chapter 34)', () {
    /// A server task, changed on the device, and the refused change.
    /// After the refusal, another change waits in the queue; the archived one
    /// has no later change.
    Future<TaskConflict> refused({
      TaskConflictKind kind = TaskConflictKind.conflict,
      bool archived = false,
    }) async {
      await service.saveActiveTasks([
        _remote('t-1', 'Buy bread', version: 3),
      ], refreshedAt: now);
      if (archived) {
        await service.archiveTask('t-1');
      } else {
        await service.saveTask(
          _task('t-1', 'Buy bread', status: TaskStatus.done),
        );
      }
      final operation = (await service.pendingInOrder()).single;
      await service.moveFromQueue(
        operation,
        kind: kind,
        statusCode: kind == TaskConflictKind.conflict ? 409 : 422,
      );
      if (!archived) {
        await service.saveTask(
          _task('t-1', 'Buy whole wheat bread', status: TaskStatus.done),
        );
      }
      return (await service.watchConflicts().first).single;
    }

    Future<int?> refreshedAt() async {
      final db = await factory.rawDatabase(tasksDatabaseSchema);
      final rows = await db.rawQuery('SELECT refreshed_at FROM sync_state');
      return rows.isEmpty ? null : rows.single['refreshed_at'] as int?;
    }

    test('the refusal arrives as a domain conflict, with the device\'s '
        'task', () async {
      final conflict = await refused();

      expect(conflict.id, isNotEmpty);
      expect(conflict.reason, TaskConflictReason.versionConflict);
      expect(conflict.task.title.value, 'Buy whole wheat bread');
      expect(conflict.task.status, TaskStatus.done);
      expect(conflict.createdAt, now);
      expect(conflict.choices, [
        TaskConflictChoice.keepMine,
        TaskConflictChoice.keepServer,
      ]);
    });

    test('any other 4xx refusal arrives as a refusal', () async {
      final conflict = await refused(kind: TaskConflictKind.rejected);

      expect(conflict.reason, TaskConflictReason.rejected);
    });

    test(
      'the conflict list is observed and notifies on every refusal',
      () async {
        final seen = <int>[];
        final subscription = service.watchConflicts().listen(
          (conflicts) => seen.add(conflicts.length),
        );
        await pumpEventQueue();

        await refused();
        await pumpEventQueue();

        expect(seen.first, 0);
        expect(seen.last, 1);
        await subscription.cancel();
      },
    );

    test('keep mine: a single operation, with the device\'s version and the '
        'server\'s base', () async {
      final conflict = await refused();

      await service.keepLocalVersion(
        conflict.id,
        taskId: 't-1',
        serverVersion: 5,
      );

      expect(await service.watchConflicts().first, isEmpty);
      final ops = await operations();
      expect(ops, hasLength(1));
      expect(ops.single['operation'], 'update');
      expect(ops.single['base_version'], 5);
      expect(ops.single['payload'], {
        'title': 'Buy whole wheat bread',
        'status': 'done',
      });
      expect(await service.entitiesWithOpenConflict(), isEmpty);
    });

    test('keep mine, archived here: the archiving with the server\'s '
        'base', () async {
      final conflict = await refused(archived: true);

      await service.keepLocalVersion(
        conflict.id,
        taskId: 't-1',
        serverVersion: 5,
      );

      final op = (await operations()).single;
      expect(op['operation'], 'archive');
      expect(op['payload'], {'status': 'archived'});
      expect(op['base_version'], 5);
    });

    test('keep mine, deleted on the server: comes back as a creation, with the '
        'same id', () async {
      final conflict = await refused();

      await service.keepLocalVersion(
        conflict.id,
        taskId: 't-1',
        serverVersion: null,
      );

      final op = (await operations()).single;
      expect(op['operation'], 'create');
      expect(op['entity_id'], 't-1');
      expect(op['payload'], {
        'title': 'Buy whole wheat bread',
        'status': 'done',
        'createdAt': '2026-10-27T09:00:00.000Z',
      });
    });

    test(
      'keep mine, deleted there and archived here: nothing to send',
      () async {
        final conflict = await refused(archived: true);

        await service.keepLocalVersion(
          conflict.id,
          taskId: 't-1',
          serverVersion: null,
        );

        expect(await operations(), isEmpty);
        expect(await service.findTask('t-1'), isNull);
      },
    );

    test('keep the server\'s: its version stays, and the task\'s queue '
        'empties', () async {
      final conflict = await refused();

      await service.acceptServerVersion(
        conflict.id,
        taskId: 't-1',
        server: _remote('t-1', 'Buy French bread', version: 6),
      );

      expect(await operations(), isEmpty);
      expect(await service.watchConflicts().first, isEmpty);
      final task = await service.findTask('t-1');
      expect(task?.title.value, 'Buy French bread');
      expect(task?.status, TaskStatus.open);
      expect(task?.createdAt, DateTime.utc(2026, 10, 27, 9));
    });

    test('keep the server\'s, deleted there: it goes away here too', () async {
      final conflict = await refused();

      await service.acceptServerVersion(
        conflict.id,
        taskId: 't-1',
        server: null,
      );

      expect(await service.findTask('t-1'), isNull);
      expect(await operations(), isEmpty);
    });

    test('discard: the change leaves, and the list expires to refresh behind '
        'the scenes', () async {
      final conflict = await refused(kind: TaskConflictKind.rejected);
      expect(await refreshedAt(), now.millisecondsSinceEpoch);

      await service.discardConflict(conflict.id, taskId: 't-1');

      expect(await operations(), isEmpty);
      expect(await service.watchConflicts().first, isEmpty);
      expect(await refreshedAt(), 0);
      // The device shows its version until the refresh arrives.
      expect(
        (await service.findTask('t-1'))?.title.value,
        'Buy whole wheat bread',
      );
    });

    test('deciding on a conflict that already left breaks nothing', () async {
      final conflict = await refused();
      await service.discardConflict(conflict.id, taskId: 't-1');

      await service.discardConflict(conflict.id, taskId: 't-1');
      await service.keepLocalVersion('c-9', taskId: 't-9', serverVersion: 1);

      expect(await operations(), isEmpty);
    });

    test('the other tasks are not touched', () async {
      final conflict = await refused();
      await service.saveTask(_task('t-2', 'Pay the power bill'));

      await service.acceptServerVersion(
        conflict.id,
        taskId: 't-1',
        server: _remote('t-1', 'Buy bread', version: 6),
      );

      expect([for (final op in await operations()) op['entity_id']], ['t-2']);
      expect(
        (await service.findTask('t-2'))?.title.value,
        'Pay the power bill',
      );
    });
  });
}
