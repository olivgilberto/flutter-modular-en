import 'dart:convert';
import 'dart:io';

import 'package:auth_module/adapters/driven/auth_api_paths.dart';
import 'package:auth_module/application/use_cases/auth_use_case.dart';
import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'fakes.dart';
import 'support/ffi_local_database.dart';

/// The whole hexagon: View, Bloc, use case, Service, and the session
/// database are the real ones. Only the core ports are mocked, and the
/// module is assembled by its own registration function, as the host will do.
final class _MockApiClient extends Mock implements ApiClient {}

/// Another module's local data, which auth_module does not know.
final class _TasksCleaner implements ClearableOnLogout {
  var cleared = 0;

  @override
  Future<void> clearLocalData() async => cleared++;
}

/// Another module's outbox, with two pending changes.
final class _TasksOutbox implements SyncableOutbox {
  @override
  String get name => 'tasks';

  @override
  Future<int> pendingCount() async => 2;

  @override
  Future<bool> sync() async => false;
}

/// Another module's local data that, when erased, notes what the host saw
/// at that moment.
final class _SessionSpy implements ClearableOnLogout {
  SessionState? seen;

  @override
  Future<void> clearLocalData() async =>
      seen = GetIt.instance<SessionBloc>().state;
}

const _password = 'correct-horse-battery-staple';

final _signInResponse = jsonDecode(
  File('test/fixtures/sign_in_response.json').readAsStringSync(),
);

