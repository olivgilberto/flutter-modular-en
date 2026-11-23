import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driven/models/task_model.dart';
import 'package:tasks_module/adapters/driven/services/sqlite_task_service.dart';
import 'package:tasks_module/adapters/driven/services/tasks_database_schema.dart';
import 'package:tasks_module/adapters/driven/sync/task_syncable_outbox.dart';
import 'package:tasks_module/adapters/driven/task_api_paths.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

import '../../fakes.dart';
import '../../support/ffi_local_database.dart';

final class _MockApiClient extends Mock implements ApiClient {}

Task _task(String id, String title, {TaskStatus status = TaskStatus.open}) =>
    Task(
      id: id,
      title: TaskTitle.parse(title),
      createdAt: DateTime.utc(2026, 10, 27, 9),
      status: status,
    );

TaskModel _remote(String id, String title, {required int version}) => TaskModel(
  id: id,
  title: title,
  status: 'open',
  createdAt: DateTime.utc(2026, 10, 27, 9).millisecondsSinceEpoch,
  version: version,
);

/// A backend rejection, as the HTTP adapter delivers it.
ApiError _rejected(int status, [Object? body]) =>
    ApiError(ApiErrorKind.rejected, statusCode: status, body: body);

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  late FfiLocalDatabaseFactory factory;
  late SqliteTaskService local;
  late _MockApiClient api;
  late FakeLogger logger;
  late TaskSyncableOutbox outbox;
  late int nextOperation;

  /// What the backend received, in order: method, path, body, and key.
  /// Lists, not records, so that `expect` compares the bodies by
  /// content.
  late List<List<Object?>> sent;

  /// Each task's response; with no entry, accepted with the next version.
  late Map<String, Object> answers;

  setUp(() {
    nextOperation = 0;
    factory = FfiLocalDatabaseFactory();
    local = SqliteTaskService(
      databaseFactory: factory,
      newOperationId: () => 'op-${++nextOperation}',
      now: () => now,
    );
    api = _MockApiClient();
    logger = FakeLogger();
    outbox = TaskSyncableOutbox(
      apiClient: api,
      queue: local,
      conflicts: local,
      logger: logger,
    );
    sent = [];
    answers = {};
    var version = 10;
    Future<Object?> answer(String method, Invocation invocation) async {
      final path = invocation.positionalArguments.single as String;
      sent.add([
        method,
        path,
        invocation.namedArguments[#body],
        invocation.namedArguments[#idempotencyKey],
      ]);
      final reply = answers[path];
      if (reply is ApiError) throw reply;
      return reply ?? {'version': ++version};
    }

    when(
      () => api.put(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((invocation) => answer('PUT', invocation));
    when(
      () => api.patch(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((invocation) => answer('PATCH', invocation));
  });

  tearDown(() async {
    await local.dispose();
    await factory.close();
  });

  Future<List<String>> queued() async => [
    for (final op in await local.pendingInOrder()) op.id,
  ];

  test(
    'sends in order, with the operation id in the body and the header, and the '
    'next change is rebased on the version the creation got',
    () async {
      await local.saveTask(_task('t-1', 'Buy bread'));
      await local.saveTask(_task('t-1', 'Buy whole wheat bread'));
      await local.archiveTask('t-1');

      expect(await outbox.sync(), isFalse);

      final path = TaskApiPaths.task('t-1');
      expect(sent, [
        [
          'PUT',
          path,
          {
            'title': 'Buy bread',
            'status': 'open',
            'createdAt': '2026-10-27T09:00:00.000Z',
            'operationId': 'op-1',
          },
          'op-1',
        ],
        [
          'PATCH',
          path,
          {
            'title': 'Buy whole wheat bread',
            'status': 'open',
            'operationId': 'op-2',
            'baseVersion': 11,
          },
          'op-2',
        ],
        [
          'PATCH',
          path,
          {'status': 'archived', 'operationId': 'op-3', 'baseVersion': 12},
          'op-3',
        ],
      ]);
      expect(await queued(), isEmpty);
      expect(await outbox.pendingCount(), 0);
    },
  );

  for (final (label, error) in [
    ('no connection', const ApiError(ApiErrorKind.unreachable)),
    ('5xx', const ApiError(ApiErrorKind.server, statusCode: 503)),
    ('unreadable response', const ApiError(ApiErrorKind.invalidResponse)),
    ('401', _rejected(401)),
    ('429', _rejected(429)),
    (
      '409 not about the version',
      _rejected(409, {'code': 'request_in_flight'}),
    ),
  ]) {
    test(
      '$label: the operation stays, the round stops, and the order holds',
      () async {
        await local.saveTask(_task('t-1', 'Buy bread'));
        await local.saveTask(_task('t-2', 'Pay the power bill'));
        answers[TaskApiPaths.task('t-1')] = error;

        expect(await outbox.sync(), isTrue);

        expect(sent, hasLength(1));
        expect(await queued(), ['op-1', 'op-2']);
        expect(await local.openConflictCount(), 0);
      },
    );
  }

  test('a version 409 goes to sync_conflicts, the task\'s later operations '
      'wait, and the other tasks go on', () async {
    await local.saveActiveTasks([
      _remote('t-1', 'Buy bread', version: 3),
    ], refreshedAt: now);
    await local.saveTask(_task('t-1', 'Buy bread', status: TaskStatus.done));
    await local.saveTask(_task('t-2', 'Pay the power bill'));
    await local.archiveTask('t-1');
    answers[TaskApiPaths.task('t-1')] = _rejected(409, {
      'code': 'version_conflict',
    });

    expect(await outbox.sync(), isFalse);

    expect([for (final s in sent) s[3]], ['op-1', 'op-2']);
    expect(await queued(), ['op-3']);
    expect(await local.entitiesWithOpenConflict(), {'t-1'});
    // The refusal and the waiting operation: none was accepted.
    expect(await outbox.pendingCount(), 2);

    // The next round does not send what waits for the decision either.
    sent.clear();
    expect(await outbox.sync(), isFalse);
    expect(sent, isEmpty);
  });

  test(
    'any other 4xx refusal also goes to sync_conflicts, as a refusal',
    () async {
      await local.saveTask(_task('t-1', 'Buy bread'));
      answers[TaskApiPaths.task('t-1')] = _rejected(422, {'code': 'invalid'});

      expect(await outbox.sync(), isFalse);

      final db = await factory.rawDatabase(tasksDatabaseSchema);
      final conflict = (await db.rawQuery(
        'SELECT * FROM sync_conflicts',
      )).single;
      expect(conflict['kind'], 'rejected');
      expect(conflict['status_code'], 422);
      expect(await queued(), isEmpty);
    },
  );

  test(
    '404 on an archiving leaves the queue; on an update, it is a refusal',
    () async {
      await local.saveActiveTasks([
        _remote('t-1', 'Buy bread', version: 3),
        _remote('t-2', 'Pay the power bill', version: 3),
      ], refreshedAt: now);
      await local.archiveTask('t-1');
      await local.saveTask(
        _task('t-2', 'Pay the power bill', status: TaskStatus.done),
      );
      answers[TaskApiPaths.task('t-1')] = _rejected(404);
      answers[TaskApiPaths.task('t-2')] = _rejected(404);

      expect(await outbox.sync(), isFalse);

      expect(await queued(), isEmpty);
      expect(await local.entitiesWithOpenConflict(), {'t-2'});
    },
  );

  test(
    'a success response without the version takes the operation out of the queue and goes '
    'to the crash log',
    () async {
      await local.saveTask(_task('t-1', 'Buy bread'));
      answers[TaskApiPaths.task('t-1')] = {'id': 't-1'};

      expect(await outbox.sync(), isFalse);

      expect(await queued(), isEmpty);
      expect(logger.errors, ['tasks outbox response']);
    },
  );

  test('concurrent calls share the same send', () async {
    await local.saveTask(_task('t-1', 'Buy bread'));
    final release = Completer<void>();
    when(
      () => api.put(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async {
      await release.future;
      return {'version': 1};
    });

    final first = outbox.sync();
    final second = outbox.sync();
    release.complete();

    expect(await Future.wait([first, second]), [false, false]);
    verify(
      () => api.put(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).called(1);
  });

  test('the name in the logs is stable', () {
    expect(outbox.name, 'tasks');
  });
}
