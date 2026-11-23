import 'dart:async';

import 'package:core/core.dart';

import '../../application/ports/task_repository.dart';
import '../../domain/entities/task.dart';
import '../../domain/entities/task_conflict.dart';
import 'services/task_local_service.dart';
import 'services/task_remote_service.dart';

/// The tasks repository: the device's database is the screen's source, and
/// the backend refreshes it (stale-while-revalidate, chapter 12). The
/// device's list appears right away; the network's arrives through the
/// same `Stream` when the refresh finishes. Every write is stored with its
/// operation in the queue and, right after, the queue tries to go out, without the writer waiting.
final class TaskRepositoryImpl implements TaskRepository {
  TaskRepositoryImpl({
    required TaskRemoteService remote,
    required TaskLocalService local,
    required SyncableOutbox outbox,
    required AppLogger logger,
    required DateTime Function() now,
    this.activeTasksTtl = defaultActiveTasksTtl,
  }) : _remote = remote,
       _local = local,
       _outbox = outbox,
       _logger = logger,
       _now = now;

  /// How long the device's list is valid without going to the network. The
  /// list changes at the user's own hands, and they already see it updated;
  /// what the TTL covers is a change made on another device.
  static const defaultActiveTasksTtl = Duration(minutes: 5);

  final TaskRemoteService _remote;
  final TaskLocalService _local;

  /// The `core` port, the same instance the registration function signs up
  /// to the `OutboxRegistry`.
  final SyncableOutbox _outbox;
  final AppLogger _logger;
  final DateTime Function() _now;
  final Duration activeTasksTtl;
  Future<void>? _refreshing;

  @override
  Stream<List<Task>> watchActiveTasks() async* {
    final refreshedAt = await _local.lastRefreshedAt();
    if (refreshedAt == null) {
      // First load: with no cache, there is nothing to show. An ApiError here
      // reaches the Bloc, which shows the error with the option to retry.
      await refreshActiveTasks();
    } else if (_isStale(refreshedAt)) {
      unawaited(_refreshInBackground());
    }
    yield* _local.watchActiveTasks();
  }

  /// Goes to the network now, inside or outside the deadline, as with the
  /// pull-to-refresh gesture. Whoever asks while a refresh is in progress
  /// gets the same one.
  @override
  Future<void> refreshActiveTasks() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final fresh = await _remote.fetchActiveTasks();
    await _local.saveActiveTasks(fresh, refreshedAt: _now());
  }

  /// The cache stays valid. The HTTP failure has already been logged by the
  /// logging interceptor (chapter 27); the database one has not, and goes to
  /// the crash log here, because nobody is awaiting this `Future`.
  Future<void> _refreshInBackground() async {
    try {
      await refreshActiveTasks();
    } on ApiError {
      // Nothing to do: the next opening tries again.
    } on LocalDatabaseError catch (error, stackTrace) {
      _logger.error('tasks refresh', error, stackTrace);
    }
  }

  /// A clock that went back in time also counts as expired: a time stored
  /// in the future would never expire on its own.
  bool _isStale(DateTime refreshedAt) {
    final age = _now().difference(refreshedAt);
    return age.isNegative || age >= activeTasksTtl;
  }

  @override
  Future<Task?> findTask(String taskId) => _local.findTask(taskId);

  /// The `Future` completes when the change is stored on the device; the
  /// send happens behind the scenes.
  @override
  Future<void> saveTask(Task task) async {
    await _local.saveTask(task);
    _sendSoon();
  }

  @override
  Future<void> archiveTask(String taskId) async {
    await _local.archiveTask(taskId);
    _sendSoon();
  }

  @override
  Stream<List<TaskConflict>> watchConflicts() => _local.watchConflicts();

  @override
  Future<Task?> fetchServerTask(String taskId) async =>
      (await _remote.fetchTask(taskId))?.toEntity();

  /// The decisions that need the server ask it now, not when the screen
  /// opened: in between, the task may have changed again
  /// (chapter 34).
  @override
  Future<void> resolveConflict(
    TaskConflict conflict,
    TaskConflictChoice choice,
  ) async {
    final taskId = conflict.task.id;
    switch (choice) {
      case TaskConflictChoice.keepMine:
        final server = await _remote.fetchTask(taskId);
        await _local.keepLocalVersion(
          conflict.id,
          taskId: taskId,
          serverVersion: server?.version,
        );
        _sendSoon();
      case TaskConflictChoice.keepServer || TaskConflictChoice.redo:
        await _local.acceptServerVersion(
          conflict.id,
          taskId: taskId,
          server: await _remote.fetchTask(taskId),
        );
      case TaskConflictChoice.discard:
        await _local.discardConflict(conflict.id, taskId: taskId);
        unawaited(_refreshInBackground());
    }
  }

  /// With a network, it goes out now; without one, the operation waits for
  /// the next trigger (chapter 12). The send has already handled HTTP
  /// failures; the database one goes to the crash log, because nobody awaits this `Future`.
  void _sendSoon() {
    unawaited(
      _outbox.sync().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (error is! LocalDatabaseError) {
            Error.throwWithStackTrace(error, stackTrace);
          }
          _logger.error('tasks outbox', error, stackTrace);
        },
      ),
    );
  }

  @override
  Future<bool> showCompletedTasks() => _local.showCompletedTasks();

  @override
  Future<void> saveShowCompletedTasks(bool show) =>
      _local.saveShowCompletedTasks(show);
}
