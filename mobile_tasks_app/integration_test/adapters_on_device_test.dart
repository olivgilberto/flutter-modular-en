import 'dart:convert';
import 'dart:io';

import 'package:adapter_db_sqlcipher/adapter_db_sqlcipher.dart';
import 'package:adapter_prefs_shared_preferences/adapter_prefs_shared_preferences.dart';
import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

/// The adapters against the real technology (chapter 39). The chapter 18
/// tests run on the computer, with FFI's unencrypted SQLite and mocked
/// plugins; what only the device has lives here: SQLCipher encrypting the
/// file, the key stored in the Keychain or the Keystore, and the preferences
/// written by the plugin. The host only uses sqflite_sqlcipher,
/// flutter_secure_storage, and path_provider here, as dev dependencies: in
/// the app, they only come in through the
/// adapter.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const schema = DatabaseSchema(
    name: 'integration.db',
    version: 1,
    createStatements: [
      'CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT NOT NULL)',
    ],
  );
  const storage = FlutterSecureStorage(
    iOptions: SqlcipherLocalDatabaseFactory.keychainOptions,
  );

  Future<File> databaseFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/'
    '${SqlcipherLocalDatabaseFactory.directoryName}/${schema.name}',
  );

  // Each run starts without the database and without the key, and leaves
  // neither behind.
  Future<void> clean() async {
    final file = await databaseFile();
    final keyName = 'local_database_key.${schema.name}';
    final key = await storage.read(key: keyName);
    // A connection a test left open closes before the file goes away.
    if (key != null && await file.exists()) {
      await (await sqlcipher.openDatabase(file.path, password: key)).close();
    }
    for (final path in [
      file.path,
      '${file.path}-wal',
      '${file.path}-journal',
    ]) {
      final part = File(path);
      if (await part.exists()) await part.delete();
    }
    await storage.delete(key: keyName);
  }

  setUp(clean);
  tearDown(clean);

  testWidgets('the database file is encrypted: neither the SQLite header nor '
      'the stored text appears in it', (tester) async {
    final database = await SqlcipherLocalDatabaseFactory().open(schema);
    await database.execute(
      'INSERT INTO notes (body) VALUES (?)',
      args: ['plain-text-marker'],
    );

    final file = await databaseFile();
    final bytes = await file.readAsBytes();
    // Every unencrypted SQLite database starts with "SQLite format 3".
    expect(latin1.decode(bytes.take(15).toList()), isNot('SQLite format 3'));
    // The text is not in the file, nor in the journal next to it, if any.
    for (final path in [
      file.path,
      '${file.path}-wal',
      '${file.path}-journal',
    ]) {
      final part = File(path);
      if (!await part.exists()) continue;
      expect(
        latin1.decode(await part.readAsBytes()),
        isNot(contains('plain-text-marker')),
        reason: path,
      );
    }
  });

  testWidgets(
    'the key stays in secure storage: with the database closed, another '
    'factory, as on a new app start, opens it again',
    (tester) async {
      final first = await SqlcipherLocalDatabaseFactory().open(schema);
      await first.execute(
        'INSERT INTO notes (body) VALUES (?)',
        args: ['stored'],
      );
      final key = await storage.read(key: 'local_database_key.${schema.name}');
      // 32 bytes in base64url: 44 characters.
      expect(key, hasLength(44));

      // sqflite returns the same connection to whoever opens the same file; for
      // the second factory to really open it, the first connection closes.
      final path = (await databaseFile()).path;
      await (await sqlcipher.openDatabase(path, password: key)).close();

      final again = await SqlcipherLocalDatabaseFactory().open(schema);
      expect(await again.query('SELECT body FROM notes'), [
        {'body': 'stored'},
      ]);
      await (await sqlcipher.openDatabase(path, password: key)).close();
    },
  );

  testWidgets('without the right key, the file does not open', (tester) async {
    final database = await SqlcipherLocalDatabaseFactory().open(schema);
    await database.execute(
      'INSERT INTO notes (body) VALUES (?)',
      args: ['stored'],
    );
    final path = (await databaseFile()).path;
    final key = await storage.read(key: 'local_database_key.${schema.name}');
    await (await sqlcipher.openDatabase(path, password: key)).close();

    await expectLater(() async {
      final wrong = await sqlcipher.openDatabase(
        path,
        password: 'another-key',
        singleInstance: false,
      );
      try {
        await wrong.rawQuery('SELECT count(*) FROM notes');
      } finally {
        await wrong.close();
      }
    }(), throwsA(isA<sqlcipher.DatabaseException>()));
  });

  testWidgets('the preferences written by the plugin survive another '
      'instance of the adapter', (tester) async {
    await SharedPreferencesAppPreferences().saveLanguageCode('pt-BR');
    await SharedPreferencesAppPreferences().saveThemeMode(AppThemeMode.dark);

    final read = SharedPreferencesAppPreferences();
    expect(await read.languageCode(), 'pt-BR');
    expect(await read.themeMode(), AppThemeMode.dark);
  });
}
