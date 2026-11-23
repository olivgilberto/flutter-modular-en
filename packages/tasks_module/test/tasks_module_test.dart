import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driven/task_api_paths.dart';
import 'package:tasks_module/adapters/driving/bloc/task_conflicts_bloc.dart';
import 'package:tasks_module/adapters/driving/bloc/task_edit_bloc.dart';
import 'package:tasks_module/adapters/driving/bloc/task_list_bloc.dart';
import 'package:tasks_module/application/use_cases/task_use_case.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/entities/task_conflict.dart';
import 'package:tasks_module/tasks_module.dart';

import 'fakes.dart';
import 'support/ffi_local_database.dart';

final class _MockApiClient extends Mock implements ApiClient {}

void main() {
  late GetIt getIt;
  late _MockApiClient api;
  late DefaultLogoutCleanerRegistry cleaners;
  late DefaultOutboxRegistry outboxes;
  late FfiLocalDatabaseFactory databases;

  setUpAll(() => registerFallbackValue(<String, String>{}));

  // The base scope as the host builds it, with only the ports the module
  // uses; the module goes into the session scope, as in the host's openSessionScope.
  setUp(() {
    api = _MockApiClient();
    cleaners = DefaultLogoutCleanerRegistry();
    outboxes = DefaultOutboxRegistry();
    databases = FfiLocalDatabaseFactory();
    getIt = GetIt.asNewInstance()
      ..registerSingleton<ApiClient>(api)
      ..registerSingleton<LocalDatabaseFactory>(databases)
      ..registerSingleton<LogoutCleanerRegistry>(cleaners)
      ..registerSingleton<OutboxRegistry>(outboxes)
      ..registerSingleton<AppLogger>(FakeLogger())
      ..registerSingleton<AppAnalytics>(FakeAnalytics())
      ..pushNewScope(
        scopeName: 'session',
        init: (scope) => registerTasksModuleDependencies(scope),
      );
  });
  tearDown(() async {
    await getIt.reset();
    await databases.close();
  });

  /// No network to send: what the user does stays in the queue.
  void sendingFails() => when(
    () => api.put(
      any(),
      body: any(named: 'body'),
      idempotencyKey: any(named: 'idempotencyKey'),
    ),
  ).thenThrow(const ApiError(ApiErrorKind.unreachable));

  /// The backend always returns the same list, in a single page.
  void backendHas(List<Map<String, Object?>> items) => when(
    () => api.get(TaskApiPaths.tasks, query: any(named: 'query')),
  ).thenAnswer((_) async => {'items': items, 'nextCursor': null});

  test('the first list comes from the backend and, after that, from the '
      'module\'s database', () async {
    backendHas([
      {
        'id': 't-1',
        'title': 'Pay the power bill',
        'status': 'open',
        'createdAt': '2026-10-27T09:00:00.000Z',
        'version': 2,
      },
    ]);
    final tasks = getIt<TaskUseCase>();
    expect(getIt<TaskUseCase>(), same(tasks));

    final listed = await tasks.watchActiveTasks().first;
    expect(listed.single.title.value, 'Pay the power bill');

    // Loaded once already, the list comes from the device, with no other trip to the network.
    await tasks.watchActiveTasks().first;
    verify(
      () => api.get(TaskApiPaths.tasks, query: any(named: 'query')),
    ).called(1);
  });

  test('a task created on the device survives the refresh, even without '
      'being on the backend', () async {
    backendHas([]);
    sendingFails();
    final tasks = getIt<TaskUseCase>();

    final created = await tasks.createTask(title: '  Buy bread ');
    expect(created.title.value, 'Buy bread');
    expect(created.createdAt.isUtc, isTrue);
    expect(created.id, hasLength(36));
    await tasks.refreshTasks();

    final listed = await tasks.watchActiveTasks().first;
    expect(listed.single.id, created.id);
  });

  test('logout, through the core registry, erases the tasks and the '
      'preferences', () async {
    backendHas([]);
    sendingFails();
    final tasks = getIt<TaskUseCase>();
    await tasks.createTask(title: 'Buy bread');
    await tasks.setShowCompletedTasks(false);

    await cleaners.clearAll();

    // With no stored list, the next opening goes to the backend again.
    expect(await tasks.watchActiveTasks().first, isEmpty);
    expect(await tasks.showCompletedTasks(), isTrue);
    verify(
      () => api.get(TaskApiPaths.tasks, query: any(named: 'query')),
    ).called(1);
  });

  test('the queue registers with the OutboxRegistry: sign-out counts it, and '
      'the core worker sends it', () async {
    sendingFails();
    final tasks = getIt<TaskUseCase>();
    await tasks.createTask(title: 'Buy bread');
    await pumpEventQueue();
    expect(await outboxes.pendingOperations(), 1);

    when(
      () => api.put(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((_) async => {'version': 1});
    final worker = OutboxSyncWorker(registry: outboxes, logger: FakeLogger());

    expect(await worker.run(), isFalse);
    expect(await outboxes.pendingOperations(), 0);
  });

  test(
    'with no network, no module action is blocked: everything is stored '
    'and waits in the queue, and only the refresh gesture shows the error',
    () async {
      // The list already came once, and then the network went down for good.
      backendHas([
        {
          'id': 't-1',
          'title': 'Pay the power bill',
          'status': 'open',
          'createdAt': '2026-10-27T09:00:00.000Z',
          'version': 2,
        },
      ]);
      final tasks = getIt<TaskUseCase>();
      await tasks.watchActiveTasks().first;
      const offline = ApiError(ApiErrorKind.unreachable);
      when(() => api.get(any(), query: any(named: 'query'))).thenThrow(offline);
      when(
        () => api.put(
          any(),
          body: any(named: 'body'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(offline);
      when(
        () => api.patch(
          any(),
          body: any(named: 'body'),
          idempotencyKey: any(named: 'idempotencyKey'),
        ),
      ).thenThrow(offline);

      final created = await tasks.createTask(title: 'Buy bread');
      await tasks.renameTask(created.id, title: 'Buy whole wheat bread');
      await tasks.completeTask('t-1');
      await tasks.reopenTask('t-1');
      await tasks.archiveTask('t-1');
      await tasks.setShowCompletedTasks(false);
      await pumpEventQueue();

      final listed = await tasks.watchActiveTasks().first;
      expect(
        [for (final task in listed) task.title.value],
        ['Buy whole wheat bread'],
      );
      expect(await outboxes.pendingOperations(), 5);
      await expectLater(tasks.refreshTasks(), throwsA(isA<ApiError>()));
    },
  );

  test('a conflict on purpose: two edits offline, the version 409, '
      'the conflicts screen, and "Keep mine", which resends on top of the '
      'server version (chapter 34)', () async {
    backendHas([
      {
        'id': 't-1',
        'title': 'Pay the power bill',
        'status': 'open',
        'createdAt': '2026-10-27T09:00:00.000Z',
        'version': 2,
      },
    ]);
    final tasks = getIt<TaskUseCase>();
    await tasks.watchActiveTasks().first;
    // Database, queue, and chained Streams: more turns than the default.
    Future<void> settle() => pumpEventQueue(times: 100);

    // Two edits offline: they stay in the queue, in order.
    const offline = ApiError(ApiErrorKind.unreachable);
    final patches = <Map<String, Object?>>[];
    Object? patchAnswer = offline;
    when(
      () => api.patch(
        any(),
        body: any(named: 'body'),
        idempotencyKey: any(named: 'idempotencyKey'),
      ),
    ).thenAnswer((invocation) async {
      patches.add(invocation.namedArguments[#body] as Map<String, Object?>);
      final answer = patchAnswer;
      if (answer is ApiError) throw answer;
      return answer;
    });
    await tasks.completeTask('t-1');
    await tasks.renameTask('t-1', title: 'Pay the October power bill');
    await settle();
    expect(await outboxes.pendingOperations(), 2);

    // The network comes back, but someone else had already changed the task:
    // the server's version 5 refuses the first edit, and the second waits for the decision.
    patchAnswer = const ApiError(
      ApiErrorKind.rejected,
      statusCode: 409,
      body: {'code': 'version_conflict'},
    );
    patches.clear();
    final worker = OutboxSyncWorker(registry: outboxes, logger: FakeLogger());
    await worker.run();
    expect(patches, hasLength(1));
    expect(patches.single['baseVersion'], 2);

    // The list warns, and the conflicts screen shows both versions.
    final list = getIt<TaskListBloc>()..add(const TaskListStarted());
    addTearDown(list.close);
    await settle();
    expect(list.state.conflicts, 1);

    when(() => api.get(TaskApiPaths.task('t-1'))).thenAnswer(
      (_) async => {
        'id': 't-1',
        'title': 'Pay the electricity bill',
        'status': 'open',
        'createdAt': '2026-10-27T09:00:00.000Z',
        'version': 5,
      },
    );
    final screen = getIt<TaskConflictsBloc>()
      ..add(const TaskConflictsStarted());
    addTearDown(screen.close);
    await settle();
    final conflict = screen.state.conflicts.single;
    expect(conflict.reason, TaskConflictReason.versionConflict);
    expect(conflict.task.title.value, 'Pay the October power bill');
    expect(conflict.task.status, TaskStatus.done);
    final server = screen.state.servers[conflict.id]! as ServerVersionFound;
    expect(server.task?.title.value, 'Pay the electricity bill');

    // "Keep mine": a single operation, with everything the user did,
    // on top of the version the server has now.
    patchAnswer = {'version': 6};
    patches.clear();
    screen.add(TaskConflictResolved(conflict, TaskConflictChoice.keepMine));
    await settle();

    expect(patches, [
      {
        'title': 'Pay the October power bill',
        'status': 'done',
        'operationId': isA<String>(),
        'baseVersion': 5,
      },
    ]);
    expect(screen.state.conflicts, isEmpty);
    expect(list.state.conflicts, 0);
    expect(await outboxes.pendingOperations(), 0);
  });

  test('the factories hand a new Bloc to each screen', () {
    expect(getIt<TaskListBloc>(), isNot(same(getIt<TaskListBloc>())));
    expect(getIt<TaskEditBloc>(), isNot(same(getIt<TaskEditBloc>())));
    expect(getIt<TaskConflictsBloc>(), isNot(same(getIt<TaskConflictsBloc>())));
  });

  test('once the session scope closes, nothing from the module stays '
      'registered', () async {
    await getIt.popScope();
    expect(getIt.isRegistered<TaskUseCase>(), isFalse);
  });
}
