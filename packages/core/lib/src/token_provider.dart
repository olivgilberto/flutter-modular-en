/// Implemented by the authentication module; used by the HTTP adapter
/// without either one knowing the other (chapter 11).
abstract interface class TokenProvider {
  /// The current session's token, or `null` if there is no session.
  Future<String?> currentToken();

  /// Called when the server rejected the current token. Returns a new
  /// token, or `null` when the session cannot be refreshed; in that case,
  /// the implementation reports that the session expired.
  ///
  /// Concurrent calls share the same refresh.
  Future<String?> refreshToken();
}
