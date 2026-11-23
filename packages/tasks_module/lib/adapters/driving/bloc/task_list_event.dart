part of 'task_list_bloc.dart';

sealed class TaskListEvent {
  const TaskListEvent();
}

/// The screen opened, or the user asked to try again after a failure on
/// the first load.
final class TaskListStarted extends TaskListEvent {
  const TaskListStarted();
}

/// The raw text of the field: the use case does the validating.
final class TaskCreated extends TaskListEvent {
  const TaskCreated(this.title);

  final String title;
}

/// Complete an open task, or reopen a done one.
final class TaskToggled extends TaskListEvent {
  const TaskToggled(this.task);

  final Task task;
}

/// The pull-to-refresh gesture.
final class TaskListRefreshed extends TaskListEvent {
  const TaskListRefreshed();
}

final class ShowCompletedToggled extends TaskListEvent {
  const ShowCompletedToggled();
}