void main() {
  final getIt = GetIt.instance;
  late _MockApiClient api;
  late FfiLocalDatabaseFactory databases;
  late DefaultLogoutCleanerRegistry cleaners;
  late DefaultOutboxRegistry outboxes;
  late FakeLogger logger;
  late FakeAnalytics analytics;
  late _TasksCleaner tasks;

  /// What the host will do in chapter 28: registers the core ports and
  /// calls the module's function. Called again, it simulates the app opened
  /// once more on the same device (the same database) with empty memory.
  void startApp() => getIt.pushNewScope(
    scopeName: 'app',
    init: (scope) {
      scope
        ..registerSingleton<ApiClient>(api)
        ..registerSingleton<LocalDatabaseFactory>(databases)
        ..registerSingleton<LogoutCleanerRegistry>(cleaners)
        ..registerSingleton<OutboxRegistry>(outboxes)
        ..registerSingleton<AppLogger>(logger)
        ..registerSingleton<AppAnalytics>(analytics);
      registerAuthModuleDependencies(scope);
    },
  );

  Future<void> restartApp() async {
    await getIt.popScope();
    startApp();
  }

  AuthUseCase auth() => getIt<AuthUseCase>();
  Future<String?> token() => getIt<TokenProvider>().currentToken();

  // `authenticated` goes into the stubs because the refresh passes it as
  // false (chapter 27); the other calls use the default.
  void answer(String path, Object? Function() response) => when(
    () => api.post(
      path,
      body: any(named: 'body'),
      authenticated: any(named: 'authenticated'),
    ),
  ).thenAnswer((_) async => response());

  void refuse(String path, ApiError error) => when(
    () => api.post(
      path,
      body: any(named: 'body'),
      authenticated: any(named: 'authenticated'),
    ),
  ).thenThrow(error);

  setUp(() {
    api = _MockApiClient();
    databases = FfiLocalDatabaseFactory();
    cleaners = DefaultLogoutCleanerRegistry();
    outboxes = DefaultOutboxRegistry();
    logger = FakeLogger();
    analytics = FakeAnalytics();
    tasks = _TasksCleaner();
    cleaners.register(tasks);
    outboxes.register(_TasksOutbox());
    startApp();
  });

  tearDown(() async {
    while (getIt.hasScope('app')) {
      await getIt.popScope();
    }
  });

  group('through the screen', () {
    /// The button stays busy after success, with the indicator
    /// animating: pumpAndSettle would never finish.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> openLogin(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/auth/login',
        routes: authModuleRoutes,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates:
              AuthModuleLocalizations.localizationsDelegates,
          supportedLocales: AuthModuleLocalizations.supportedLocales,
          routerConfig: router,
        ),
      );
    }

    Future<void> signInWith(WidgetTester tester, String email) async {
      await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        _password,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);
    }

    testWidgets('sign-in stores the session and hands the token to the core', (
      tester,
    ) async {
      answer(AuthApiPaths.signIn, () => _signInResponse);
      await openLogin(tester);

      await signInWith(tester, ' Ana@Example.com ');

      verify(
        () => api.post(
          AuthApiPaths.signIn,
          body: {'email': 'ana@example.com', 'password': _password},
        ),
      ).called(1);
      expect(await token(), 'eyJhbGciOiJIUzI1NiJ9.access');
      expect(logger.userIds, ['u-1']);
      expect(analytics.events, ['auth_session_started']);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('credentials refused: the right message and no session', (
      tester,
    ) async {
      refuse(
        AuthApiPaths.signIn,
        const ApiError(
          ApiErrorKind.rejected,
          statusCode: 401,
          body: {'code': 'invalid_credentials'},
        ),
      );
      await openLogin(tester);

      await signInWith(tester, 'ana@example.com');

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(await token(), isNull);
      expect(analytics.events, isEmpty);
    });

    testWidgets('no network: the generic message, and trying again works', (
      tester,
    ) async {
      refuse(AuthApiPaths.signIn, const ApiError(ApiErrorKind.unreachable));
      await openLogin(tester);

      await signInWith(tester, 'ana@example.com');
      expect(
        find.text('We couldn\'t sign you in right now. Please try again.'),
        findsOneWidget,
      );

      answer(AuthApiPaths.signIn, () => _signInResponse);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await settle(tester);

      expect(await token(), 'eyJhbGciOiJIUzI1NiJ9.access');
    });

    testWidgets(
      'sign-up, opened from sign-in, creates the account and the session',
      (tester) async {
        answer(AuthApiPaths.register, () => _signInResponse);
        await openLogin(tester);

        await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Name'), ' Ana ');
        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'ana@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password (at least 15 characters)'),
          _password,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await settle(tester);

        verify(
          () => api.post(
            AuthApiPaths.register,
            body: {
              'name': 'Ana',
              'email': 'ana@example.com',
              'password': _password,
            },
          ),
        ).called(1);
        expect(await token(), 'eyJhbGciOiJIUzI1NiJ9.access');
        expect(analytics.events, ['auth_account_registered']);
      },
    );

    testWidgets(
      'a short password is refused on the device, without going to the network',
      (tester) async {
        await openLogin(tester);
        await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
        await tester.pumpAndSettle();

        await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Ana');
        await tester.enterText(
          find.widgetWithText(TextField, 'Email'),
          'ana@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Password (at least 15 characters)'),
          'short',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
        await settle(tester);

        expect(
          find.text(
            'Choose another password: at least 15 characters, '
            'and not a well-known one.',
          ),
          findsOneWidget,
        );
        verifyZeroInteractions(api);
      },
    );
  });

  group('through the use case', () {
    Future<void> signedIn() async {
      answer(AuthApiPaths.signIn, () => _signInResponse);
      await auth().signInWithPassword(
        email: 'ana@example.com',
        password: _password,
      );
      clearInteractions(api);
    }

    test(
      'the session comes back after reopening the app, without the network',
      () async {
        await signedIn();

        await restartApp();
        final user = await auth().restoreSession();

        expect(user?.id, 'u-1');
        expect(await token(), 'eyJhbGciOiJIUzI1NiJ9.access');
        verifyZeroInteractions(api);
        expect(logger.userIds, ['u-1', 'u-1']);
        expect(analytics.events, ['auth_session_started']);
      },
    );

    test(
      'logout counts other modules\' pending changes and erases everything',
      () async {
        await signedIn();
        when(
          () => api.post(AuthApiPaths.signOut),
        ).thenAnswer((_) async => null);

        expect(await auth().pendingChanges(), 2);
        await auth().signOut();

        verify(() => api.post(AuthApiPaths.signOut)).called(1);
        expect(await token(), isNull);
        expect(tasks.cleared, 1);
        expect(logger.userIds.last, isNull);
        expect(analytics.events.last, 'auth_session_ended');

        await restartApp();
        expect(await auth().restoreSession(), isNull);
      },
    );

    test(
      'with no network, logout erases the local data and tells the caller',
      () async {
        await signedIn();
        when(
          () => api.post(AuthApiPaths.signOut),
        ).thenThrow(const ApiError(ApiErrorKind.unreachable));

        await expectLater(auth().signOut(), throwsA(isA<ApiError>()));

        expect(await token(), isNull);
        expect(tasks.cleared, 1);
        expect(analytics.events, isNot(contains('auth_session_ended')));
      },
    );

    test(
      'the refresh stores the new pair, which survives reopening the app',
      () async {
        await signedIn();
        answer(
          AuthApiPaths.refresh,
          () => {'accessToken': 'at-2', 'refreshToken': 'rt-2'},
        );

        expect(await getIt<TokenProvider>().refreshToken(), 'at-2');
        verify(
          () => api.post(
            AuthApiPaths.refresh,
            body: {'refreshToken': 'rt-1'},
            authenticated: false,
          ),
        ).called(1);

        await restartApp();
        expect(await token(), 'at-2');
      },
    );

    test(
      'refresh with no network: the error goes up and the session goes on',
      () async {
        await signedIn();
        refuse(AuthApiPaths.refresh, const ApiError(ApiErrorKind.unreachable));

        await expectLater(
          getIt<TokenProvider>().refreshToken(),
          throwsA(isA<ApiError>()),
        );
        expect(await token(), 'eyJhbGciOiJIUzI1NiJ9.access');
      },
    );

    test('refresh refused: the session expires and its end cleans up every '
        'module', () async {
      await signedIn();
      refuse(
        AuthApiPaths.refresh,
        const ApiError(ApiErrorKind.rejected, statusCode: 401),
      );
      final expired = auth().watchSessionExpired().first;

      expect(await getIt<TokenProvider>().refreshToken(), isNull);
      await expired;
      expect(await token(), isNull);

      await auth().endExpiredSession();
      expect(tasks.cleared, 1);
      expect(logger.userIds.last, isNull);
      expect(analytics.events.last, 'auth_session_expired');
    });
  });

  group('through the session state, as the host sees it', () {
    late SessionBloc session;
    late List<SessionState> states;

    void watchSession() {
      session = getIt<SessionBloc>();
      states = [];
      session.stream.listen(states.add);
    }

    test(
      'sign-in opens the session; logout closes it after the cleanup',
      () async {
        final spy = _SessionSpy();
        cleaners.register(spy);
        watchSession();
        answer(AuthApiPaths.signIn, () => _signInResponse);
        when(
          () => api.post(AuthApiPaths.signOut),
        ).thenAnswer((_) async => null);

        await auth().signInWithPassword(
          email: 'ana@example.com',
          password: _password,
        );
        await pumpEventQueue();
        expect(states, [isA<SessionAuthenticated>()]);

        await auth().signOut();
        await pumpEventQueue();
        expect(spy.seen, isA<SessionAuthenticated>());
        expect(states.last, isA<SessionUnauthenticated>());
      },
    );

    test(
      'once the app is reopened, the restore brings the session back without the network',
      () async {
        answer(AuthApiPaths.signIn, () => _signInResponse);
        await auth().signInWithPassword(
          email: 'ana@example.com',
          password: _password,
        );
        clearInteractions(api);

        await restartApp();
        watchSession();
        session.add(const SessionRestoreRequested());
        await pumpEventQueue();

        expect(states, [isA<SessionAuthenticated>()]);
        verifyZeroInteractions(api);
      },
    );

    test('with no stored session, the restore says nobody signed in', () async {
      watchSession();
      session.add(const SessionRestoreRequested());
      await pumpEventQueue();

      expect(states, [isA<SessionUnauthenticated>()]);
    });

    /// Ana's session dies on the server: the refresh is refused.
    Future<void> expireSession() async {
      refuse(
        AuthApiPaths.refresh,
        const ApiError(ApiErrorKind.rejected, statusCode: 401),
      );
      expect(await getIt<TokenProvider>().refreshToken(), isNull);
      await pumpEventQueue();
    }

    Future<void> signInAs(Object? response, String email) async {
      answer(AuthApiPaths.signIn, () => response);
      await auth().signInWithPassword(email: email, password: _password);
      await pumpEventQueue();
    }

    test('refresh refused with pending changes: the session waits for the '
        'decision, and nothing is erased', () async {
      watchSession();
      await signInAs(_signInResponse, 'ana@example.com');

      await expireSession();

      expect(
        states.last,
        isA<SessionExpiredWithPendingChanges>().having(
          (state) => state.pendingChanges,
          'pendingChanges',
          2,
        ),
      );
      expect(await token(), isNull);
      expect(tasks.cleared, 0);

      session.add(const SessionDiscardRequested());
      await pumpEventQueue();

      expect(states.last, isA<SessionUnauthenticated>());
      expect(tasks.cleared, 1);
      expect(analytics.events.last, 'auth_session_expired');
    });

    test(
      'with no pending changes, the expired session ends on its own',
      () async {
        outboxes.unregisterAll();
        watchSession();
        await signInAs(_signInResponse, 'ana@example.com');

        await expireSession();

        expect(states.last, isA<SessionUnauthenticated>());
        expect(tasks.cleared, 1);
      },
    );

    test(
      'after the expiry, the same person signs in and finds everything',
      () async {
        watchSession();
        await signInAs(_signInResponse, 'ana@example.com');
        await expireSession();

        await signInAs(_signInResponse, 'ana@example.com');

        expect(states.last, isA<SessionAuthenticated>());
        expect(tasks.cleared, 0);
      },
    );

    test(
      'after the expiry, someone else signs in: the previous person\'s data is '
      'erased first',
      () async {
        final spy = _SessionSpy();
        watchSession();
        await signInAs(_signInResponse, 'ana@example.com');
        await expireSession();
        cleaners.register(spy);

        final bia = {
          ..._signInResponse as Map<String, Object?>,
          'user': {'id': 'u-2', 'name': 'Bia', 'email': 'bia@example.com'},
        };
        await signInAs(bia, 'bia@example.com');

        expect(tasks.cleared, 1);
        expect(spy.seen, isA<SessionExpiredWithPendingChanges>());
        expect(states.last, isA<SessionAuthenticated>());
        expect(logger.userIds, ['u-1', 'u-2']);
      },
    );

    group('after the expiry and reopening the app (chapter 32)', () {
      final bia = {
        ..._signInResponse as Map<String, Object?>,
        'user': {'id': 'u-2', 'name': 'Bia', 'email': 'bia@example.com'},
      };

      /// Ana leaves through expiry with pending changes, and the app is closed
      /// before anyone decides. Memory goes away; the database stays.
      Future<void> expiredAndRestarted() async {
        watchSession();
        await signInAs(_signInResponse, 'ana@example.com');
        await expireSession();
        await restartApp();
        watchSession();
        session.add(const SessionRestoreRequested());
        await pumpEventQueue();
      }

      test(
        'the boot goes back to waiting for the decision, with the changes counted, and '
        'nothing is erased',
        () async {
          await expiredAndRestarted();

          expect(states, [
            isA<SessionExpiredWithPendingChanges>().having(
              (state) => state.pendingChanges,
              'pendingChanges',
              2,
            ),
          ]);
          expect(tasks.cleared, 0);
        },
      );

      test(
        'someone else signs in: the previous person\'s data is erased before '
        'the new session is published',
        () async {
          await expiredAndRestarted();
          final spy = _SessionSpy();
          cleaners.register(spy);

          await signInAs(bia, 'bia@example.com');

          expect(tasks.cleared, 1);
          expect(spy.seen, isA<SessionExpiredWithPendingChanges>());
          expect(states.last, isA<SessionAuthenticated>());
        },
      );

      test('the same person signs in and finds everything', () async {
        await expiredAndRestarted();

        await signInAs(_signInResponse, 'ana@example.com');

        expect(tasks.cleared, 0);
        expect(states.last, isA<SessionAuthenticated>());
      });

      test(
        'discarding erases the data and the owner: the next boot starts with '
        'nobody',
        () async {
          await expiredAndRestarted();
          session.add(const SessionDiscardRequested());
          await pumpEventQueue();
          expect(tasks.cleared, 1);

          await restartApp();
          watchSession();
          session.add(const SessionRestoreRequested());
          await pumpEventQueue();

          expect(states, [isA<SessionUnauthenticated>()]);
        },
      );
    });
  });
}
