import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driving/bloc/task_list_bloc.dart';
import 'package:tasks_module/domain/task_failure.dart';

import 'driving_mocks.dart';

void main() {
  late MockTaskUseCase tasks;

  setUp(() {
    tasks = MockTaskUseCase();
    when(() => tasks.showCompletedTasks()).thenAnswer((_) async => true);
    when(
      () => tasks.watchActiveTasks(),
    ).thenAnswer((_) => Stream.value([bread, light]));
    when(() => tasks.watchConflicts()).thenAnswer((_) => Stream.value([]));
  });

  /// A Bloc already started, with the list loaded.
  Future<TaskListBloc> started() async {
    final bloc = TaskListBloc(tasks: tasks)..add(const TaskListStarted());
    addTearDown(bloc.close);
    await pumpEventQueue();
    return bloc;
  }

  test('starts loading', () {
    final bloc = TaskListBloc(tasks: tasks);
    addTearDown(bloc.close);
    expect(bloc.state.status, TaskListStatus.loading);
  });

  test('the database list, the preference, and the conflict count reach '
      'the state', () async {
    when(() => tasks.showCompletedTasks()).thenAnswer((_) async => false);
    when(() => tasks.watchConflicts()).thenAnswer(
      (_) => Stream.value([conflictOf(bread), conflictOf(light, id: 'c-2')]),
    );

    final bloc = await started();

    expect(bloc.state.status, TaskListStatus.ready);
    expect(bloc.state.tasks, [bread, light]);
    expect(bloc.state.conflicts, 2);
    expect(bloc.state.showCompleted, isFalse);
    expect(bloc.state.visibleTasks, [bread]);
  });

  test('with no stored preference, done tasks are shown', () async {
    when(
      () => tasks.showCompletedTasks(),
    ).thenThrow(const LocalDatabaseError('locked'));

    final bloc = await started();

    expect(bloc.state.showCompleted, isTrue);
    expect(bloc.state.visibleTasks, [bread, light]);
  });

  for (final error in [
    const ApiError(ApiErrorKind.unreachable),
    const LocalDatabaseError('locked'),
  ]) {
    test('a failing first load (${error.runtimeType}) becomes a failure, and '
        'trying again loads', () async {
      when(
        () => tasks.watchActiveTasks(),
      ).thenAnswer((_) => Stream.error(error));
      final bloc = await started();
      expect(bloc.state.status, TaskListStatus.failure);

      when(
        () => tasks.watchActiveTasks(),
      ).thenAnswer((_) => Stream.value([bread]));
      bloc.add(const TaskListStarted());
      await pumpEventQueue();

      expect(bloc.state.status, TaskListStatus.ready);
      expect(bloc.state.tasks, [bread]);
    });
  }

  test('without the conflict count, the list goes on', () async {
    when(
      () => tasks.watchConflicts(),
    ).thenAnswer((_) => Stream.error(const LocalDatabaseError('locked')));

    final bloc = await started();

    expect(bloc.state.status, TaskListStatus.ready);
    expect(bloc.state.conflicts, 0);
  });

  group('create', () {
    test('once stored, the notice asks to clear the field', () async {
      when(
        () => tasks.createTask(title: any(named: 'title')),
      ).thenAnswer((_) async => bread);
      final bloc = await started();

      bloc.add(const TaskCreated('Buy bread'));
      await pumpEventQueue();

      verify(() => tasks.createTask(title: 'Buy bread')).called(1);
      expect(bloc.state.notice, TaskListNotice.created);
    });

    for (final (thrown, notice) in [
      (const EmptyTaskTitleFailure(), TaskListNotice.emptyTitle),
      (const TaskTitleTooLongFailure(), TaskListNotice.titleTooLong),
      (const TaskNotFoundFailure(), TaskListNotice.notFound),
      (const LocalDatabaseError('locked'), TaskListNotice.unavailable),
    ]) {
      test('${thrown.runtimeType} becomes the ${notice.name} notice', () async {
        when(
          () => tasks.createTask(title: any(named: 'title')),
        ).thenThrow(thrown);
        final bloc = await started();

        bloc.add(const TaskCreated(''));
        await pumpEventQueue();

        expect(bloc.state.notice, notice);
      });
    }
  });

  test('toggling completes the open one and reopens the done one', () async {
    when(() => tasks.completeTask(any())).thenAnswer((_) async {});
    when(() => tasks.reopenTask(any())).thenAnswer((_) async {});
    final bloc = await started();

    bloc
      ..add(TaskToggled(bread))
      ..add(TaskToggled(light));
    await pumpEventQueue();

    verify(() => tasks.completeTask('t-1')).called(1);
    verify(() => tasks.reopenTask('t-2')).called(1);
  });

  group('refresh', () {
    test('marks progress and the end', () async {
      final network = Completer<void>();
      when(() => tasks.refreshTasks()).thenAnswer((_) => network.future);
      final bloc = await started();

      bloc.add(const TaskListRefreshed());
      await pumpEventQueue();
      expect(bloc.state.refreshing, isTrue);

      network.complete();
      await pumpEventQueue();
      expect(bloc.state.refreshing, isFalse);
      expect(bloc.state.notice, isNull);
    });

    test('a second gesture during the first one is ignored', () async {
      final network = Completer<void>();
      when(() => tasks.refreshTasks()).thenAnswer((_) => network.future);
      final bloc = await started();

      bloc
        ..add(const TaskListRefreshed())
        ..add(const TaskListRefreshed());
      await pumpEventQueue();
      network.complete();
      await pumpEventQueue();

      verify(() => tasks.refreshTasks()).called(1);
    });

    for (final (thrown, notice) in [
      (const ApiError(ApiErrorKind.unreachable), TaskListNotice.refreshFailed),
      (const LocalDatabaseError('locked'), TaskListNotice.unavailable),
    ]) {
      test(
        '${thrown.runtimeType} becomes the ${notice.name} notice, and the list '
        'stays',
        () async {
          when(() => tasks.refreshTasks()).thenThrow(thrown);
          final bloc = await started();

          bloc.add(const TaskListRefreshed());
          await pumpEventQueue();

          expect(bloc.state.refreshing, isFalse);
          expect(bloc.state.notice, notice);
          expect(bloc.state.tasks, [bread, light]);
        },
      );
    }
  });

  group('show done tasks', () {
    test('switches right away and stores the choice', () async {
      when(() => tasks.setShowCompletedTasks(any())).thenAnswer((_) async {});
      final bloc = await started();

      bloc.add(const ShowCompletedToggled());
      await pumpEventQueue();

      expect(bloc.state.showCompleted, isFalse);
      expect(bloc.state.visibleTasks, [bread]);
      verify(() => tasks.setShowCompletedTasks(false)).called(1);
    });

    test(
      'unable to store it, the toggle holds until closing, with a notice',
      () async {
        when(
          () => tasks.setShowCompletedTasks(any()),
        ).thenThrow(const LocalDatabaseError('locked'));
        final bloc = await started();

        bloc.add(const ShowCompletedToggled());
        await pumpEventQueue();

        expect(bloc.state.showCompleted, isFalse);
        expect(bloc.state.notice, TaskListNotice.unavailable);
      },
    );
  });

  test('each copy of the state forgets the previous notice', () {
    const state = TaskListState(notice: TaskListNotice.created);
    expect(state.copyWith(refreshing: true).notice, isNull);
  });
}
