import 'app_logger.dart';
import 'local_database.dart';
import 'outbox.dart';

/// Runs every queue signed up to the [OutboxRegistry], each one isolated
/// from the others. Knows nothing about tasks, endpoints, or tables.
final class OutboxSyncWorker {
  OutboxSyncWorker({
    required OutboxRegistry registry,
    required AppLogger logger,
  }) : _registry = registry,
       _logger = logger;

  final OutboxRegistry _registry;
  final AppLogger _logger;

  /// True when some queue left something for the next round.
  ///
  /// A [LocalDatabaseError] in one queue is logged and counts as "try
  /// again", without stopping the others. Each queue already handles
  /// `ApiError`s in its own send. A bug is still an `Error`: `Future.wait`
  /// waits for the other queues to finish and only then rethrows it.
  Future<bool> run() async {
    final retries = await Future.wait([
      for (final outbox in _registry.outboxes.toList()) _runOne(outbox),
    ]);
    return retries.contains(true);
  }

  Future<bool> _runOne(SyncableOutbox outbox) async {
    try {
      return await outbox.sync();
    } on LocalDatabaseError catch (error, stackTrace) {
      _logger.error('outbox ${outbox.name}', error, stackTrace);
      return true;
    }
  }
}
