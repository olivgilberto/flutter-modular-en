import 'task.dart';

/// Why the server did not accept what the user did (chapter 12).
enum TaskConflictReason {
  /// Someone else changed the task first: there are two versions, and one stays.
  versionConflict,

  /// The server refused the change itself: it will never go through as it is.
  rejected,
}

/// What the user can decide when facing a conflict.
enum TaskConflictChoice {
  /// The device's version stays, over the server's.
  keepMine,

  /// The server's version stays, and the device's is discarded.
  keepServer,

  /// The refused change is discarded.
  discard,

  /// The refused change is discarded, and the user acts again on the task's
  /// current state.
  redo,
}

/// A change the server did not accept, waiting for the user. The domain
/// does not know there was an HTTP response, a queue, or a table: it knows
/// there is a task, its version on the device, and a decision to make. The
/// server version is fetched when the user opens the resolution, because
/// until then it may have changed again.
final class TaskConflict {
  const TaskConflict({
    required this.id,
    required this.reason,
    required this.task,
    required this.createdAt,
  });

  final String id;
  final TaskConflictReason reason;

  /// The task as it is on the device, with what the user did.
  final Task task;

  /// When the refusal arrived, in UTC.
  final DateTime createdAt;

  /// The decisions that make sense for the reason.
  List<TaskConflictChoice> get choices => switch (reason) {
    TaskConflictReason.versionConflict => const [
      TaskConflictChoice.keepMine,
      TaskConflictChoice.keepServer,
    ],
    TaskConflictReason.rejected => const [
      TaskConflictChoice.redo,
      TaskConflictChoice.discard,
    ],
  };

  @override
  bool operator ==(Object other) => other is TaskConflict && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
