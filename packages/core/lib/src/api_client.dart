/// The HTTP port. Returns the response body already decoded and throws
/// [ApiError] on any failure; no HTTP library type crosses this
/// boundary.
abstract interface class ApiClient {
  Future<Object?> get(String path, {Map<String, String>? query});

  /// [idempotencyKey] goes in the Idempotency-Key header and is kept on
  /// retries. It is only transport: the "exactly once" guarantee comes from
  /// the design of the operations (chapter 12).
  ///
  /// [authenticated] false sends the request without the token and without
  /// the refresh on a 401: that is the case of the refresh itself (chapter 27).
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  });
  Future<Object?> put(String path, {Object? body, String? idempotencyKey});
  Future<Object?> patch(String path, {Object? body, String? idempotencyKey});
  Future<Object?> delete(String path, {String? idempotencyKey});
}

enum ApiErrorKind {
  /// The request did not arrive or the response did not come back: no
  /// network, timeout, rejected certificate.
  unreachable,

  /// The server answered 5xx.
  server,

  /// The server rejected the request with a 4xx.
  rejected,

  /// The response arrived, but not in the expected format. Never carries the body.
  invalidResponse,
}

final class ApiError implements Exception {
  const ApiError(this.kind, {this.statusCode, this.body});

  final ApiErrorKind kind;
  final int? statusCode;
  final Object? body;

  /// What is worth trying again: the decision behind retries and the outbox.
  bool get isTransient => switch (kind) {
    ApiErrorKind.unreachable || ApiErrorKind.server => true,
    ApiErrorKind.rejected || ApiErrorKind.invalidResponse => false,
  };

  @override
  String toString() => 'ApiError(${kind.name}, statusCode: $statusCode)';
}
