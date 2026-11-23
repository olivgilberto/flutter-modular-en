import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/use_cases/task_use_case.dart';
import '../../../domain/entities/task.dart';
import '../../../domain/entities/task_conflict.dart';
import '../../../domain/task_failure.dart';

part 'task_list_event.dart';
part 'task_list_state.dart';

/// The ViewModel of the task list. It depends only on the use case. No
/// event checks the connection: writing always works, and only the refresh
/// gesture can fail for lack of a network (chapter 33).
///
/// Not `final`: the View tests mock it with `implements`.
class TaskListBloc extends Bloc<TaskListEvent, TaskListState> {
  TaskListBloc({required TaskUseCase tasks})
    : _tasks = tasks,
      super(const TaskListState()) {
    // Starting over, after a failure, replaces the old subscriptions.
    on<TaskListStarted>(_onStarted, transformer: restartable());
    // In the order the user typed.
    on<TaskCreated>(_onCreated, transformer: sequential());
    on<TaskToggled>(_onToggled);
    on<TaskListRefreshed>(_onRefreshed, transformer: droppable());
    on<ShowCompletedToggled>(
      _onShowCompletedToggled,
      transformer: sequential(),
    );
  }

  final TaskUseCase _tasks;

  Future<void> _onStarted(
    TaskListStarted event,
    Emitter<TaskListState> emit,
  ) async {
    emit(state.copyWith(status: TaskListStatus.loading));
    try {
      emit(state.copyWith(showCompleted: await _tasks.showCompletedTasks()));
    } on LocalDatabaseError {
      // Without the preference, done tasks are shown, as on first use.
    }
    await Future.wait([
      emit.forEach<List<Task>>(
        _tasks.watchActiveTasks(),
        onData: (tasks) =>
            state.copyWith(status: TaskListStatus.ready, tasks: tasks),
        onError: (error, stackTrace) => _technical(error)
            ? state.copyWith(status: TaskListStatus.failure)
            : Error.throwWithStackTrace(error, stackTrace),
      ),
      emit.forEach<List<TaskConflict>>(
        _tasks.watchConflicts(),
        onData: (conflicts) => state.copyWith(conflicts: conflicts.length),
        // Without the count, the list goes on; the notice comes back next time.
        onError: (error, stackTrace) => _technical(error)
            ? state
            : Error.throwWithStackTrace(error, stackTrace),
      ),
    ]);
  }

  Future<void> _onCreated(TaskCreated event, Emitter<TaskListState> emit) =>
      _attempt(emit, () async {
        await _tasks.createTask(title: event.title);
        emit(state.copyWith(notice: TaskListNotice.created));
      });

  Future<void> _onToggled(TaskToggled event, Emitter<TaskListState> emit) =>
      _attempt(
        emit,
        () => event.task.isDone
            ? _tasks.reopenTask(event.task.id)
            : _tasks.completeTask(event.task.id),
      );

  Future<void> _onRefreshed(
    TaskListRefreshed event,
    Emitter<TaskListState> emit,
  ) async {
    emit(state.copyWith(refreshing: true));
    try {
      await _tasks.refreshTasks();
      emit(state.copyWith(refreshing: false));
    } on ApiError {
      emit(
        state.copyWith(refreshing: false, notice: TaskListNotice.refreshFailed),
      );
    } on LocalDatabaseError {
      emit(
        state.copyWith(refreshing: false, notice: TaskListNotice.unavailable),
      );
    }
  }

  Future<void> _onShowCompletedToggled(
    ShowCompletedToggled event,
    Emitter<TaskListState> emit,
  ) async {
    final show = !state.showCompleted;
    emit(state.copyWith(showCompleted: show));
    try {
      await _tasks.setShowCompletedTasks(show);
    } on LocalDatabaseError {
      emit(state.copyWith(notice: TaskListNotice.unavailable));
    }
  }

  /// The failures the user understands become a notice; the technical
  /// ones, a generic notice. A bug is still a bug.
  Future<void> _attempt(
    Emitter<TaskListState> emit,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on TaskFailure catch (failure) {
      emit(state.copyWith(notice: TaskListNotice.of(failure)));
    } on LocalDatabaseError {
      emit(state.copyWith(notice: TaskListNotice.unavailable));
    }
  }

  static bool _technical(Object error) =>
      error is ApiError || error is LocalDatabaseError;
}
