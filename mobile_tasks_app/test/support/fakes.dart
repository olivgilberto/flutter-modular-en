import 'dart:async';

import 'package:core/core.dart';

/// Keeps what the host logs, for the tests to check.
final class FakeLogger implements AppLogger {
  final logs = <String>[];
  final errors = <String>[];
  final fatals = <Object>[];

  @override
  void log(String message) => logs.add(message);

  @override
  void error(String reason, Object error, StackTrace stackTrace) =>
      errors.add(reason);

  @override
  void fatal(Object error, StackTrace stackTrace) => fatals.add(error);

  @override
  void setUserId(String? opaqueId) {}
}

/// In-memory preferences, with the port's change streams. A read can get
/// stuck forever ([hang]), like a frozen plugin.
final class FakePreferences implements AppPreferences {
  FakePreferences({
    this.storedThemeMode = AppThemeMode.system,
    this.storedLanguage,
    this.hang = false,
  });

  AppThemeMode storedThemeMode;
  String? storedLanguage;
  final bool hang;
  final _themeModeChanges = StreamController<AppThemeMode>.broadcast();
  final _languageCodeChanges = StreamController<String>.broadcast();

  Future<T> _read<T>(T value) =>
      hang ? Completer<T>().future : Future.value(value);

  @override
  Future<AppThemeMode> themeMode() => _read(storedThemeMode);

  @override
  Future<void> saveThemeMode(AppThemeMode mode) async {
    storedThemeMode = mode;
    _themeModeChanges.add(mode);
  }

  @override
  Stream<AppThemeMode> get themeModeChanges => _themeModeChanges.stream;

  @override
  Future<String?> languageCode() => _read(storedLanguage);

  @override
  Future<void> saveLanguageCode(String languageCode) async {
    storedLanguage = languageCode;
    _languageCodeChanges.add(languageCode);
  }

  @override
  Stream<String> get languageCodeChanges => _languageCodeChanges.stream;
}

final class FakeAnalytics implements AppAnalytics {
  /// The logged screens, in order (chapter 38).
  final screens = <String>[];

  @override
  Future<void> logEvent(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {}

  @override
  Future<void> logScreenView(String screenName) async =>
      screens.add(screenName);
}

/// Ports the test requires to build the module, but that no test uses:
/// any call is the test's own error.
final class UnusedApiClient implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class UnusedDatabaseFactory implements LocalDatabaseFactory {
  @override
  Future<LocalDatabase> open(DatabaseSchema schema) =>
      throw UnimplementedError('open');
}

/// The connection state controlled by the test.
final class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService([this._status = ConnectivityStatus.unknown]);

  ConnectivityStatus _status;
  final _changes = StreamController<ConnectivityStatus>.broadcast();

  void emit(ConnectivityStatus status) {
    _status = status;
    _changes.add(status);
  }

  @override
  ConnectivityStatus get status => _status;

  @override
  Stream<ConnectivityStatus> get statusChanges => _changes.stream;

  @override
  Future<void> start() async {}

  @override
  Future<ConnectivityStatus> check() async => _status;

  @override
  Future<void> dispose() => _changes.close();
}

/// A database that does not open, as on a device with secure storage
/// unavailable: the technical failure the screens know how to show.
final class FailingDatabaseFactory implements LocalDatabaseFactory {
  @override
  Future<LocalDatabase> open(DatabaseSchema schema) async =>
      throw const LocalDatabaseError('database unavailable in the test');
}
