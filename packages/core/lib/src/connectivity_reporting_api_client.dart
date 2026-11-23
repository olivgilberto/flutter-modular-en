import 'dart:async';

import 'api_client.dart';
import 'connectivity.dart';

/// An [ApiClient] that tells the [ConnectivityService] what requests find
/// out about the backend (chapter 35). The service only checks when it
/// starts and when the network interface changes; a backend that goes
/// down, or comes back, while the interface stays up would go unnoticed,
/// with no notice on screen and no transition to online to send the queue.
///
/// - A request that did not reach the server, with the state `online`, asks
///   for a check: if the backend went down, the state becomes `noInternet`,
///   the notice appears, and the new checks with growing backoff start.
/// - Any response, with the state `noInternet`, also asks for one: the
///   backend is back, and the transition to `online` makes the
///   [SyncOrchestrator] send the queues.
///
/// With the state `unknown`, nothing is requested: the service has not
/// started yet, as in the background, where nobody shows a notice or
/// orchestrates sending. No request waits for the check, and no error changes.
final class ConnectivityReportingApiClient implements ApiClient {
  ConnectivityReportingApiClient({
    required ApiClient inner,
    required ConnectivityService connectivityService,
  }) : _inner = inner,
       _connectivity = connectivityService;

  final ApiClient _inner;
  final ConnectivityService _connectivity;

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _report(() => _inner.get(path, query: query));

  @override
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) => _report(
    () => _inner.post(
      path,
      body: body,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    ),
  );

  @override
  Future<Object?> put(String path, {Object? body, String? idempotencyKey}) =>
      _report(
        () => _inner.put(path, body: body, idempotencyKey: idempotencyKey),
      );

  @override
  Future<Object?> patch(String path, {Object? body, String? idempotencyKey}) =>
      _report(
        () => _inner.patch(path, body: body, idempotencyKey: idempotencyKey),
      );

  @override
  Future<Object?> delete(String path, {String? idempotencyKey}) =>
      _report(() => _inner.delete(path, idempotencyKey: idempotencyKey));

  Future<Object?> _report(Future<Object?> Function() request) async {
    try {
      final response = await request();
      _recheckIf(ConnectivityStatus.noInternet);
      return response;
    } on ApiError catch (error) {
      if (error.kind == ApiErrorKind.unreachable) {
        _recheckIf(ConnectivityStatus.online);
      } else {
        // The server answered, even if it refused: it is up.
        _recheckIf(ConnectivityStatus.noInternet);
      }
      rethrow;
    }
  }

  void _recheckIf(ConnectivityStatus status) {
    if (_connectivity.status == status) unawaited(_connectivity.check());
  }
}
