import 'package:core/core.dart';
import 'package:workmanager/workmanager.dart';

/// Schedules syncing the queues as a periodic workmanager task, only with
/// a network, so pending operations go out even with the app
/// closed.
///
/// [callbackDispatcher] is the host's background entry point, a top-level
/// function annotated with `@pragma('vm:entry-point')` that calls
/// [runWorkmanagerSyncTask].
final class WorkmanagerSyncScheduler implements SyncScheduler {
  WorkmanagerSyncScheduler({
    required void Function() callbackDispatcher,
    this.frequency = const Duration(hours: 1),
    Workmanager? workmanager,
  }) : _callbackDispatcher = callbackDispatcher,
       _workmanager = workmanager ?? Workmanager();

  /// Also the BGTaskScheduler identifier on iOS: the host's Info.plist and
  /// AppDelegate use the same value.
  static const taskName = 'outbox_sync';

  /// Android enforces a minimum of 15 minutes.
  final Duration frequency;
  final void Function() _callbackDispatcher;
  final Workmanager _workmanager;

  @override
  Future<void> schedulePeriodicSync() async {
    await _workmanager.initialize(_callbackDispatcher);
    await _workmanager.registerPeriodicTask(
      taskName,
      taskName,
      frequency: frequency,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}

/// Called by the host's background entry point. Runs [sync] whenever the
/// system fires the task; returning `false` lets Android reschedule it
/// according to its backoff policy.
void runWorkmanagerSyncTask(Future<bool> Function() sync) {
  Workmanager().executeTask((_, _) => sync());
}
