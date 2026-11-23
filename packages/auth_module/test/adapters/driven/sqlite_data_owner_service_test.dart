import 'package:auth_module/adapters/driven/services/auth_database_schema.dart';
import 'package:auth_module/adapters/driven/services/sqlite_data_owner_service.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/ffi_local_database.dart';

void main() {
  late FfiLocalDatabaseFactory databases;
  late SqliteDataOwnerService service;

  setUp(() {
    databases = FfiLocalDatabaseFactory();
    service = SqliteDataOwnerService(databaseFactory: databases);
  });
  tearDown(() => databases.close());

  test('with nobody\'s data, there is no owner', () async {
    expect(await service.currentOwner(), isNull);
  });

  test('writes, replaces, and deletes the single owner', () async {
    await service.saveOwner('u-1');
    await service.saveOwner('u-2');
    expect(await service.currentOwner(), 'u-2');

    await service.clearOwner();
    expect(await service.currentOwner(), isNull);
  });

  test('only the id is stored, next to the session', () async {
    await service.saveOwner('u-1');

    final db = await databases.rawDatabase(authDatabaseSchema);
    expect(await db.rawQuery('SELECT * FROM data_owner'), [
      {'id': 1, 'user_id': 'u-1'},
    ]);
  });

  test('a malformed owner is a technical database failure', () async {
    final db = await databases.open(authDatabaseSchema);
    await db.execute("INSERT INTO data_owner VALUES (1, '')");

    await expectLater(
      service.currentOwner(),
      throwsA(isA<LocalDatabaseError>()),
    );
  });
}
