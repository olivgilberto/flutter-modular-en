import 'package:core/core.dart';

/// Records only the logged errors, which is what the tests check.
final class FakeLogger implements AppLogger {
  final errors = <String>[];

  @override
  void setUserId(String? opaqueId) {}

  @override
  void log(String message) {}

  @override
  void error(String reason, Object error, StackTrace stackTrace) =>
      errors.add(reason);

  @override
  void fatal(Object error, StackTrace stackTrace) {}
}

/// Records the product events in the order they arrive (chapter 38).
final class FakeAnalytics implements AppAnalytics {
  final events = <(String, Map<String, Object>)>[];
  final screens = <String>[];

  List<String> get names => [for (final (name, _) in events) name];

  @override
  Future<void> logEvent(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async => events.add((name, parameters));

  @override
  Future<void> logScreenView(String screenName) async =>
      screens.add(screenName);
}
