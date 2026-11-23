import 'package:adapter_db_sqlcipher/adapter_db_sqlcipher.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SqlcipherLocalDatabase only uses sqflite's common API, so it runs on
/// the computer over an in-memory sqflite_common_ffi database. The
/// encryption itself only exists on the device.
void main() {
  late Database raw;
  late LocalDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    database = SqlcipherLocalDatabase(raw);
    await database.execute(
      'CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL)',
    );
  });

  tearDown(() => raw.close());

  test('writes and reads', () async {
    await database.execute(
      'INSERT INTO tasks (id, title) VALUES (?, ?)',
      args: ['1', 'Buy bread'],
    );

    expect(await database.query('SELECT title FROM tasks'), [
      {'title': 'Buy bread'},
    ]);
  });

  test('a failure inside the transaction undoes everything', () async {
    await expectLater(
      database.transaction((txn) async {
        await txn.execute("INSERT INTO tasks VALUES ('1', 'a')");
        throw StateError('fails midway');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('SELECT * FROM tasks'), isEmpty);
  });

  test('a nested transaction joins the outer one', () async {
    await expectLater(
      database.transaction((outer) async {
        await outer.execute("INSERT INTO tasks VALUES ('1', 'a')");
        await outer.transaction(
          (inner) => inner.execute("INSERT INTO tasks VALUES ('2', 'b')"),
        );
        throw StateError('undoes both');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await database.query('SELECT * FROM tasks'), isEmpty);
  });

  test('a driver error becomes LocalDatabaseError', () async {
    await expectLater(
      database.execute("INSERT INTO tasks VALUES ('1', NULL)"),
      throwsA(isA<LocalDatabaseError>()),
    );
    await expectLater(
      database.query('SELECT * FROM does_not_exist'),
      throwsA(isA<LocalDatabaseError>()),
    );
  });
}
