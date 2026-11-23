import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/application/ports/task_repository.dart';
import 'package:tasks_module/application/use_cases/task_use_case.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/entities/task_conflict.dart';
import 'package:tasks_module/domain/task_failure.dart';
import 'package:tasks_module/domain/value_objects/task_title.dart';

import '../fakes.dart';

final class _MockTaskRepository extends Mock implements TaskRepository {}

void main() {
  final now = DateTime.utc(2026, 10, 27, 9);
  final bread = Task(
    id: 't-1',
    title: TaskTitle.parse('Buy bread'),
    createdAt: now,
  );

  late _MockTaskRepository repository;
  late FakeAnalytics analytics;
  late TaskUseCase useCase;

  setUpAll(() => registerFallbackValue(bread));

  setUp(() {
    repository = _MockTaskRepository();
    analytics = FakeAnalytics();
    useCase = TaskUseCase(
      repository: repository,
      newId: () => 'new-id',
      now: () => now,
      analytics: analytics,
    );
    when(() => repository.saveTask(any())).thenAnswer((_) async {});
    when(() => repository.archiveTask(any())).thenAnswer((_) async {});
  });

  void stored(Task? task) =>
      when(() => repository.findTask(any())).thenAnswer((_) async => task);

  Task saved() =>
      verify(() => repository.saveTask(captureAny())).captured.single as Task;

  test('create gives the task a device id, the current time, and the trimmed '
      'title', () async {
    final task = await useCase.createTask(title: '  Pay the power bill ');

    expect(task.id, 'new-id');
    expect(task.createdAt, now);
    expect(task.title.value, 'Pay the power bill');
    expect(task.status, TaskStatus.open);
    expect(saved(), same(task));
  });

  test('an invalid title does not reach the port', () async {
    await expectLater(
      useCase.createTask(title: '   '),
      throwsA(isA<EmptyTaskTitleFailure>()),
    );
    stored(bread);
    await expectLater(
      useCase.renameTask('t-1', title: 'x' * 201),
      throwsA(isA<TaskTitleTooLongFailure>()),
    );
    verifyNever(() => repository.saveTask(any()));
  });

  test('complete, reopen, and rename store the transformed task', () async {
    stored(bread);
    await useCase.completeTask('t-1');
    expect(saved().status, TaskStatus.done);

    stored(bread.complete());
    await useCase.reopenTask('t-1');
    expect(saved().status, TaskStatus.open);

    stored(bread);
    await useCase.renameTask('t-1', title: 'Buy whole wheat bread');
    expect(saved().title.value, 'Buy whole wheat bread');
  });

  test('archive goes through the port\'s own operation', () async {
    stored(bread);
    await useCase.archiveTask('t-1');

    verify(() => repository.archiveTask('t-1')).called(1);
    verifyNever(() => repository.saveTask(any()));
  });

  test('a task that is not in the list cannot be changed', () async {
    stored(null);
    await expectLater(
      useCase.completeTask('t-9'),
      throwsA(isA<TaskNotFoundFailure>()),
    );

    // Archived is the same as out of the list.
    when(() => repository.findTask('t-1')).thenAnswer(
      (_) async => Task(
        id: 't-1',
        title: bread.title,
        createdAt: now,
        status: TaskStatus.archived,
      ),
    );
    await expectLater(
      useCase.archiveTask('t-1'),
      throwsA(isA<TaskNotFoundFailure>()),
    );
    verifyNever(() => repository.saveTask(any()));
    verifyNever(() => repository.archiveTask(any()));
  });

  test('every successful write logs its event, with no title or '
      'id', () async {
    final task = await useCase.createTask(title: 'Pay the power bill');
    stored(task);
    await useCase.renameTask(task.id, title: 'Pay the electricity bill');
    await useCase.completeTask(task.id);
    await useCase.reopenTask(task.id);
    await useCase.archiveTask(task.id);

    expect(analytics.names, [
      'tasks_task_created',
      'tasks_task_renamed',
      'tasks_task_completed',
      'tasks_task_reopened',
      'tasks_task_archived',
    ]);
    for (final (_, parameters) in analytics.events) {
      expect(parameters, isEmpty);
    }
  });

  test('a write that fails logs no event', () async {
    await expectLater(
      useCase.createTask(title: '   '),
      throwsA(isA<EmptyTaskTitleFailure>()),
    );
    stored(null);
    await expectLater(
      useCase.archiveTask('t-1'),
      throwsA(isA<TaskNotFoundFailure>()),
    );
    when(
      () => repository.saveTask(any()),
    ).thenThrow(const LocalDatabaseError('disk full'));
    await expectLater(
      useCase.createTask(title: 'Pay the power bill'),
      throwsA(isA<LocalDatabaseError>()),
    );

    expect(analytics.events, isEmpty);
  });

  test('the done-tasks preference goes through the port', () async {
    when(() => repository.showCompletedTasks()).thenAnswer((_) async => false);
    when(
      () => repository.saveShowCompletedTasks(any()),
    ).thenAnswer((_) async {});

    expect(await useCase.showCompletedTasks(), isFalse);
    await useCase.setShowCompletedTasks(true);
    verify(() => repository.saveShowCompletedTasks(true)).called(1);
  });

  test(
    'refresh asks the port for the new list, and the failure reaches whoever '
    'asked',
    () async {
      when(
        () => repository.refreshActiveTasks(),
      ).thenAnswer((_) async => throw const ApiError(ApiErrorKind.unreachable));

      await expectLater(useCase.refreshTasks(), throwsA(isA<ApiError>()));
      verify(() => repository.refreshActiveTasks()).called(1);
    },
  );

  test(
    'find returns the task from the list, and null for an archived one or one '
    'that does not exist',
    () async {
      stored(bread);
      expect(await useCase.findTask('t-1'), same(bread));

      stored(
        Task(
          id: 't-1',
          title: bread.title,
          createdAt: now,
          status: TaskStatus.archived,
        ),
      );
      expect(await useCase.findTask('t-1'), isNull);

      stored(null);
      expect(await useCase.findTask('t-1'), isNull);
    },
  );

  group('conflicts (chapter 34)', () {
    TaskConflict conflict(TaskConflictReason reason) =>
        TaskConflict(id: 'c-1', reason: reason, task: bread, createdAt: now);

    setUpAll(() {
      registerFallbackValue(conflict(TaskConflictReason.rejected));
      registerFallbackValue(TaskConflictChoice.discard);
    });

    setUp(() {
      when(
        () => repository.resolveConflict(any(), any()),
      ).thenAnswer((_) async {});
    });

    test('each reason has its own decisions', () {
      expect(conflict(TaskConflictReason.versionConflict).choices, [
        TaskConflictChoice.keepMine,
        TaskConflictChoice.keepServer,
      ]);
      expect(conflict(TaskConflictReason.rejected).choices, [
        TaskConflictChoice.redo,
        TaskConflictChoice.discard,
      ]);
    });

    test('the decision that fits the reason reaches the port', () async {
      final versionConflict = conflict(TaskConflictReason.versionConflict);

      await useCase.resolveConflict(
        versionConflict,
        TaskConflictChoice.keepMine,
      );

      verify(
        () => repository.resolveConflict(
          versionConflict,
          TaskConflictChoice.keepMine,
        ),
      ).called(1);
      final (name, parameters) = analytics.events.single;
      expect(name, 'tasks_conflict_resolved');
      expect(parameters, {'reason': 'versionConflict', 'choice': 'keepMine'});
    });

    test(
      'a decision that does not fit is the caller\'s defect, and does not reach '
      'the port',
      () async {
        await expectLater(
          useCase.resolveConflict(
            conflict(TaskConflictReason.rejected),
            TaskConflictChoice.keepMine,
          ),
          throwsArgumentError,
        );
        await expectLater(
          useCase.resolveConflict(
            conflict(TaskConflictReason.versionConflict),
            TaskConflictChoice.discard,
          ),
          throwsArgumentError,
        );
        verifyNever(() => repository.resolveConflict(any(), any()));
      },
    );

    test('the list and the server version go through the port', () async {
      final versionConflict = conflict(TaskConflictReason.versionConflict);
      when(
        () => repository.watchConflicts(),
      ).thenAnswer((_) => Stream.value([versionConflict]));
      when(
        () => repository.fetchServerTask('t-1'),
      ).thenAnswer((_) async => bread.complete());

      expect(await useCase.watchConflicts().first, [versionConflict]);
      expect(
        (await useCase.serverVersion(versionConflict))?.status,
        TaskStatus.done,
      );
    });

    test('conflicts are equal by id', () {
      final a = conflict(TaskConflictReason.rejected);
      final b = TaskConflict(
        id: 'c-1',
        reason: TaskConflictReason.versionConflict,
        task: bread.complete(),
        createdAt: now.add(const Duration(hours: 1)),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
