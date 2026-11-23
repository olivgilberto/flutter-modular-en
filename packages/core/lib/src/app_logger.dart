/// Crash and error reporting (chapter 14).
abstract interface class AppLogger {
  /// A step that helps understand a future failure (breadcrumb).
  /// Never personal data, tokens, headers, or bodies.
  void log(String message);

  /// A handled error that did not bring the app down. [reason] says where
  /// it happened and carries no unique values (ids, dates).
  void error(String reason, Object error, StackTrace stackTrace);

  /// An error nobody handled: the app may be in an inconsistent state.
  void fatal(Object error, StackTrace stackTrace);

  /// An opaque identifier of the account, or `null` on logout.
  void setUserId(String? opaqueId);
}
