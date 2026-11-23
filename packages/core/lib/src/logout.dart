/// Implemented by every module that keeps local session data.
abstract interface class ClearableOnLogout {
  Future<void> clearLocalData();
}

abstract interface class LogoutCleanerRegistry {
  void register(ClearableOnLogout cleaner);

  /// Runs all registered cleaners. A cleaner that fails does not stop
  /// the others; after all of them finish, the first failure is
  /// rethrown.
  Future<void> clearAll();

  /// Forgets the cleaners of the session that ended.
  void unregisterAll();
}

final class DefaultLogoutCleanerRegistry implements LogoutCleanerRegistry {
  final List<ClearableOnLogout> _cleaners = [];

  @override
  void register(ClearableOnLogout cleaner) => _cleaners.add(cleaner);

  /// `Future.wait`, not the lists' `.wait`: `.wait` gathers the failures
  /// into a `ParallelWaitError`, which is an `Error` and would be treated as a bug.
  @override
  Future<void> clearAll() async {
    await Future.wait([
      for (final cleaner in List.of(_cleaners)) cleaner.clearLocalData(),
    ]);
  }

  @override
  void unregisterAll() => _cleaners.clear();
}
