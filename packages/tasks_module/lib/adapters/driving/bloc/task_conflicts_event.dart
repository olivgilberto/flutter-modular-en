part of 'task_conflicts_bloc.dart';

sealed class TaskConflictsEvent {
  const TaskConflictsEvent();
}

final class TaskConflictsStarted extends TaskConflictsEvent {
  const TaskConflictsStarted();
}

/// Fetch, or fetch again, the server version of a conflict.
final class ServerVersionRequested extends TaskConflictsEvent {
  const ServerVersionRequested(this.conflict);

  final TaskConflict conflict;
}

final class TaskConflictResolved extends TaskConflictsEvent {
  const TaskConflictResolved(this.conflict, this.choice);

  final TaskConflict conflict;
  final TaskConflictChoice choice;
}
