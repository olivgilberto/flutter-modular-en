import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driven/models/task_model.dart';
import 'package:tasks_module/adapters/driven/services/task_local_service.dart';
import 'package:tasks_module/adapters/driven/services/task_remote_service.dart';
import 'package:tasks_module/adapters/driven/task_repository_impl.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/entities/task_conflict.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

import '../../fakes.dart';

final class _MockRemote extends Mock implements TaskRemoteService {}

final class _MockLocal extends Mock implements TaskLocalService {}

final class _MockOutbox extends Mock implements SyncableOutbox {}

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);
  final fromServer = [
    const TaskModel(
      id: 't-1',
      title: 'Buy bread',
      status: 'open',
      createdAt: 0,
      version: 1,
    ),
  ];
  final onDevice = [
    Task(
      id: 't-1',
      title: TaskTitle.parse('Buy bread'),
      createdAt: DateTime.utc(1970),
    ),
  ];

  late _MockRemote remote;
  late _MockLocal local;
  late _MockOutbox outbox;
  late FakeLogger logger;
  late TaskRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(<TaskModel>[]);
    registerFallbackValue(DateTime.utc(2000));
  });

  setUp(() {
    remote = _MockRemote();
    local = _MockLocal();
    outbox = _MockOutbox();
    logger = FakeLogger();
    repository = TaskRepositoryImpl(
      remote: remote,
      local: local,
      outbox: outbox,
      logger: logger,
      now: () => now,
    );
    when(() => remote.fetchActiveTasks()).thenAnswer((_) async => fromServer);
    when(
      () =>
          local.saveActiveTasks(any(), refreshedAt: any(named: 'refreshedAt')),
    ).thenAnswer((_) async {});
    when(
      () => local.watchActiveTasks(),
    ).thenAnswer((_) => Stream.value(onDevice));
  });

  void refreshedAgo(Duration? age) => when(
    () => local.lastRefreshedAt(),
  ).thenAnswer((_) async => age == null ? null : now.subtract(age));

  test(
    'with no stored list, the first comes from the network, and only then is the database '
    'observed',
    () async {
      refreshedAgo(null);

      expect(await repository.watchActiveTasks().first, onDevice);

      verifyInOrder([
        () => remote.fetchActiveTasks(),
        () => local.saveActiveTasks(fromServer, refreshedAt: now),
        () => local.watchActiveTasks(),
      ]);
    },
  );

  test(
    'with no stored list and no network, the error arrives through the Stream',
    () async {
      refreshedAgo(null);
      when(
        () => remote.fetchActiveTasks(),
      ).thenThrow(const ApiError(ApiErrorKind.unreachable));

      await expectLater(
        repository.watchActiveTasks(),
        emitsError(isA<ApiError>()),
      );
      verifyNever(() => local.watchActiveTasks());
    },
  );

  test('within the deadline, the database answers alone', () async {
    refreshedAgo(const Duration(minutes: 4, seconds: 59));

    expect(await repository.watchActiveTasks().first, onDevice);
    await pumpEventQueue();

    verifyNever(() => remote.fetchActiveTasks());
  });

  test(
    'expired, the database list arrives right away, and the network\'s comes '
    'behind it',
    () async {
      refreshedAgo(TaskRepositoryImpl.defaultActiveTasksTtl);
      final network = Completer<List<TaskModel>>();
      when(() => remote.fetchActiveTasks()).thenAnswer((_) => network.future);

      expect(await repository.watchActiveTasks().first, onDevice);
      verifyNever(
        () => local.saveActiveTasks(
          any(),
          refreshedAt: any(named: 'refreshedAt'),
        ),
      );

      network.complete(fromServer);
      await pumpEventQueue();
      verify(
        () => local.saveActiveTasks(fromServer, refreshedAt: now),
      ).called(1);
    },
  );

  test('a time stored in the future, from a clock that went back, counts as '
      'expired', () async {
    refreshedAgo(const Duration(hours: -1));

    await repository.watchActiveTasks().first;
    await pumpEventQueue();

    verify(() => remote.fetchActiveTasks()).called(1);
  });

  test(
    'behind the scenes, the network failure goes away, and the database one goes to the crash '
    'log',
    () async {
      refreshedAgo(const Duration(hours: 1));
      when(
        () => remote.fetchActiveTasks(),
      ).thenThrow(const ApiError(ApiErrorKind.unreachable));
      expect(await repository.watchActiveTasks().first, onDevice);
      await pumpEventQueue();
      expect(logger.errors, isEmpty);

      when(() => remote.fetchActiveTasks()).thenAnswer((_) async => fromServer);
      when(
        () => local.saveActiveTasks(
          any(),
          refreshedAt: any(named: 'refreshedAt'),
        ),
      ).thenThrow(const LocalDatabaseError('database locked'));
      expect(await repository.watchActiveTasks().first, onDevice);
      await pumpEventQueue();
      expect(logger.errors, ['tasks refresh']);
    },
  );

  test('concurrent requests share the same trip to the network, and the forced '
      'one takes the failure to whoever asked', () async {
    final network = Completer<List<TaskModel>>();
    when(() => remote.fetchActiveTasks()).thenAnswer((_) => network.future);

    final first = repository.refreshActiveTasks();
    final second = repository.refreshActiveTasks();
    network.complete(fromServer);
    await Future.wait([first, second]);
    verify(() => remote.fetchActiveTasks()).called(1);

    when(
      () => remote.fetchActiveTasks(),
    ).thenThrow(const ApiError(ApiErrorKind.server, statusCode: 503));
    await expectLater(
      repository.refreshActiveTasks(),
      throwsA(isA<ApiError>()),
    );
  });

  group('writes', () {
    setUpAll(() => registerFallbackValue(onDevice.single));

    test(
      'stores on the device and, without waiting, asks the queue to go out',
      () async {
        final sending = Completer<bool>();
        when(() => local.saveTask(any())).thenAnswer((_) async {});
        when(() => local.archiveTask(any())).thenAnswer((_) async {});
        when(() => outbox.sync()).thenAnswer((_) => sending.future);

        await repository.saveTask(onDevice.single);
        await repository.archiveTask('t-1');

        verifyInOrder([
          () => local.saveTask(onDevice.single),
          () => outbox.sync(),
          () => local.archiveTask('t-1'),
          () => outbox.sync(),
        ]);
        sending.complete(false);
      },
    );

    test('a database failure while sending goes to the crash log', () async {
      when(() => local.saveTask(any())).thenAnswer((_) async {});
      when(
        () => outbox.sync(),
      ).thenAnswer((_) async => throw const LocalDatabaseError('locked'));

      await repository.saveTask(onDevice.single);
      await pumpEventQueue();

      expect(logger.errors, ['tasks outbox']);
    });
  });

  group('conflicts (chapter 34)', () {
    const server = TaskModel(
      id: 't-1',
      title: 'Buy French bread',
      status: 'open',
      createdAt: 0,
      version: 6,
    );
    final conflict = TaskConflict(
      id: 'c-1',
      reason: TaskConflictReason.versionConflict,
      task: onDevice.single,
      createdAt: now,
    );

    setUpAll(() => registerFallbackValue(server));

    setUp(() {
      when(() => remote.fetchTask('t-1')).thenAnswer((_) async => server);
      when(() => outbox.sync()).thenAnswer((_) async => false);
      when(
        () => local.keepLocalVersion(
          any(),
          taskId: any(named: 'taskId'),
          serverVersion: any(named: 'serverVersion'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => local.acceptServerVersion(
          any(),
          taskId: any(named: 'taskId'),
          server: any(named: 'server'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => local.discardConflict(any(), taskId: any(named: 'taskId')),
      ).thenAnswer((_) async {});
    });

    test('the server version arrives as an entity, or null if it was '
        'deleted', () async {
      expect(
        (await repository.fetchServerTask('t-1'))?.title.value,
        'Buy French bread',
      );

      when(() => remote.fetchTask('t-1')).thenAnswer((_) async => null);
      expect(await repository.fetchServerTask('t-1'), isNull);
    });

    test('keep mine asks the server right away, rebases on its version, '
        'and asks the queue to go out', () async {
      await repository.resolveConflict(conflict, TaskConflictChoice.keepMine);

      verifyInOrder([
        () => remote.fetchTask('t-1'),
        () => local.keepLocalVersion('c-1', taskId: 't-1', serverVersion: 6),
        () => outbox.sync(),
      ]);
    });

    test('keep mine with no network does not touch the device', () async {
      when(
        () => remote.fetchTask('t-1'),
      ).thenThrow(const ApiError(ApiErrorKind.unreachable));

      await expectLater(
        repository.resolveConflict(conflict, TaskConflictChoice.keepMine),
        throwsA(isA<ApiError>()),
      );
      verifyNever(
        () => local.keepLocalVersion(
          any(),
          taskId: any(named: 'taskId'),
          serverVersion: any(named: 'serverVersion'),
        ),
      );
    });

    for (final choice in [
      TaskConflictChoice.keepServer,
      TaskConflictChoice.redo,
    ]) {
      test('${choice.name} stores the version the server has now', () async {
        await repository.resolveConflict(conflict, choice);

        verify(
          () => local.acceptServerVersion('c-1', taskId: 't-1', server: server),
        ).called(1);
        verifyNever(() => outbox.sync());
      });
    }

    test(
      'discard needs no network and refreshes the list behind the scenes',
      () async {
        await repository.resolveConflict(conflict, TaskConflictChoice.discard);
        await pumpEventQueue();

        verify(() => local.discardConflict('c-1', taskId: 't-1')).called(1);
        verifyNever(() => remote.fetchTask(any()));
        verify(() => remote.fetchActiveTasks()).called(1);
      },
    );

    test('discard with no network finishes, and the list waits for the next '
        'opening', () async {
      when(
        () => remote.fetchActiveTasks(),
      ).thenThrow(const ApiError(ApiErrorKind.unreachable));

      await repository.resolveConflict(conflict, TaskConflictChoice.discard);
      await pumpEventQueue();

      expect(logger.errors, isEmpty);
    });

    test('the conflicts come from the database', () async {
      when(
        () => local.watchConflicts(),
      ).thenAnswer((_) => Stream.value([conflict]));

      expect(await repository.watchConflicts().first, [conflict]);
    });
  });
}
