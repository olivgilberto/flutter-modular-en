import 'package:core/core.dart';

/// The business deviations of tasks: everything the user can fix.
/// No failure carries text; the View decides the message.
sealed class TaskFailure implements Failure {
  const TaskFailure();
}

/// The title became empty after trimming the spaces at the ends.
final class EmptyTaskTitleFailure extends TaskFailure {
  const EmptyTaskTitleFailure();
}

/// The title goes past the limit agreed with the backend (`TaskTitle.maxLength`).
final class TaskTitleTooLongFailure extends TaskFailure {
  const TaskTitleTooLongFailure();
}

/// The task is no longer in this device's list, as after being archived
/// on another screen.
final class TaskNotFoundFailure extends TaskFailure {
  const TaskNotFoundFailure();
}
