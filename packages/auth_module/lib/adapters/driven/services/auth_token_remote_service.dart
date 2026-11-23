/// The remote source for token refresh.
abstract interface class AuthTokenRemoteService {
  /// Trades the refresh token for a new pair. Throws an `ApiError` of type
  /// `rejected` when the backend no longer accepts the session.
  Future<({String accessToken, String refreshToken})> renew(
    String refreshToken,
  );
}
