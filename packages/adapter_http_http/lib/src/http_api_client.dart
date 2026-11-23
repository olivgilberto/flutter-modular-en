import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

import 'io_client.dart';

/// [ApiClient] with the http package. What were three interceptors in Dio
/// are three visible pieces here: the token and the refresh on a 401 live
/// in the send itself; the retry is the package's [RetryClient]; the log
/// and each attempt's timeout live in an inner client. Every failure
/// becomes an [ApiError] before leaving this class; responses are never cached.
final class HttpApiClient implements ApiClient {
  HttpApiClient({
    required String baseUrl,
    required TokenProvider? Function() tokenProvider,
    required AppLogger logger,
    Duration retryBaseDelay = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 20),
    http.Client? client,
    Random? random,
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _tokenProvider = tokenProvider,
       _timeout = timeout,
       _client = RetryClient(
         _AttemptClient(
           client ?? ioClient(connectionTimeout: const Duration(seconds: 10)),
           logger,
           timeout,
         ),
         // Three attempts in total: RetryClient only counts the retries.
         retries: 2,
         // Only transient failures: 5xx and transport failures. Never a 4xx.
         when: (response) => response.statusCode >= 500,
         whenError: (error, _) => _isTransport(error),
         delay: _backoff(retryBaseDelay, random ?? Random()),
       );

  final String _baseUrl;

  /// Resolved on every request: the authentication module registers its
  /// TokenProvider after the adapters, or never.
  final TokenProvider? Function() _tokenProvider;
  final Duration _timeout;
  final http.Client _client;

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  @override
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) => _send(
    'POST',
    path,
    body: body,
    idempotencyKey: idempotencyKey,
    authenticated: authenticated,
  );

  @override
  Future<Object?> put(String path, {Object? body, String? idempotencyKey}) =>
      _send('PUT', path, body: body, idempotencyKey: idempotencyKey);

  @override
  Future<Object?> patch(String path, {Object? body, String? idempotencyKey}) =>
      _send('PATCH', path, body: body, idempotencyKey: idempotencyKey);

  @override
  Future<Object?> delete(String path, {String? idempotencyKey}) =>
      _send('DELETE', path, idempotencyKey: idempotencyKey);

  /// The whole send. With [authenticated], it carries the token when there
  /// is a TokenProvider and a session; on a 401 for a request that carried
  /// the token, it asks for a new token, once, and repeats with it. Without
  /// [authenticated], it is the refresh itself, which cannot ask for another
  /// (chapter 27).
  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) async {
    // A request can only be sent once: the repeat after the refresh builds
    // another one, with the same body and the same key.
    http.Request build(String? token) {
      final request = http.Request(method, _uri(path, query))
        ..headers['accept'] = 'application/json';
      if (idempotencyKey != null) {
        request.headers['Idempotency-Key'] = idempotencyKey;
      }
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return request;
    }

    try {
      final provider = authenticated ? _tokenProvider() : null;
      final token = await provider?.currentToken();
      var response = await _fetch(build(token));
      if (response.statusCode == 401 && provider != null && token != null) {
        // With no new token, the session is over: the TokenProvider has
        // already reported it, and the 401 goes up; the host's redirect leads
        // to the sign-in (chapter 28). A refresh with no network raises its
        // own error, which is transient.
        final renewed = await provider.refreshToken();
        if (renewed != null) response = await _fetch(build(renewed));
      }
      return _decode(response);
    } on ApiError {
      rethrow;
    } on Exception {
      // No response after the attempts: no network, timeout, connection
      // refused, certificate rejected.
      throw const ApiError(ApiErrorKind.unreachable);
    }
  }

  Uri _uri(String path, Map<String, String>? query) {
    final uri = Uri.parse('$_baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<http.Response> _fetch(http.Request request) async {
    final streamed = await _client.send(request);
    return http.Response.fromStream(streamed).timeout(_timeout);
  }

  /// 2xx → the decoded body (null if empty), or invalidResponse, never
  /// with the body, if it is not JSON; 5xx → server; any other status →
  /// rejected, both with status and body.
  static Object? _decode(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiError(ApiErrorKind.invalidResponse, statusCode: status);
      }
    }
    throw ApiError(
      status >= 500 ? ApiErrorKind.server : ApiErrorKind.rejected,
      statusCode: status,
      body: _tryDecode(response.bodyBytes),
    );
  }

  static Object? _tryDecode(List<int> bytes) {
    try {
      return bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null;
    }
  }

  static bool _isTransport(Object error) =>
      error is http.ClientException ||
      error is IOException ||
      error is TimeoutException;

  /// baseDelay × 2^retry, plus up to one baseDelay of jitter; retries
  /// count from zero.
  static Duration Function(int) _backoff(Duration baseDelay, Random random) =>
      (retry) => baseDelay * pow(2, retry) + baseDelay * random.nextDouble();
}

/// Each attempt, one by one: the timeout and the log. Records method, path,
/// status, and duration in the [AppLogger]; never headers, query, or
/// bodies, which is where tokens and personal data would be.
final class _AttemptClient extends http.BaseClient {
  _AttemptClient(this._inner, this._logger, this._timeout);

  final http.Client _inner;
  final AppLogger _logger;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    final what = '${request.method} ${request.url.path}';
    try {
      final response = await _inner.send(request).timeout(_timeout);
      _logger.log(
        '$what → ${response.statusCode} (${watch.elapsedMilliseconds} ms)',
      );
      return response;
    } catch (_) {
      // A breadcrumb, not a recorded error: whoever handles the ApiError
      // decides whether it is worth reporting.
      _logger.log('$what → no response (${watch.elapsedMilliseconds} ms)');
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
