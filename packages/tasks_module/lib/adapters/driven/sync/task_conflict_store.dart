import 'task_operation.dart';

/// Why the server refused an operation.
enum TaskConflictKind {
  /// Version 409: someone changed the task first.
  conflict,

  /// Any other 4xx refusal: the operation will never go through as it is.
  rejected,
}

/// The refusals stored in `sync_conflicts`, waiting for the user
/// (chapter 34). Internal to the module, like the queue.
abstract interface class TaskConflictStore {
  /// The tasks with an open refusal: their later operations wait in the
  /// queue.
  Future<Set<String>> entitiesWithOpenConflict();

  Future<int> openConflictCount();

  /// In a transaction: the operation leaves the queue and becomes a
  /// refusal. A second copy of the same operation is ignored.
  Future<void> moveFromQueue(
    TaskOperation operation, {
    required TaskConflictKind kind,
    required int statusCode,
  });
}
