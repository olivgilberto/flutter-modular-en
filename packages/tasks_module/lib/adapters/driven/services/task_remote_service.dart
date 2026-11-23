import '../models/task_model.dart';

/// What the repository asks of the backend. A network failure, a refusal,
/// or a malformed response arrives as `ApiError`.
abstract interface class TaskRemoteService {
  /// All non-archived tasks, already validated, read page by page. It only
  /// finishes with the whole list: a page that fails brings the fetch down,
  /// and nothing partial reaches the database.
  Future<List<TaskModel>> fetchActiveTasks();

  /// A task as it is on the server now, already validated, or `null` when
  /// it no longer exists there (chapter 34).
  Future<TaskModel?> fetchTask(String taskId);
}
