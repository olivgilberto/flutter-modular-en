import 'package:auth_module/application/ports/data_owner_repository.dart';
import 'package:core/core.dart';

/// Records only what the use case tests check.
final class FakeLogger implements AppLogger {
  final userIds = <String?>[];
  final errors = <String>[];

  @override
  void setUserId(String? opaqueId) => userIds.add(opaqueId);

  @override
  void log(String message) {}

  @override
  void error(String reason, Object error, StackTrace stackTrace) =>
      errors.add(reason);

  @override
  void fatal(Object error, StackTrace stackTrace) {}
}

final class FakeAnalytics implements AppAnalytics {
  final events = <String>[];
  final parameters = <String, Map<String, Object>>{};

  @override
  Future<void> logEvent(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    events.add(name);
    this.parameters[name] = parameters;
  }

  @override
  Future<void> logScreenView(String screenName) async {}
}

/// The data owner in memory. [failing] simulates a database that cannot be
/// read or written.
final class FakeDataOwnerRepository implements DataOwnerRepository {
  String? owner;
  bool failing = false;

  void _check() {
    if (failing) throw const LocalDatabaseError('unreadable database');
  }

  @override
  Future<String?> currentOwner() async {
    _check();
    return owner;
  }

  @override
  Future<void> saveOwner(String userId) async {
    _check();
    owner = userId;
  }

  @override
  Future<void> clearOwner() async {
    _check();
    owner = null;
  }
}
