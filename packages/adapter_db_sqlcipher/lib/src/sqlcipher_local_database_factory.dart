import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'sqlcipher_local_database.dart';

/// Opens one encrypted database per module. Each database has its own
/// random 256-bit key, created on first open and kept in secure storage;
/// never a key fixed in the code. A new install runs `createStatements`;
/// an upgrade runs the pending `migrations`, in version order.
///
/// The files live in [directoryName], inside the app's Application
/// Support, never in Documents. The host excludes that folder from backups
/// (chapter 30): on iOS through `AppDelegate.swift`, on Android through the
/// manifest's data extraction rules.
final class SqlcipherLocalDatabaseFactory implements LocalDatabaseFactory {
  SqlcipherLocalDatabaseFactory({FlutterSecureStorage? secureStorage})
    : _secureStorage =
          secureStorage ??
          const FlutterSecureStorage(iOptions: keychainOptions);

  /// Folder inside `getApplicationSupportDirectory()`. It must be the same
  /// name the host excludes from backups, in `AppDelegate.swift` and in
  /// `data_extraction_rules.xml` (chapter 30); changing it in a published
  /// app requires migrating the files.
  static const directoryName = 'local_databases';

  /// Readable after the first unlock since boot, so that background sync
  /// can open the database with the device locked; never goes to backups
  /// or to another device.
  static const keychainOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  );

  final FlutterSecureStorage _secureStorage;
  final Map<String, Future<LocalDatabase>> _opened = {};

  /// Concurrent calls for the same database share the opening. An opening
  /// that failed is forgotten, so the next one tries again.
  @override
  Future<LocalDatabase> open(DatabaseSchema schema) => _opened[schema.name] ??=
      _open(schema).catchError((Object error, StackTrace stackTrace) {
        _opened.remove(schema.name);
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<LocalDatabase> _open(DatabaseSchema schema) async {
    try {
      final directory = Directory(
        '${(await getApplicationSupportDirectory()).path}/$directoryName',
      );
      await directory.create(recursive: true);
      final database = await openDatabase(
        '${directory.path}/${schema.name}',
        password: await _keyFor(schema.name),
        version: schema.version,
        onCreate: (db, _) async {
          for (final statement in schema.createStatements) {
            await db.execute(statement);
          }
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (var version = oldVersion + 1; version <= newVersion; version++) {
            for (final statement in schema.migrations[version] ?? const []) {
              await db.execute(statement);
            }
          }
        },
      );
      return SqlcipherLocalDatabase(database);
    } on DatabaseException catch (exception) {
      throw LocalDatabaseError(exception.toString());
    } on FileSystemException catch (exception) {
      throw LocalDatabaseError(exception.toString());
    }
  }

  Future<String> _keyFor(String databaseName) async {
    final storageKey = 'local_database_key.$databaseName';
    final existing = await _secureStorage.read(key: storageKey);
    if (existing != null) return existing;

    final key = newKey();
    await _secureStorage.write(key: storageKey, value: key);
    return key;
  }

  /// 32 bytes from `Random.secure()`, in base64url.
  @visibleForTesting
  static String newKey() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)));
  }
}
