import 'package:core/core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The `LocalDatabaseFactory` port over the computer's SQLite, for tests
/// only: the module never depends on the SQLCipher adapter, not even here.
/// It opens the way the adapter does (chapter 18): a new install runs the
/// complete schema, an upgrade runs the pending migrations, real
/// transactions, and a driver error becomes `LocalDatabaseError`.
///
/// No isolate (chapter 23): in widget tests the clock is simulated, and a
/// response coming from another isolate would never arrive.
final class FfiLocalDatabaseFactory implements LocalDatabaseFactory {
  /// In memory, unless [directory] is given.
  FfiLocalDatabaseFactory({this.directory}) {
    sqfliteFfiInit();
  }

  final String? directory;
  final _opened = <String, Future<Database>>{};

  @override
  Future<LocalDatabase> open(DatabaseSchema schema) async =>
      FfiLocalDatabase(await rawDatabase(schema));

  /// The driver's database, for the tests that inspect the schema.
  Future<Database> rawDatabase(DatabaseSchema schema) =>
      _opened[schema.name] ??= databaseFactoryFfiNoIsolate.openDatabase(
        directory == null ? inMemoryDatabasePath : '$directory/${schema.name}',
        options: OpenDatabaseOptions(
          version: schema.version,
          singleInstance: false,
          onCreate: (db, _) async {
            for (final statement in schema.createStatements) {
              await db.execute(statement);
            }
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            for (var v = oldVersion + 1; v <= newVersion; v++) {
              for (final statement in schema.migrations[v] ?? const []) {
                await db.execute(statement);
              }
            }
          },
        ),
      );

  Future<void> close() async {
    for (final database in _opened.values) {
      await (await database).close();
    }
    _opened.clear();
  }
}

final class FfiLocalDatabase implements LocalDatabase {
  FfiLocalDatabase(this._executor);

  final DatabaseExecutor _executor;

  @override
  Future<List<Map<String, Object?>>> query(String sql, {List<Object?>? args}) =>
      _guard(() => _executor.rawQuery(sql, args));

  @override
  Future<void> execute(String sql, {List<Object?>? args}) =>
      _guard(() => _executor.execute(sql, args));

  @override
  Future<T> transaction<T>(Future<T> Function(LocalDatabase txn) action) {
    final executor = _executor;
    if (executor is! Database) return action(this);
    return _guard(
      () => executor.transaction((txn) => action(FfiLocalDatabase(txn))),
    );
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on DatabaseException catch (exception) {
      throw LocalDatabaseError(exception.toString());
    }
  }
}
