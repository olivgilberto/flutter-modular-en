import 'package:core/core.dart';

import 'services/task_local_service.dart';

/// What the module erases at logout: the user's tasks and preferences.
/// Signed up to the `LogoutCleanerRegistry` by the module's registration
/// function; auth_module does not know it exists (chapter 29).
final class TaskClearableOnLogout implements ClearableOnLogout {
  TaskClearableOnLogout(this._local);

  final TaskLocalService _local;

  @override
  Future<void> clearLocalData() => _local.deleteAll();
}
