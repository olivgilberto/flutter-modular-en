import 'package:adapter_http_http/adapter_http_http.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  (HttpApiClient, FakeServer) clientWith(
    List<Responder> responders,
    TokenProvider? tokenProvider,
  ) {
    final server = FakeServer(responders);
    final client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      tokenProvider: () => tokenProvider,
      logger: FakeLogger(),
      retryBaseDelay: Duration.zero,
      client: server.client,
    );
    return (client, server);
  }

  Iterable<Object?> authorizations(FakeServer server) =>
      server.requests.map((r) => r.headers['Authorization']);

  Matcher apiError(ApiErrorKind kind, {int? statusCode}) => throwsA(
    isA<ApiError>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.statusCode, 'statusCode', statusCode),
  );

  test(
    '401 with a token: refreshes once and repeats with the new token',
    () async {
      final provider = FakeTokenProvider('expired', refreshed: 'fresh');
      final (client, server) = clientWith([
        (_) => json(401, '{}'),
        (_) => json(200, '{"ok": true}'),
      ], provider);

      expect(await client.get('/tasks'), {'ok': true});
      expect(provider.refreshCalls, 1);
      expect(authorizations(server), ['Bearer expired', 'Bearer fresh']);
    },
  );

  test('a second 401 after the refresh does not refresh again', () async {
    final provider = FakeTokenProvider('expired', refreshed: 'fresh');
    final (client, server) = clientWith([(_) => json(401, '{}')], provider);

    await expectLater(
      client.get('/tasks'),
      apiError(ApiErrorKind.rejected, statusCode: 401),
    );
    expect(provider.refreshCalls, 1);
    expect(server.requests, hasLength(2));
  });

  test(
    'refresh refused: the 401 goes up and the request is not repeated',
    () async {
      final provider = FakeTokenProvider('expired');
      final (client, server) = clientWith([(_) => json(401, '{}')], provider);

      await expectLater(
        client.get('/tasks'),
        apiError(ApiErrorKind.rejected, statusCode: 401),
      );
      expect(provider.refreshCalls, 1);
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'refresh with no network: raises the transient error, not the 401',
    () async {
      final provider = FakeTokenProvider(
        'expired',
        refreshError: const ApiError(ApiErrorKind.unreachable),
      );
      final (client, server) = clientWith([(_) => json(401, '{}')], provider);

      await expectLater(
        client.get('/tasks'),
        apiError(ApiErrorKind.unreachable),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'a 401 without a token, like the sign-in one, asks for no refresh',
    () async {
      final provider = FakeTokenProvider(null, refreshed: 'fresh');
      final (client, _) = clientWith([(_) => json(401, '{}')], provider);

      await expectLater(
        client.post('/v1/auth/sign-in', body: {}),
        apiError(ApiErrorKind.rejected, statusCode: 401),
      );
      expect(provider.refreshCalls, 0);
    },
  );

  test(
    'an unauthenticated request carries no token and does not refresh',
    () async {
      final provider = FakeTokenProvider('expired', refreshed: 'fresh');
      final (client, server) = clientWith([(_) => json(401, '{}')], provider);

      await expectLater(
        client.post('/v1/auth/refresh', body: {}, authenticated: false),
        apiError(ApiErrorKind.rejected, statusCode: 401),
      );
      expect(authorizations(server), [null]);
      expect(provider.refreshCalls, 0);
    },
  );
}
