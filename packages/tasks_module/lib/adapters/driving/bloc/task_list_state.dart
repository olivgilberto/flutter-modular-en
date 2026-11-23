part of 'task_list_bloc.dart';

enum TaskListStatus { loading, ready, failure }

/// A one-time notice, which the View shows and forgets. The failure carries
/// no text: the View chooses the message.
enum TaskListNotice {
  created,
  emptyTitle,
  titleTooLong,
  notFound,
  refreshFailed,
  unavailable;

  static TaskListNotice of(TaskFailure failure) => switch (failure) {
    EmptyTaskTitleFailure() => emptyTitle,
    TaskTitleTooLongFailure() => titleTooLong,
    TaskNotFoundFailure() => notFound,
  };
}

/// The state never overrides `==`: every emission reaches the screen.
final class TaskListState {
  const TaskListState({
    this.status = TaskListStatus.loading,
    this.tasks = const [],
    this.conflicts = 0,
    this.showCompleted = true,
    this.refreshing = false,
    this.notice,
  });

  final TaskListStatus status;

  /// All non-archived tasks, as the database delivers them.
  final List<Task> tasks;

  /// How many changes are waiting for the user's decision (chapter 34).
  final int conflicts;
  final bool showCompleted;
  final bool refreshing;
  final TaskListNotice? notice;

  /// What the screen shows, according to the user's preference.
  List<Task> get visibleTasks => showCompleted
      ? tasks
      : [
          for (final task in tasks)
            if (!task.isDone) task,
        ];

  /// Each copy forgets the previous notice, unless it brings another.
  TaskListState copyWith({
    TaskListStatus? status,
    List<Task>? tasks,
    int? conflicts,
    bool? showCompleted,
    bool? refreshing,
    TaskListNotice? notice,
  }) => TaskListState(
    status: status ?? this.status,
    tasks: tasks ?? this.tasks,
    conflicts: conflicts ?? this.conflicts,
    showCompleted: showCompleted ?? this.showCompleted,
    refreshing: refreshing ?? this.refreshing,
    notice: notice,
  );
}
