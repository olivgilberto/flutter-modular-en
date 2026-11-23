import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driving/bloc/task_edit_bloc.dart';
import 'package:tasks_module/domain/task_failure.dart';

import 'driving_mocks.dart';

void main() {
  late MockTaskUseCase tasks;

  setUp(() {
    tasks = MockTaskUseCase();
    when(() => tasks.findTask('t-1')).thenAnswer((_) async => bread);
    when(
      () => tasks.renameTask(any(), title: any(named: 'title')),
    ).thenAnswer((_) async {});
    when(() => tasks.archiveTask(any())).thenAnswer((_) async {});
  });

  /// The Bloc and every state it emitted.
  Future<(TaskEditBloc, List<TaskEditState>)> opened() async {
    final bloc = TaskEditBloc(tasks: tasks);
    addTearDown(bloc.close);
    final states = <TaskEditState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);
    bloc.add(const TaskEditStarted('t-1'));
    await pumpEventQueue();
    return (bloc, states);
  }

  test('starts loading and opens the task from the list', () async {
    final (bloc, _) = await opened();

    expect(bloc.state, isA<TaskEditReady>());
    expect((bloc.state as TaskEditReady).task, bread);
  });

  for (final (label, stub) in [
    ('out of the list', () async => null),
    (
      'with the database locked',
      () async => throw const LocalDatabaseError('x'),
    ),
  ]) {
    test('$label, the task is not found', () async {
      when(() => tasks.findTask('t-1')).thenAnswer((_) => stub());

      final (bloc, _) = await opened();

      expect(bloc.state, isA<TaskEditNotFound>());
    });
  }

  test('save renames with the raw text and closes', () async {
    final (bloc, states) = await opened();

    bloc.add(const TaskEditSubmitted('  Buy whole wheat bread '));
    await pumpEventQueue();

    verify(
      () => tasks.renameTask('t-1', title: '  Buy whole wheat bread '),
    ).called(1);
    expect(states.skip(1).map((s) => s.runtimeType), [
      TaskEditSaving,
      TaskEditDone,
    ]);
  });

  test('archiving closes', () async {
    final (bloc, _) = await opened();

    bloc.add(const TaskEditArchived());
    await pumpEventQueue();

    verify(() => tasks.archiveTask('t-1')).called(1);
    expect(bloc.state, isA<TaskEditDone>());
  });

  test('repeated taps save only once', () async {
    final saving = Completer<void>();
    when(
      () => tasks.renameTask(any(), title: any(named: 'title')),
    ).thenAnswer((_) => saving.future);
    final (bloc, _) = await opened();

    bloc
      ..add(const TaskEditSubmitted('Another'))
      ..add(const TaskEditSubmitted('Another'));
    await pumpEventQueue();
    saving.complete();
    await pumpEventQueue();

    verify(() => tasks.renameTask(any(), title: any(named: 'title'))).called(1);
  });

  test(
    'the rejected title comes back to the screen with the failure',
    () async {
      when(
        () => tasks.renameTask(any(), title: any(named: 'title')),
      ).thenThrow(const EmptyTaskTitleFailure());
      final (bloc, _) = await opened();

      bloc.add(const TaskEditSubmitted('   '));
      await pumpEventQueue();

      final state = bloc.state as TaskEditReady;
      expect(state.task, bread);
      expect(state.failure, isA<EmptyTaskTitleFailure>());
    },
  );

  test('the task that left the list halfway', () async {
    when(() => tasks.archiveTask(any())).thenThrow(const TaskNotFoundFailure());
    final (bloc, _) = await opened();

    bloc.add(const TaskEditArchived());
    await pumpEventQueue();

    expect(bloc.state, isA<TaskEditNotFound>());
  });

  test(
    'the locked database comes back to the screen with the generic notice',
    () async {
      when(
        () => tasks.renameTask(any(), title: any(named: 'title')),
      ).thenThrow(const LocalDatabaseError('locked'));
      final (bloc, _) = await opened();

      bloc.add(const TaskEditSubmitted('Another'));
      await pumpEventQueue();

      final state = bloc.state as TaskEditReady;
      expect(state.unavailable, isTrue);
      expect(state.failure, isNull);
    },
  );

  test('before the task opens, save does nothing', () async {
    when(() => tasks.findTask('t-1')).thenAnswer((_) async => null);
    final (bloc, _) = await opened();

    bloc.add(const TaskEditSubmitted('Another'));
    await pumpEventQueue();

    verifyNever(() => tasks.renameTask(any(), title: any(named: 'title')));
  });
}
