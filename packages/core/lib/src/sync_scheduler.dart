/// Schedules syncing the queues with the app closed (chapter 12). The
/// implementation lives in an adapter; the background entry point, in the
/// host.
abstract interface class SyncScheduler {
  Future<void> schedulePeriodicSync();
}
