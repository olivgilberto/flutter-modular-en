/// A module's local database. Every method throws [LocalDatabaseError] on
/// failure; no driver exception crosses this boundary.
abstract interface class LocalDatabase {
  Future<List<Map<String, Object?>>> query(String sql, {List<Object?>? args});
  Future<void> execute(String sql, {List<Object?>? args});

  /// Runs [action] in a transaction. Inside a transaction, a nested call
  /// joins the same transaction instead of opening another one.
  Future<T> transaction<T>(Future<T> Function(LocalDatabase txn) action);
}

/// Opens each module's database. One database per module, never shared.
abstract interface class LocalDatabaseFactory {
  Future<LocalDatabase> open(DatabaseSchema schema);
}

/// What a module declares about its database: name, version, the complete
/// schema for new installs, and the migrations for upgrades.
final class DatabaseSchema {
  const DatabaseSchema({
    required this.name,
    required this.version,
    required this.createStatements,
    this.migrations = const {},
  });

  /// File name, unique in the app (for example, 'tasks.db').
  final String name;
  final int version;

  /// The schema of the current version, for whoever installs the app now.
  final List<String> createStatements;

  /// For each version, the statements that lead from the previous one to it.
  final Map<int, List<String>> migrations;
}

final class LocalDatabaseError implements Exception {
  const LocalDatabaseError(this.message);

  final String message;

  @override
  String toString() => 'LocalDatabaseError($message)';
}
