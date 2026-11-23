import '../../domain/entities/task.dart';
import '../../domain/entities/task_conflict.dart';

/// The tasks' driven port. The device's database answers right away, and
/// the backend refreshes it in the background (chapter 31).
abstract interface class TaskRepository {
  /// The non-archived tasks, newest first. Emits the current list and,
  /// again, after every change, including those coming from the backend.
  /// With no stored list, the first one comes from the network, and a
  /// failure there arrives as an error of the `Stream`.
  Stream<List<Task>> watchActiveTasks();

  /// Fetches the list from the backend now. A failure reaches the caller.
  Future<void> refreshActiveTasks();

  /// `null` when the task does not exist on this device.
  Future<Task?> findTask(String taskId);

  /// Writes a new task or the new version of an existing one.
  Future<void> saveTask(Task task);

  Future<void> archiveTask(String taskId);

  /// Whether the list shows done tasks. It is the user's preference, stored
  /// with their tasks, not the device's.
  Future<bool> showCompletedTasks();
  Future<void> saveShowCompletedTasks(bool show);

  /// The changes the server did not accept, oldest first, again on every
  /// change (chapter 34).
  Stream<List<TaskConflict>> watchConflicts();

  /// The task's version on the server now, or `null` when it no longer
  /// exists there. Goes to the network: a failure arrives as `ApiError`.
  Future<Task?> fetchServerTask(String taskId);

  /// Applies the user's decision and takes the conflict off hold. `keepMine`,
  /// `keepServer`, and `redo` go to the server for the current state;
  /// `discard` works without a network.
  Future<void> resolveConflict(
    TaskConflict conflict,
    TaskConflictChoice choice,
  );
}
