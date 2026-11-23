/// A module's outbox (chapter 12). Implemented on the module's driven side
/// and signed up to the [OutboxRegistry] by the module's own registration
/// function.
abstract interface class SyncableOutbox {
  /// Name of the queue in logs (for example, 'tasks'). Never `runtimeType`,
  /// which is obfuscated in production builds.
  String get name;

  /// Operations not yet accepted by the server: those in the queue and
  /// those waiting for a user decision in sync_conflicts.
  Future<int> pendingCount();

  /// Sends the pending operations, in the order they were written.
  /// Returns true when something was left for a retry.
  /// Concurrent calls share the same send.
  Future<bool> sync();
}

abstract interface class OutboxRegistry {
  void register(SyncableOutbox outbox);
  Iterable<SyncableOutbox> get outboxes;

  /// Sums the pending operations of all queues, checked before
  /// logout.
  Future<int> pendingOperations();

  /// Forgets the queues of the session that ended.
  void unregisterAll();
}

final class DefaultOutboxRegistry implements OutboxRegistry {
  final List<SyncableOutbox> _outboxes = [];

  @override
  void register(SyncableOutbox outbox) => _outboxes.add(outbox);

  @override
  Iterable<SyncableOutbox> get outboxes => List.unmodifiable(_outboxes);

  @override
  Future<int> pendingOperations() async {
    final counts = await Future.wait([
      for (final outbox in List.of(_outboxes)) outbox.pendingCount(),
    ]);
    return counts.fold<int>(0, (sum, count) => sum + count);
  }

  @override
  void unregisterAll() => _outboxes.clear();
}
