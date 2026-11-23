/// The tasks backend paths, all under one version. No other file in the
/// module writes a path.
abstract final class TaskApiPaths {
  static const version = '/v1';

  /// `GET` with `status=active`, `limit` and, from the second page on,
  /// `cursor`. Answers `{"items": [...], "nextCursor": "..." | null}`.
  static const tasks = '$version/tasks';

  /// A task: `PUT` creates, with the id generated in the app; `PATCH`
  /// changes or archives, with the base version. Both answer with the task
  /// and its new version (chapter 32).
  static String task(String id) => '$tasks/${Uri.encodeComponent(id)}';
}
