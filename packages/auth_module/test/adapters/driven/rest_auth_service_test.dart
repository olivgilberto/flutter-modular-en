import 'package:auth_module/adapters/driven/auth_api_paths.dart';
import 'package:auth_module/adapters/driven/models/auth_model.dart';
import 'package:auth_module/adapters/driven/services/rest_auth_service.dart';
import 'package:auth_module/domain/auth_failure.dart';
import 'package:auth_module/domain/value_objects/email_address.dart';
import 'package:auth_module/domain/value_objects/password.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'driven_fakes.dart';

final class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;
  late FakeSessionStore session;
  late RestAuthService service;
  final email = EmailAddress.parse('ana@example.com');
  final password = Password.parse('correct-horse-battery-staple');

  Map<String, Object?> response({String email = 'ana@example.com'}) => {
    'user': {'id': 'u-1', 'name': 'Ana', 'email': email},
    'accessToken': 'at-1',
    'refreshToken': 'rt-1',
  };

  void rejectWith(String path, int status, String code) {
    when(() => api.post(path, body: any(named: 'body'))).thenThrow(
      ApiError(ApiErrorKind.rejected, statusCode: status, body: {'code': code}),
    );
  }

  setUp(() {
    api = MockApiClient();
    session = FakeSessionStore();
    service = RestAuthService(apiClient: api, session: session);
  });

  test('sign-in converts the response and stores the session', () async {
    when(
      () => api.post(AuthApiPaths.signIn, body: any(named: 'body')),
    ).thenAnswer((_) async => response());

    final user = await service.signInWithPassword(email, password);

    expect(user.id, 'u-1');
    expect(session.stored?.refreshToken, 'rt-1');
    final body =
        verify(
              () => api.post(
                AuthApiPaths.signIn,
                body: captureAny(named: 'body'),
              ),
            ).captured.single
            as Map;
    expect(body, {'email': 'ana@example.com', 'password': password.value});
  });

  test('401 with invalid_credentials becomes a Failure', () async {
    rejectWith(AuthApiPaths.signIn, 401, 'invalid_credentials');

    await expectLater(
      service.signInWithPassword(email, password),
      throwsA(isA<InvalidCredentialsFailure>()),
    );
  });

  test('422 with email_already_registered becomes a Failure', () async {
    rejectWith(AuthApiPaths.register, 422, 'email_already_registered');

    await expectLater(
      service.registerAccount(name: 'Ana', email: email, password: password),
      throwsA(isA<EmailAlreadyRegisteredFailure>()),
    );
  });

  test('422 with weak_password becomes the same domain failure', () async {
    rejectWith(AuthApiPaths.register, 422, 'weak_password');

    await expectLater(
      service.registerAccount(name: 'Ana', email: email, password: password),
      throwsA(isA<WeakPasswordFailure>()),
    );
  });

  test('422 with an unknown code stays technical', () async {
    rejectWith(AuthApiPaths.register, 422, 'something_new');

    await expectLater(
      service.registerAccount(name: 'Ana', email: email, password: password),
      throwsA(isA<ApiError>()),
    );
  });

  test(
    'an invalid email from the server becomes neither a Failure nor a session',
    () async {
      when(
        () => api.post(AuthApiPaths.signIn, body: any(named: 'body')),
      ).thenAnswer((_) async => response(email: 'no-at-sign'));

      await expectLater(
        service.signInWithPassword(email, password),
        throwsA(
          isA<ApiError>().having(
            (e) => e.kind,
            'kind',
            ApiErrorKind.invalidResponse,
          ),
        ),
      );
      expect(session.stored, isNull);
    },
  );

  test('logout erases the session even if the backend fails', () async {
    session.stored = ana;
    when(
      () => api.post(AuthApiPaths.signOut),
    ).thenThrow(const ApiError(ApiErrorKind.server, statusCode: 503));

    await expectLater(service.signOut(), throwsA(isA<ApiError>()));
    expect(session.stored, isNull);
  });

  test(
    'the session is restored from the device, without the network',
    () async {
      session.stored = ana;

      final user = await service.restoreSession();

      expect(user?.id, 'u-1');
      verifyNoMoreInteractions(api);
    },
  );

  test(
    'a stored session with an invalid email is a technical failure',
    () async {
      session.stored = const AuthModel(
        userId: 'u-1',
        name: 'Ana',
        email: 'no-at-sign',
        accessToken: 'at-1',
        refreshToken: 'rt-1',
      );

      await expectLater(
        service.restoreSession(),
        throwsA(isA<LocalDatabaseError>()),
      );
    },
  );

  test('the session expiry arrives through the port', () async {
    final expired = service.watchSessionExpired().first;

    session.expired.add(null);

    await expectLater(expired, completes);
  });
}
