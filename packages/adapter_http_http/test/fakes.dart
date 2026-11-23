import 'package:core/core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A response from the simulated server, built on every request.
typedef Responder = http.Response Function(http.Request request);

http.Response json(int status, String body) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});

Never offline(http.Request request) =>
    throw http.ClientException('no network', request.url);

/// Replaces the http package's network: each request consumes the next
/// [Responder]; the last one repeats. Each attempt arrives here as a new
/// request, with the headers it went out with.
final class FakeServer {
  FakeServer(this._responders);

  final List<Responder> _responders;
  final requests = <http.Request>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final responder = _responders.length > 1
        ? _responders.removeAt(0)
        : _responders.single;
    return responder(request);
  });
}

final class FakeLogger implements AppLogger {
  final messages = <String>[];

  @override
  void log(String message) => messages.add(message);

  @override
  void error(String reason, Object error, StackTrace stackTrace) {}

  @override
  void fatal(Object error, StackTrace stackTrace) {}

  @override
  void setUserId(String? opaqueId) {}
}

/// The session as the adapter sees it: the current token and the result of
/// the refresh, which can be a new token, `null` (session ended), or an
/// error (no network to refresh).
final class FakeTokenProvider implements TokenProvider {
  FakeTokenProvider(this.token, {this.refreshed, this.refreshError});

  String? token;
  final String? refreshed;
  final Exception? refreshError;
  var refreshCalls = 0;

  @override
  Future<String?> currentToken() async => token;

  @override
  Future<String?> refreshToken() async {
    refreshCalls++;
    if (refreshError case final error?) throw error;
    return token = refreshed;
  }
}
