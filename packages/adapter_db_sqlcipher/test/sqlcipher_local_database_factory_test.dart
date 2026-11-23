import 'package:adapter_db_sqlcipher/adapter_db_sqlcipher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Both constants match the host (AppDelegate.swift); changing them without
/// changing the host would let databases or keys go into backups.
void main() {
  test('the databases live in local_databases', () {
    expect(SqlcipherLocalDatabaseFactory.directoryName, 'local_databases');
  });

  test('the key exists only on this device', () {
    expect(
      SqlcipherLocalDatabaseFactory.keychainOptions.toMap()['accessibility'],
      'first_unlock_this_device',
    );
  });

  test('each new key has 256 bits and never repeats', () {
    final first = SqlcipherLocalDatabaseFactory.newKey();
    final second = SqlcipherLocalDatabaseFactory.newKey();

    expect(first, hasLength(44)); // 32 bytes in base64url
    expect(first, isNot(second));
  });
}
