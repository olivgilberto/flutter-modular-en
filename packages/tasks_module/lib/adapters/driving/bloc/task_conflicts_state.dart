part of 'task_conflicts_bloc.dart';

/// The server version of a conflict, as the screen knows it.
sealed class ServerVersion {
  const ServerVersion();
}

final class ServerVersionLoading extends ServerVersion {
  const ServerVersionLoading();
}

/// The server's current version, or `null` when the task was deleted there.
final class ServerVersionFound extends ServerVersion {
  const ServerVersionFound(this.task);

  final Task? task;
}

/// No network: the comparison waits, and "Discard" is still possible.
final class ServerVersionUnavailable extends ServerVersion {
  const ServerVersionUnavailable();
}

enum TaskConflictsNotice { offline, unavailable }

/// The state never overrides `==`: every emission reaches the screen.
final class TaskConflictsState {
  const TaskConflictsState({
    this.loading = true,
    this.conflicts = const [],
    this.servers = const {},
    this.resolving,
    this.redoTaskId,
    this.notice,
  });

  final bool loading;
  final List<TaskConflict> conflicts;

  /// The server version of each conflict, by conflict id.
  final Map<String, ServerVersion> servers;

  /// The conflict whose decision is being applied.
  final String? resolving;

  /// Only once: the task the screen opens after "Redo".
  final String? redoTaskId;
  final TaskConflictsNotice? notice;

  TaskConflictsState withServer(String conflictId, ServerVersion server) =>
      copyWith(servers: {...servers, conflictId: server});

  /// Each copy forgets the decision in progress, the navigation, and the
  /// notice, unless it brings others.
  TaskConflictsState copyWith({
    bool? loading,
    List<TaskConflict>? conflicts,
    Map<String, ServerVersion>? servers,
    String? resolving,
    String? redoTaskId,
    TaskConflictsNotice? notice,
  }) => TaskConflictsState(
    loading: loading ?? this.loading,
    conflicts: conflicts ?? this.conflicts,
    servers: servers ?? this.servers,
    resolving: resolving,
    redoTaskId: redoTaskId,
    notice: notice,
  );
}
