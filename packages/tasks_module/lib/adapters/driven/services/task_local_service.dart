import '../../../domain/entities/task.dart';
import '../../../domain/entities/task_conflict.dart';
import '../models/task_model.dart';

/// What the repository asks of the device's database. A row the domain
/// rejects arrives as `LocalDatabaseError`: the data was written by the app
/// itself, and the user has no way to fix it (chapter 9).
abstract interface class TaskLocalService {
  Stream<List<Task>> watchActiveTasks();
  Future<Task?> findTask(String taskId);

  /// Writes the task and, in the same transaction, the operation the
  /// backend needs to receive (chapter 31).
  Future<void> saveTask(Task task);
  Future<void> archiveTask(String taskId);

  /// Replaces the local copy with the backend's list, except the tasks with
  /// a pending operation in the queue or an open refusal, and stores the
  /// refresh time.
  Future<void> saveActiveTasks(
    List<TaskModel> tasks, {
    required DateTime refreshedAt,
  });

  /// `null` while the list has never come from the backend on this device.
  Future<DateTime?> lastRefreshedAt();

  Future<bool> showCompletedTasks();
  Future<void> saveShowCompletedTasks(bool show);

  /// Erases the tasks, the queue, the refusals, the refresh state, and the
  /// user's preferences: the logout (chapter 29).
  Future<void> deleteAll();

  /// The open refusals with the task as it is on the device, oldest
  /// first (chapter 34).
  Stream<List<TaskConflict>> watchConflicts();

  /// "Keep mine": in a transaction, the conflict and the task's pending
  /// operations go away, and a new operation takes the device's state to
  /// the server, based on the version it has now. With no version on the
  /// server (the task was deleted there), the operation is a creation.
  Future<void> keepLocalVersion(
    String conflictId, {
    required String taskId,
    required int? serverVersion,
  });

  /// "Keep the server's" and "Redo": the conflict and the pending
  /// operations go away, and the task becomes the server's; without it, it
  /// leaves the device.
  Future<void> acceptServerVersion(
    String conflictId, {
    required String taskId,
    required TaskModel? server,
  });

  /// "Discard": the conflict and the pending operations go away, and the
  /// list becomes stale, so the next refresh brings the real state. No network.
  Future<void> discardConflict(String conflictId, {required String taskId});
}
