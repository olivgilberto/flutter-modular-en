import 'package:adapter_http_http/adapter_http_http.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeLogger logger;

  setUp(() => logger = FakeLogger());

  (HttpApiClient, FakeServer) clientWith(
    List<Responder> responders, {
    TokenProvider? tokenProvider,
  }) {
    final server = FakeServer(responders);
    final client = HttpApiClient(
      baseUrl: 'https://api.example.com',
      tokenProvider: () => tokenProvider,
      logger: logger,
      retryBaseDelay: Duration.zero,
      client: server.client,
    );
    return (client, server);
  }

  test('returns the body already decoded', () async {
    final (client, _) = clientWith([(_) => json(200, '{"id": 1}')]);

    expect(await client.get('/tasks'), {'id': 1});
  });

  test('4xx becomes rejected, with status and body, without a retry', () async {
    final (client, server) = clientWith([
      (_) => json(422, '{"code": "title_required"}'),
    ]);

    await expectLater(
      client.post('/tasks', body: {'title': ''}),
      throwsA(
        isA<ApiError>()
            .having((e) => e.kind, 'kind', ApiErrorKind.rejected)
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.body, 'body', {'code': 'title_required'}),
      ),
    );
    expect(server.requests, hasLength(1));
  });

  test('5xx is retried and may succeed on the next attempt', () async {
    final (client, server) = clientWith([
      (_) => json(503, '{}'),
      (_) => json(200, '{"ok": true}'),
    ]);

    expect(await client.get('/tasks'), {'ok': true});
    expect(server.requests, hasLength(2));
  });

  test('a persistent 5xx becomes server after three attempts', () async {
    final (client, server) = clientWith([(_) => json(500, '{}')]);

    await expectLater(
      client.get('/tasks'),
      throwsA(
        isA<ApiError>().having((e) => e.kind, 'kind', ApiErrorKind.server),
      ),
    );
    expect(server.requests, hasLength(3));
  });

  test('no network becomes unreachable after three attempts', () async {
    final (client, server) = clientWith([offline]);

    await expectLater(
      client.get('/tasks'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.kind, 'kind', ApiErrorKind.unreachable)
            .having((e) => e.isTransient, 'isTransient', isTrue),
      ),
    );
    expect(server.requests, hasLength(3));
  });

  test(
    'a body that is not JSON becomes invalidResponse, without the body',
    () async {
      final (client, _) = clientWith([(_) => json(200, '<html>')]);

      await expectLater(
        client.get('/tasks'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.kind, 'kind', ApiErrorKind.invalidResponse)
              .having((e) => e.body, 'body', isNull),
        ),
      );
    },
  );

  test('the idempotency key goes on every attempt', () async {
    final (client, server) = clientWith([
      (_) => json(503, '{}'),
      (_) => json(201, '{}'),
    ]);

    await client.post('/tasks', body: {}, idempotencyKey: 'op-42');

    expect(server.requests.map((r) => r.headers['Idempotency-Key']), [
      'op-42',
      'op-42',
    ]);
  });

  test('sends the token only when there is a TokenProvider', () async {
    final (anonymous, anonymousServer) = clientWith([(_) => json(200, '{}')]);
    final (signedIn, signedInServer) = clientWith([
      (_) => json(200, '{}'),
    ], tokenProvider: FakeTokenProvider('secret'));

    await anonymous.get('/tasks');
    await signedIn.get('/tasks');

    expect(anonymousServer.requests.single.headers['Authorization'], isNull);
    expect(
      signedInServer.requests.single.headers['Authorization'],
      'Bearer secret',
    );
  });

  test(
    'the log has method, path, and status, never the token or body',
    () async {
      final (client, _) = clientWith([
        (_) => json(200, '{"email": "ana@example.com"}'),
      ], tokenProvider: FakeTokenProvider('secret'));

      await client.get('/tasks', query: {'q': 'ana'});

      final line = logger.messages.single;
      expect(line, startsWith('GET /tasks → 200'));
      expect(line, isNot(contains('secret')));
      expect(line, isNot(contains('ana')));
    },
  );
}
