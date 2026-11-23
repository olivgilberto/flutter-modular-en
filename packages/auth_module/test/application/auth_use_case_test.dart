import 'package:auth_module/application/ports/auth_repository.dart';
import 'package:auth_module/application/use_cases/auth_use_case.dart';
import 'package:auth_module/domain/auth_failure.dart';
import 'package:auth_module/domain/entities/user.dart';
import 'package:auth_module/domain/value_objects/email_address.dart';
import 'package:auth_module/domain/value_objects/password.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fakes.dart';

final class MockAuthRepository extends Mock implements AuthRepository {}

final class MockLogoutCleanerRegistry extends Mock
    implements LogoutCleanerRegistry {}

final class MockOutboxRegistry extends Mock implements OutboxRegistry {}

void main() {
  late MockAuthRepository repository;
  late MockLogoutCleanerRegistry cleaners;
  late MockOutboxRegistry outboxes;
  late FakeDataOwnerRepository owner;
  late FakeLogger logger;
  late FakeAnalytics analytics;
  late AuthUseCase useCase;

  final ana = User(
    id: 'u-1',
    name: 'Ana',
    email: EmailAddress.parse('ana@example.com'),
  );
  const strongPassword = 'correct-horse-battery-staple';

  setUpAll(() {
    registerFallbackValue(EmailAddress.parse('fallback@example.com'));
    registerFallbackValue(Password.parse('fallback-long-password'));
  });

  setUp(() {
    repository = MockAuthRepository();
    cleaners = MockLogoutCleanerRegistry();
    outboxes = MockOutboxRegistry();
    owner = FakeDataOwnerRepository();
    logger = FakeLogger();
    analytics = FakeAnalytics();
    when(
      () => repository.watchSessionExpired(),
    ).thenAnswer((_) => const Stream.empty());
    useCase = AuthUseCase(
      repository: repository,
      owner: owner,
      cleaners: cleaners,
      outboxes: outboxes,
      logger: logger,
      analytics: analytics,
    );
    when(() => cleaners.clearAll()).thenAnswer((_) async {});
  });

  group('login', () {
    test('an invalid email does not reach the repository', () async {
      await expectLater(
        useCase.signInWithPassword(
          email: 'no-at-sign',
          password: strongPassword,
        ),
        throwsA(isA<InvalidEmailFailure>()),
      );
      verifyNever(() => repository.signInWithPassword(any(), any()));
    });

    test('a short password does not reach the repository', () async {
      await expectLater(
        useCase.signInWithPassword(email: 'ana@example.com', password: 'short'),
        throwsA(isA<WeakPasswordFailure>()),
      );
      verifyNever(() => repository.signInWithPassword(any(), any()));
    });

    test('success identifies the user and logs the event', () async {
      when(
        () => repository.signInWithPassword(any(), any()),
      ).thenAnswer((_) async => ana);

      final user = await useCase.signInWithPassword(
        email: ' Ana@Example.com ',
        password: strongPassword,
      );

      expect(user, ana);
      verify(
        () => repository.signInWithPassword(
          EmailAddress.parse('ana@example.com'),
          Password.parse(strongPassword),
        ),
      ).called(1);
      expect(logger.userIds, ['u-1']);
      expect(analytics.events, ['auth_session_started']);
      expect(analytics.parameters['auth_session_started'], {
        'method': 'password',
      });
    });

    test('a refusal from the backend identifies nobody', () async {
      when(
        () => repository.signInWithPassword(any(), any()),
      ).thenThrow(const InvalidCredentialsFailure());

      await expectLater(
        useCase.signInWithPassword(
          email: 'ana@example.com',
          password: strongPassword,
        ),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      expect(logger.userIds, isEmpty);
      expect(analytics.events, isEmpty);
    });
  });

  test('sign-up trims the name and logs the event', () async {
    when(
      () => repository.registerAccount(
        name: any(named: 'name'),
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async => ana);

    await useCase.registerAccount(
      name: '  Ana ',
      email: 'ana@example.com',
      password: strongPassword,
    );

    verify(
      () => repository.registerAccount(
        name: any(named: 'name', that: equals('Ana')),
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).called(1);
    expect(analytics.events, ['auth_account_registered']);
  });

  test('a restored session identifies the user, with no event', () async {
    when(() => repository.restoreSession()).thenAnswer((_) async => ana);

    expect(await useCase.restoreSession(), ana);
    expect(logger.userIds, ['u-1']);
    expect(analytics.events, isEmpty);
  });

  group('logout', () {
    test('ends the session and then cleans up the data', () async {
      when(() => repository.signOut()).thenAnswer((_) async {});

      await useCase.signOut();

      verifyInOrder([() => repository.signOut(), () => cleaners.clearAll()]);
      expect(logger.userIds, [null]);
      expect(analytics.events, ['auth_session_ended']);
    });

    test(
      'cleans up the data and forgets the user even if the backend fails',
      () async {
        final error = Exception('backend down');
        when(() => repository.signOut()).thenThrow(error);

        await expectLater(useCase.signOut(), throwsA(same(error)));

        verify(() => cleaners.clearAll()).called(1);
        expect(logger.userIds, [null]);
        expect(analytics.events, isEmpty);
      },
    );

    test(
      'an expired session cleans up the data without calling the backend',
      () async {
        await useCase.endExpiredSession();

        verify(() => cleaners.clearAll()).called(1);
        verifyNever(() => repository.signOut());
        expect(logger.userIds, [null]);
        expect(analytics.events, ['auth_session_expired']);
      },
    );

    test('the pending changes come from every module\'s queues', () async {
      when(() => outboxes.pendingOperations()).thenAnswer((_) async => 3);

      expect(await useCase.pendingChanges(), 3);
    });
  });

  group('session state', () {
    late List<bool> published;

    setUp(() {
      published = [];
      useCase.watchSignedIn().listen(published.add);
    });

    test('sign-in, sign-up, and a restored session publish the open session; '
        'with no stored session, it publishes the opposite', () async {
      when(
        () => repository.signInWithPassword(any(), any()),
      ).thenAnswer((_) async => ana);
      when(
        () => repository.registerAccount(
          name: any(named: 'name'),
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => ana);
      when(() => repository.restoreSession()).thenAnswer((_) async => null);

      await useCase.restoreSession();
      await useCase.signInWithPassword(
        email: 'ana@example.com',
        password: strongPassword,
      );
      await useCase.registerAccount(
        name: 'Ana',
        email: 'ana@example.com',
        password: strongPassword,
      );
      await pumpEventQueue();

      expect(published, [false, true, true]);
    });

    test('a refusal from the backend publishes nothing', () async {
      when(
        () => repository.signInWithPassword(any(), any()),
      ).thenThrow(const InvalidCredentialsFailure());

      await expectLater(
        useCase.signInWithPassword(
          email: 'ana@example.com',
          password: strongPassword,
        ),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
      await pumpEventQueue();

      expect(published, isEmpty);
    });

    test(
      'the end of the session is only published after the cleanup',
      () async {
        when(() => repository.signOut()).thenAnswer((_) async {});
        List<bool>? duringCleanup;
        when(() => cleaners.clearAll()).thenAnswer((_) async {
          await pumpEventQueue();
          duringCleanup = [...published];
        });

        await useCase.signOut();
        await pumpEventQueue();

        expect(duringCleanup, isEmpty);
        expect(published, [false]);
      },
    );

    test('the expired session also ends published', () async {
      await useCase.endExpiredSession();
      await pumpEventQueue();

      expect(published, [false]);
    });
  });

  group('someone else after an expired session', () {
    final bia = User(
      id: 'u-2',
      name: 'Bia',
      email: EmailAddress.parse('bia@example.com'),
    );

    void signInAnswers(User user) => when(
      () => repository.signInWithPassword(any(), any()),
    ).thenAnswer((_) async => user);

    test(
      'erases the previous person\'s data before the new session starts',
      () async {
        final published = <bool>[];
        useCase.watchSignedIn().listen(published.add);
        signInAnswers(ana);
        await useCase.signInWithPassword(
          email: 'ana@example.com',
          password: strongPassword,
        );
        // Ana's session expires with pending changes: nobody calls
        // endExpiredSession, and her data stays on the device.
        await pumpEventQueue();
        List<bool>? duringCleanup;
        when(() => cleaners.clearAll()).thenAnswer((_) async {
          await pumpEventQueue();
          duringCleanup = [...published];
        });

        signInAnswers(bia);
        await useCase.signInWithPassword(
          email: 'bia@example.com',
          password: strongPassword,
        );
        await pumpEventQueue();

        verify(() => cleaners.clearAll()).called(1);
        expect(duringCleanup, [true]);
        expect(published, [true, true]);
        expect(logger.userIds, ['u-1', 'u-2']);
      },
    );

    test('the same person finds everything as they left it', () async {
      signInAnswers(ana);
      await useCase.signInWithPassword(
        email: 'ana@example.com',
        password: strongPassword,
      );
      await useCase.signInWithPassword(
        email: 'ana@example.com',
        password: strongPassword,
      );

      verifyNever(() => cleaners.clearAll());
    });

    test('after a complete logout, there is nothing to erase', () async {
      signInAnswers(ana);
      when(() => repository.signOut()).thenAnswer((_) async {});
      await useCase.signInWithPassword(
        email: 'ana@example.com',
        password: strongPassword,
      );
      await useCase.signOut();
      clearInteractions(cleaners);

      signInAnswers(bia);
      await useCase.signInWithPassword(
        email: 'bia@example.com',
        password: strongPassword,
      );

      verifyNever(() => cleaners.clearAll());
    });
  });

  test('a cleanup failure goes to the crash log and up', () async {
    when(() => repository.signOut()).thenAnswer((_) async {});
    when(
      () => cleaners.clearAll(),
    ).thenThrow(const LocalDatabaseError('database locked'));

    await expectLater(useCase.signOut(), throwsA(isA<LocalDatabaseError>()));

    expect(logger.errors, ['auth clear local data']);
    expect(logger.userIds, [null]);
  });

  group('the data owner, stored (chapter 32)', () {
    final bia = User(
      id: 'u-2',
      name: 'Bia',
      email: EmailAddress.parse('bia@example.com'),
    );

    void signInAnswers(User user) => when(
      () => repository.signInWithPassword(any(), any()),
    ).thenAnswer((_) async => user);

    Future<void> signIn(String email) =>
        useCase.signInWithPassword(email: email, password: strongPassword);

    test('sign-in stores the owner; logout erases it after the data', () async {
      signInAnswers(ana);
      when(() => repository.signOut()).thenAnswer((_) async {});
      String? ownerDuringCleanup;
      when(() => cleaners.clearAll()).thenAnswer((_) async {
        ownerDuringCleanup = owner.owner;
      });

      await signIn('ana@example.com');
      expect(owner.owner, 'u-1');

      await useCase.signOut();
      expect(ownerDuringCleanup, 'u-1');
      expect(owner.owner, isNull);
    });

    test('someone else after a restart: the stored owner makes the cleanup '
        'happen first, and only then changes', () async {
      // The app was reopened: memory is empty, the database is not.
      owner.owner = 'u-1';
      signInAnswers(bia);
      String? ownerDuringCleanup;
      when(() => cleaners.clearAll()).thenAnswer((_) async {
        ownerDuringCleanup = owner.owner;
      });

      await signIn('bia@example.com');

      verify(() => cleaners.clearAll()).called(1);
      expect(ownerDuringCleanup, 'u-1');
      expect(owner.owner, 'u-2');
    });

    test('a failing cleanup keeps the previous owner, and the next sign-in '
        'tries again', () async {
      owner.owner = 'u-1';
      signInAnswers(bia);
      when(
        () => cleaners.clearAll(),
      ).thenThrow(const LocalDatabaseError('database locked'));

      await expectLater(
        signIn('bia@example.com'),
        throwsA(isA<LocalDatabaseError>()),
      );
      expect(owner.owner, 'u-1');

      when(() => cleaners.clearAll()).thenAnswer((_) async {});
      await signIn('bia@example.com');
      expect(owner.owner, 'u-2');
    });

    test(
      'an unreadable owner refuses the sign-in before going to the backend',
      () async {
        owner.failing = true;
        final published = <bool>[];
        useCase.watchSignedIn().listen(published.add);

        await expectLater(
          signIn('bia@example.com'),
          throwsA(isA<LocalDatabaseError>()),
        );
        await pumpEventQueue();

        verifyNever(() => repository.signInWithPassword(any(), any()));
        expect(published, isEmpty);
      },
    );

    test(
      'at boot, with no stored session but with an owner, the session expired '
      'before the app closed: nothing is published, and the expiry is reported',
      () async {
        owner.owner = 'u-1';
        when(() => repository.restoreSession()).thenAnswer((_) async => null);
        final published = <bool>[];
        var expirations = 0;
        useCase.watchSignedIn().listen(published.add);
        useCase.watchSessionExpired().listen((_) => expirations++);

        expect(await useCase.restoreSession(), isNull);
        await pumpEventQueue();

        expect(published, isEmpty);
        expect(expirations, 1);
        verifyNever(() => cleaners.clearAll());
      },
    );

    test('at boot, someone else\'s stored session also cleans up the previous '
        'owner\'s data before being published', () async {
      owner.owner = 'u-1';
      when(() => repository.restoreSession()).thenAnswer((_) async => bia);

      expect(await useCase.restoreSession(), bia);

      verify(() => cleaners.clearAll()).called(1);
      expect(owner.owner, 'u-2');
    });

    test('a session stored before this chapter, with no owner, gets an '
        'owner', () async {
      when(() => repository.restoreSession()).thenAnswer((_) async => ana);

      await useCase.restoreSession();

      verifyNever(() => cleaners.clearAll());
      expect(owner.owner, 'u-1');
    });
  });
}
