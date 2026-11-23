part of 'task_edit_bloc.dart';

sealed class TaskEditEvent {
  const TaskEditEvent();
}

final class TaskEditStarted extends TaskEditEvent {
  const TaskEditStarted(this.taskId);

  final String taskId;
}

/// The raw text of the field: the use case does the validating.
final class TaskEditSubmitted extends TaskEditEvent {
  const TaskEditSubmitted(this.title);

  final String title;
}

final class TaskEditArchived extends TaskEditEvent {
  const TaskEditArchived();
}
