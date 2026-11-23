import 'task_operation.dart';

/// The outbox, from the sender's point of view. Internal to the module:
/// only `TaskSyncableOutbox` uses it, and `SqliteTaskService` implements it
/// in the same database as the tasks.
abstract interface class TaskOutboxQueue {
  /// The operations in the order they were written.
  Future<List<TaskOperation>> pendingInOrder();

  Future<int> pendingCount();

  /// The server accepted the operation and answered with the task's new
  /// version. In a transaction: the operation leaves the queue, the task
  /// stores the version, and the same task's later operations, made on the
  /// result of this one, take that version as their base. An operation that
  /// has already left, because the other isolate sent it, changes nothing.
  Future<void> complete(TaskOperation operation, {required int newVersion});

  /// Takes the operation out of the queue without touching the task: what
  /// it wanted had already happened.
  Future<void> remove(String operationId);
}
