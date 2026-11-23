import 'package:core/core.dart';

import '../../../application/ports/data_owner_repository.dart';
import 'auth_database_schema.dart';

/// The data owner in the module's encrypted database, next to the session:
/// the same key in secure storage, the same file out of backups
/// (chapter 18). A single source, so the Service implements the port
/// directly (chapter 8).
final class SqliteDataOwnerService implements DataOwnerRepository {
  SqliteDataOwnerService({required LocalDatabaseFactory databaseFactory})
    : _databaseFactory = databaseFactory;

  final LocalDatabaseFactory _databaseFactory;

  Future<LocalDatabase> get _database =>
      _databaseFactory.open(authDatabaseSchema);

  @override
  Future<String?> currentOwner() async {
    final rows = await (await _database).query(
      'SELECT user_id FROM data_owner WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    return switch (rows.single['user_id']) {
      final String userId when userId.isNotEmpty => userId,
      _ => throw const LocalDatabaseError('invalid data owner'),
    };
  }

  @override
  Future<void> saveOwner(String userId) async {
    await (await _database).execute(
      'INSERT INTO data_owner (id, user_id) VALUES (1, ?) '
      'ON CONFLICT (id) DO UPDATE SET user_id = excluded.user_id',
      args: [userId],
    );
  }

  @override
  Future<void> clearOwner() async {
    await (await _database).execute('DELETE FROM data_owner');
  }
}
