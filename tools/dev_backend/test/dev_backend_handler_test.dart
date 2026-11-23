import 'dart:convert';

import 'package:dev_backend/dev_backend.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The handler called directly, with no network: each contract rule in a test.
void main() {
  late DateTime now;
  late DevBackendState state;
  late Handler handler;
  late List<String> lines;

  setUp(() {
    now = DateTime.utc(2026, 10, 28, 12);
    state = DevBackendState(now: () => now);
    lines = [];
    handler = devBackendHandler(state, log: lines.add);
  });

  Future<(int, Object?)> call(
    String method,
    String path, {
    Object? body,
    String? token,
    String? key,
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://127.0.0.1$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {
          'Authorization': ?(token == null ? null : 'Bearer $token'),
          'Idempotency-Key': ?key,
        },
      ),
    );
    final text = await response.readAsString();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  /// The status and the body, compared by content.
  Matcher reply(int status, Object? body) => isA<(int, Object?)>()
      .having((r) => r.$1, 'status', status)
      .having((r) => r.$2, 'body', body);

  Future<String> register([String email = 'ana@example.com']) async {
    final (status, body) = await call(
      'POST',
      '/v1/auth/register',
      body: {
        'name': 'Ana',
        'email': email,
        'password': 'correct-horse-battery-staple',
      },
    );
    expect(status, 201);
    return (body! as Map)['accessToken'] as String;
  }

  Map<String, Object?> create(String title, {String op = 'op-1'}) => {
    'title': title,
    'status': 'open',
    'createdAt': '2026-10-28T09:00:00.000Z',
    'operationId': op,
  };

  group('authentication', () {
    test('sign-up and sign-in return the user and both tokens', () async {
      await register();
      final (status, body) = await call(
        'POST',
        '/v1/auth/sign-in',
        body: {
          'email': ' ANA@example.com',
          'password': 'correct-horse-battery-staple',
        },
      );

      expect(status, 200);
      expect(body, {
        'user': {
          'id': 'u-1',
          'name': 'Ana',
          'email': 'ana@example.com',
          'createdAt': '2026-10-28T12:00:00.000Z',
        },
        'accessToken': isA<String>(),
        'refreshToken': isA<String>(),
        'expiresIn': 900,
      });
    });

    test('the refusal codes the app translates', () async {
      await register();
      expect(
        await call(
          'POST',
          '/v1/auth/register',
          body: {
            'name': 'Ana',
            'email': 'ana@example.com',
            'password': 'correct-horse-battery-staple',
          },
        ),
        reply(422, {'code': 'email_already_registered'}),
      );
      expect(
        await call(
          'POST',
          '/v1/auth/register',
          body: {
            'name': 'Bia',
            'email': 'bia@example.com',
            'password': '123456789012345',
          },
        ),
        reply(422, {'code': 'weak_password'}),
      );
      expect(
        await call(
          'POST',
          '/v1/auth/sign-in',
          body: {'email': 'ana@example.com', 'password': 'any-other-password'},
        ),
        reply(401, {'code': 'invalid_credentials'}),
      );
    });

    test('the expired token gets a 401, and the refresh trades both', () async {
      await call(
        'POST',
        '/v1/auth/register',
        body: {
          'name': 'Ana',
          'email': 'ana@example.com',
          'password': 'correct-horse-battery-staple',
        },
      );
      final session = state.sessions.single;
      final oldRefresh = session.refreshToken;
      now = now.add(const Duration(minutes: 15));

      expect(
        (await call(
          'GET',
          '/v1/tasks?status=active',
          token: session.accessToken,
        )).$1,
        401,
      );
      final (status, body) = await call(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': oldRefresh},
      );
      expect(status, 200);
      final access = (body! as Map)['accessToken'] as String;
      expect(
        (await call('GET', '/v1/tasks?status=active', token: access)).$1,
        200,
      );
      // The old refresh token is no longer valid.
      expect(
        (await call(
          'POST',
          '/v1/auth/refresh',
          body: {'refreshToken': oldRefresh},
        )).$1,
        401,
      );
    });

    test('sign-out invalidates the token', () async {
      final token = await register();
      expect((await call('POST', '/v1/auth/sign-out', token: token)).$1, 204);
      expect(
        (await call('GET', '/v1/tasks?status=active', token: token)).$1,
        401,
      );
    });
  });

  group('tasks', () {
    late String token;

    setUp(() async => token = await register());

    test(
      'create with the app\'s id, update with the version, archive',
      () async {
        expect(
          await call(
            'PUT',
            '/v1/tasks/t-1',
            body: create('  Pay the power bill '),
            token: token,
          ),
          reply(201, {
            'id': 't-1',
            'title': 'Pay the power bill',
            'status': 'open',
            'createdAt': '2026-10-28T09:00:00.000Z',
            'version': 1,
          }),
        );
        final (_, renamed) = await call(
          'PATCH',
          '/v1/tasks/t-1',
          body: {
            'title': 'Pay the October power bill',
            'status': 'done',
            'baseVersion': 1,
            'operationId': 'op-2',
          },
          token: token,
        );
        expect((renamed! as Map)['version'], 2);
        final (status, archived) = await call(
          'PATCH',
          '/v1/tasks/t-1',
          body: {'status': 'archived', 'baseVersion': 2, 'operationId': 'op-3'},
          token: token,
        );
        expect(status, 200);
        expect(archived, containsPair('title', 'Pay the October power bill'));
        expect(
          await call('GET', '/v1/tasks?status=active', token: token),
          reply(200, {'items': <Object?>[], 'nextCursor': null}),
        );
      },
    );

    test('a version someone else changed is a conflict; an operation already '
        'applied, resent, is not', () async {
      await call(
        'PUT',
        '/v1/tasks/t-1',
        body: create('Pay the power bill'),
        token: token,
      );
      final edit = {
        'title': 'Pay the October power bill',
        'status': 'open',
        'baseVersion': 1,
        'operationId': 'op-2',
      };
      await call('PATCH', '/v1/tasks/t-1', body: edit, token: token);

      // Resending the same operation, after the key expired.
      expect(
        (await call('PATCH', '/v1/tasks/t-1', body: edit, token: token)).$1,
        200,
      );
      await call(
        'POST',
        '/dev/tasks/t-1/edit',
        body: {'title': 'Electricity bill'},
      );
      expect(
        await call(
          'PATCH',
          '/v1/tasks/t-1',
          body: {...edit, 'baseVersion': 2, 'operationId': 'op-3'},
          token: token,
        ),
        reply(409, {'code': 'version_conflict'}),
      );
    });

    test('creation repeated by the same operation returns the task; by '
        'another, it is a conflict', () async {
      await call(
        'PUT',
        '/v1/tasks/t-1',
        body: create('Pay the power bill'),
        token: token,
      );

      expect(
        (await call(
          'PUT',
          '/v1/tasks/t-1',
          body: create('Pay the power bill'),
          token: token,
        )).$1,
        200,
      );
      expect(
        (await call(
          'PUT',
          '/v1/tasks/t-1',
          body: create('Pay the power bill', op: 'op-9'),
          token: token,
        )).$2,
        {'code': 'version_conflict'},
      );
    });

    test('Idempotency-Key: same key and body, the same response; another '
        'body, 422', () async {
      final first = await call(
        'PUT',
        '/v1/tasks/t-1',
        body: create('Pay the power bill'),
        token: token,
        key: 'op-1',
      );
      final again = await call(
        'PUT',
        '/v1/tasks/t-1',
        body: create('Pay the power bill'),
        token: token,
        key: 'op-1',
      );

      expect(first.$1, 201);
      expect(again, reply(first.$1, first.$2));
      expect(
        await call(
          'PUT',
          '/v1/tasks/t-1',
          body: create('Something else'),
          token: token,
          key: 'op-1',
        ),
        reply(422, {'code': 'idempotency_key_reused'}),
      );
    });

    test(
      'the list comes by cursor, oldest first, without the archived ones and without '
      'someone else\'s',
      () async {
        for (final (id, minute) in [('t-3', 3), ('t-1', 1), ('t-2', 2)]) {
          await call(
            'PUT',
            '/v1/tasks/$id',
            body: {
              ...create('Task $id', op: 'op-$id'),
              'createdAt': '2026-10-28T09:0$minute:00.000Z',
            },
            token: token,
          );
        }
        final other = await register('bia@example.com');
        await call(
          'PUT',
          '/v1/tasks/b-1',
          body: create('Bia\'s'),
          token: other,
        );

        final (_, first) = await call(
          'GET',
          '/v1/tasks?status=active&limit=2',
          token: token,
        );
        expect(
          [for (final t in (first! as Map)['items'] as List) t['id']],
          ['t-1', 't-2'],
        );
        final cursor = (first as Map)['nextCursor'];
        final (_, second) = await call(
          'GET',
          '/v1/tasks?status=active&limit=2&cursor=$cursor',
          token: token,
        );
        expect(second, {
          'items': [containsPair('id', 't-3')],
          'nextCursor': null,
        });
        expect((await call('GET', '/v1/tasks/b-1', token: token)).$1, 404);
      },
    );

    test('invalid title and missing task', () async {
      expect(
        await call('PUT', '/v1/tasks/t-1', body: create('   '), token: token),
        reply(422, {'code': 'invalid_title'}),
      );
      expect(
        (await call(
          'PATCH',
          '/v1/tasks/t-9',
          body: {'status': 'archived', 'baseVersion': 1, 'operationId': 'op-9'},
          token: token,
        )).$1,
        404,
      );
    });
  });

  group('development routes', () {
    test('delete, refuse the next write, and expire the tokens', () async {
      final token = await register();
      await call(
        'PUT',
        '/v1/tasks/t-1',
        body: create('Pay the power bill'),
        token: token,
      );

      expect((await call('DELETE', '/dev/tasks/t-1')).$1, 204);
      expect((await call('GET', '/v1/tasks/t-1', token: token)).$1, 404);

      await call('POST', '/dev/reject-next', body: {'code': 'blocked'});
      expect(
        await call(
          'PUT',
          '/v1/tasks/t-2',
          body: create('Another'),
          token: token,
        ),
        reply(422, {'code': 'blocked'}),
      );
      // Only the next one.
      expect(
        (await call(
          'PUT',
          '/v1/tasks/t-2',
          body: create('Another', op: 'op-2'),
          token: token,
        )).$1,
        201,
      );

      await call('POST', '/dev/expire-tokens');
      expect(
        (await call('GET', '/v1/tasks?status=active', token: token)).$1,
        401,
      );
    });

    test(
      'the next accepted write without the version, only the next one',
      () async {
        final token = await register();
        await call('POST', '/dev/omit-version-next');

        final (status, body) = await call(
          'PUT',
          '/v1/tasks/t-1',
          body: create('Pay the power bill'),
          token: token,
        );
        expect(status, 201);
        expect((body! as Map).containsKey('version'), isFalse);
        expect(state.tasks['t-1']!.version, 1);

        final (_, next) = await call(
          'PUT',
          '/v1/tasks/t-2',
          body: create('Another', op: 'op-2'),
          token: token,
        );
        expect((next! as Map).containsKey('version'), isTrue);
      },
    );

    test('the state and the reset', () async {
      await register();
      final (_, body) = await call('GET', '/dev/state');
      expect((body! as Map)['users'], hasLength(1));

      await call('POST', '/dev/reset');
      expect(state.users, isEmpty);
    });
  });

  test('health, and the log with no body or token', () async {
    expect(await call('GET', '/v1/health'), reply(200, {'status': 'ok'}));
    expect((await call('HEAD', '/v1/health')).$1, 200);
    final token = await register();
    await call('GET', '/v1/tasks?status=active', token: token);

    expect(lines, contains('GET /v1/health → 200'));
    expect(lines, contains('GET /v1/tasks?status=active → 200'));
    expect(lines.join('\n'), isNot(contains(token)));
    expect(lines.join('\n'), isNot(contains('horse')));
  });
}
