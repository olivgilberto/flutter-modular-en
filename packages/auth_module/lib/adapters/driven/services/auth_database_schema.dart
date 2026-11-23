import 'package:core/core.dart';

/// The authentication module's database, with the same rules as `tasks.db`
/// (chapter 30): `createStatements` is the complete schema of the current
/// version, every change bumps the version and gets its migration, and a
/// version that has reached any device never changes.
///
/// Versions: 1, the session (chapter 21); 2, the owner of the data stored on
/// the device (chapter 32).
const authDatabaseSchema = DatabaseSchema(
  name: 'auth.db',
  version: 2,
  createStatements: [_createSession, _createDataOwner],
  migrations: {
    2: [_createDataOwner],
  },
);

/// A single row: the current session.
const _createSession = '''
    CREATE TABLE session (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      access_token TEXT NOT NULL,
      refresh_token TEXT NOT NULL
    )
    ''';

/// A single row, and only the id: whose data is on the device. It outlives
/// the session, which goes away on expiry; it goes away with the data.
const _createDataOwner = '''
    CREATE TABLE data_owner (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      user_id TEXT NOT NULL
    )
    ''';
