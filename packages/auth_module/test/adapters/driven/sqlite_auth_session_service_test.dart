import 'package:auth_module/adapters/driven/services/sqlite_auth_session_service.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ffi_local_database.dart';
import 'driven_fakes.dart';

void main() {
  late FfiLocalDatabaseFactory databases;
  late SqliteAuthSessionService service;

  setUp(() {
    databases = FfiLocalDatabaseFactory();
    service = SqliteAuthSessionService(databaseFactory: databases);
  });

  test('with no stored session, reads null', () async {
    expect(await service.read(), isNull);
  });

  test('writes, reads, and replaces the single row', () async {
    await service.write(ana);
    await service.write(
      ana.withTokens(accessToken: 'at-2', refreshToken: 'rt-2'),
    );

    final stored = await service.read();
    expect(stored?.accessToken, 'at-2');
    expect(stored?.userId, 'u-1');
  });

  test('deleting removes the session', () async {
    await service.write(ana);
    await service.delete();

    expect(await service.read(), isNull);
  });

  test('a malformed row is a technical database failure', () async {
    // A BLOB in a TEXT column: SQLite accepts it, and fromMap rejects it.
    final database = await databases.open(SqliteAuthSessionService.schema);
    await database.execute(
      "INSERT INTO session VALUES (1, 'u-1', 'Ana', X'00', 'at-1', 'rt-1')",
    );

    await expectLater(service.read(), throwsA(isA<LocalDatabaseError>()));
  });
}
