import 'dart:async';

import 'connectivity.dart';
import 'outbox_sync_worker.dart';

/// Layer 3, with the app open: decides when to sync, on every transition
/// to [ConnectivityStatus.online], with a short delay to absorb
/// flapping. The [OutboxSyncWorker] decides what; the `SyncScheduler` covers
/// the app when it is closed. One run at a time in this isolate.
final class SyncOrchestrator {
  SyncOrchestrator({
    required ConnectivityService connectivityService,
    required OutboxSyncWorker outboxSyncWorker,
    this.debounce = const Duration(seconds: 2),
  }) : _connectivityService = connectivityService,
       _outboxSyncWorker = outboxSyncWorker;

  final ConnectivityService _connectivityService;
  final OutboxSyncWorker _outboxSyncWorker;
  final Duration debounce;

  StreamSubscription<ConnectivityStatus>? _subscription;
  Timer? _debounceTimer;
  Future<bool>? _running;

  /// Called by mainCommon, after the session scope opens, once there is a
  /// module with an outbox (chapter 33).
  void start() {
    _subscription ??= _connectivityService.statusChanges
        .where((status) => status == ConnectivityStatus.online)
        .listen((_) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
        });
    if (_connectivityService.status == ConnectivityStatus.online) {
      unawaited(syncNow());
    }
  }

  /// Joins the run in progress instead of starting another one. Returns
  /// whether something was left for the next round.
  Future<bool> syncNow() =>
      _running ??= _outboxSyncWorker.run().whenComplete(() => _running = null);

  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _subscription?.cancel();
  }
}
