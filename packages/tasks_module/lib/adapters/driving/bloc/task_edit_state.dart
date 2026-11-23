part of 'task_edit_bloc.dart';

/// States never override `==`: every emission reaches the screen.
sealed class TaskEditState {
  const TaskEditState();
}

final class TaskEditLoading extends TaskEditState {
  const TaskEditLoading();
}

/// The task left the list, here or on another screen.
final class TaskEditNotFound extends TaskEditState {
  const TaskEditNotFound();
}

final class TaskEditReady extends TaskEditState {
  const TaskEditReady(this.task, {this.failure, this.unavailable = false});

  final Task task;

  /// The last attempt rejected by the domain, if any.
  final TaskFailure? failure;

  /// The last attempt failed in the device's database.
  final bool unavailable;
}

final class TaskEditSaving extends TaskEditState {
  const TaskEditSaving(this.task);

  final Task task;
}

/// Stored on the device: the screen closes. The send happens behind the scenes.
final class TaskEditDone extends TaskEditState {
  const TaskEditDone();
}
