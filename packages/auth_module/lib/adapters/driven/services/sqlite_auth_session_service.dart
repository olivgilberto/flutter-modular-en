import 'package:core/core.dart';

import '../models/auth_model.dart';
import 'auth_database_schema.dart';
import 'auth_session_local_service.dart';

/// The session in the module's encrypted database, opened through the
/// `LocalDatabaseFactory` port: the database key lives in the device's
/// Keychain, and the file stays out of backups (chapter 18). No new
/// technology comes into the module to store the tokens.
final class SqliteAuthSessionService implements AuthSessionLocalService {
  SqliteAuthSessionService({required LocalDatabaseFactory databaseFactory})
    : _databaseFactory = databaseFactory;

  /// The module's database, with the data owner next to the session.
  static const schema = authDatabaseSchema;

  final LocalDatabaseFactory _databaseFactory;

  /// Opened on first use, never when the module registers. The factory keeps
  /// the open database and forgets an opening that failed (chapter 18).
  Future<LocalDatabase> get _database => _databaseFactory.open(schema);

  @override
  Future<AuthModel?> read() async {
    final rows = await (await _database).query(
      'SELECT user_id, name, email, access_token, refresh_token '
      'FROM session WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    try {
      return AuthModel.fromMap(rows.single);
    } on FormatException catch (error) {
      throw LocalDatabaseError('invalid stored session: ${error.message}');
    }
  }

  @override
  Future<void> write(AuthModel session) async {
    final row = session.toMap();
    await (await _database).execute(
      'INSERT OR REPLACE INTO session '
      '(id, user_id, name, email, access_token, refresh_token) '
      'VALUES (1, ?, ?, ?, ?, ?)',
      args: [
        row['user_id'],
        row['name'],
        row['email'],
        row['access_token'],
        row['refresh_token'],
      ],
    );
  }

  @override
  Future<void> delete() async {
    await (await _database).execute('DELETE FROM session');
  }
}
