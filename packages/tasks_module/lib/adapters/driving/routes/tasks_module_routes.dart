import 'package:go_router/go_router.dart';

import '../pages/task_conflicts_page.dart';
import '../pages/task_edit_page.dart';
import '../pages/task_list_page.dart';

/// The module's route names and paths, in the format `[module].[screen]` and
/// `/[module]/[screen]`, like auth_module's (chapter 22). They are part of
/// the module's public contract (docs/modules/tasks_module.md).
abstract final class TaskRoutes {
  static const prefix = '/tasks';
  static const list = 'tasks.list';
  static const listPath = prefix;
  static const edit = 'tasks.edit';
  static const editPath = '$prefix/edit/:taskId';
  static const conflicts = 'tasks.conflicts';
  static const conflictsPath = '$prefix/conflicts';
}

/// The list the host spreads into the `GoRouter`. The module never registers
/// routes in a global router, and the list cannot be changed by whoever receives it.
final List<RouteBase> tasksModuleRoutes = List.unmodifiable([
  GoRoute(
    name: TaskRoutes.list,
    path: TaskRoutes.listPath,
    builder: (context, state) => const TaskListPage(),
  ),
  GoRoute(
    name: TaskRoutes.edit,
    path: TaskRoutes.editPath,
    builder: (context, state) =>
        TaskEditPage(taskId: state.pathParameters['taskId']!),
  ),
  GoRoute(
    name: TaskRoutes.conflicts,
    path: TaskRoutes.conflictsPath,
    builder: (context, state) => const TaskConflictsPage(),
  ),
]);
