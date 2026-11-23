import 'dart:async';

import 'package:core/core.dart';

import '../../domain/entities/task.dart';
import '../../domain/entities/task_conflict.dart';
import '../../domain/task_failure.dart';
import '../../domain/value_objects/task_title.dart';
import '../ports/task_repository.dart';

/// The tasks' driving port: one use case for the whole feature.
/// It receives raw text from the screen and only hands valid tasks to the port.
///
/// Every operation that succeeded logs a product event following the pattern
/// `tasks_[object]_[action]` (chapters 14 and 38), without waiting for it: a
/// metrics failure never makes the operation look like a failure. No event
/// carries the task's title or id.
///
/// Not `final`: the Bloc tests will mock it with `implements`.
class TaskUseCase {
  TaskUseCase({
    required TaskRepository repository,
    required String Function() newId,
    required DateTime Function() now,
    required AppAnalytics analytics,
  }) : _repository = repository,
       _newId = newId,
       _now = now,
       _analytics = analytics;

  final TaskRepository _repository;
  final AppAnalytics _analytics;
  final String Function() _newId;
  final DateTime Function() _now;

  Stream<List<Task>> watchActiveTasks() => _repository.watchActiveTasks();

  /// The pull-to-refresh gesture. With no network, the `ApiError` reaches the
  /// screen, and the device's list stays where it was.
  Future<void> refreshTasks() => _repository.refreshActiveTasks();

  /// `async` so that a validation failure arrives as an error of the
  /// `Future`, not as a synchronous exception before the future exists.
  Future<Task> createTask({required String title}) async {
    final task = Task(
      id: _newId(),
      title: TaskTitle.parse(title),
      createdAt: _now(),
    );
    await _repository.saveTask(task);
    _event('tasks_task_created');
    return task;
  }

  Future<void> renameTask(String taskId, {required String title}) async {
    final newTitle = TaskTitle.parse(title);
    final task = await _taskInList(taskId);
    await _repository.saveTask(task.rename(newTitle));
    _event('tasks_task_renamed');
  }

  Future<void> completeTask(String taskId) async {
    final task = await _taskInList(taskId);
    await _repository.saveTask(task.complete());
    _event('tasks_task_completed');
  }

  Future<void> reopenTask(String taskId) async {
    final task = await _taskInList(taskId);
    await _repository.saveTask(task.reopen());
    _event('tasks_task_reopened');
  }

  Future<void> archiveTask(String taskId) async {
    await _taskInList(taskId);
    await _repository.archiveTask(taskId);
    _event('tasks_task_archived');
  }

  /// The task as it is on the device, for the edit screen; `null` when it
  /// has already left the list.
  Future<Task?> findTask(String taskId) async {
    final task = await _repository.findTask(taskId);
    return task == null || task.isArchived ? null : task;
  }

  Future<bool> showCompletedTasks() => _repository.showCompletedTasks();

  Future<void> setShowCompletedTasks(bool show) =>
      _repository.saveShowCompletedTasks(show);

  /// The changes waiting for the user's decision (chapter 34).
  Stream<List<TaskConflict>> watchConflicts() => _repository.watchConflicts();

  /// The server version, for the user to compare with theirs.
  Future<Task?> serverVersion(TaskConflict conflict) =>
      _repository.fetchServerTask(conflict.task.id);

  /// A decision that makes no sense for the conflict's reason is the
  /// caller's defect, not the user's.
  Future<void> resolveConflict(
    TaskConflict conflict,
    TaskConflictChoice choice,
  ) async {
    if (!conflict.choices.contains(choice)) {
      throw ArgumentError.value(choice, 'choice', 'does not fit this conflict');
    }
    await _repository.resolveConflict(conflict, choice);
    _event('tasks_conflict_resolved', {
      'reason': conflict.reason.name,
      'choice': choice.name,
    });
  }

  void _event(String name, [Map<String, Object> parameters = const {}]) =>
      unawaited(_analytics.logEvent(name, parameters));

  /// An archived task has already left the list: for whoever sees it, it does not exist.
  Future<Task> _taskInList(String taskId) async {
    final task = await _repository.findTask(taskId);
    if (task == null || task.isArchived) throw const TaskNotFoundFailure();
    return task;
  }
}
