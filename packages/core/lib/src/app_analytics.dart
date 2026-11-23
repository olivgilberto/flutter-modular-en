/// Product events (chapter 14).
abstract interface class AppAnalytics {
  /// A product event: [name] follows `[module]_[object]_[action]`.
  /// Values in [parameters] are String or num, never personal data.
  Future<void> logEvent(String name, [Map<String, Object> parameters]);

  /// The screen the user opened (called by the host, never by a module).
  Future<void> logScreenView(String screenName);
}
