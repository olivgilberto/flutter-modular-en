import 'dart:async';

import 'package:auth_module/auth_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/session/session_gate.dart';

import '../support/fakes.dart';

void main() {
  late StreamController<SessionState> changes;
  late List<String> calls;

  setUp(() {
    changes = StreamController<SessionState>.broadcast();
    calls = [];
  });

  SessionGate gate({SessionState initial = const SessionUnknown()}) {
    final gate = SessionGate(
      initial: initial,
      changes: changes.stream,
      onSignedIn: () => calls.add('opens the scope'),
      // Async, like get_it's popScopesTill.
      onSignedOut: () async {
        await Future<void>.delayed(Duration.zero);
        calls.add('closes the scope');
      },
    );
    gate.addListener(() => calls.add('notifies the router'));
    addTearDown(gate.dispose);
    return gate;
  }

  test('a session restored at boot opens the scope right away', () {
    final session = gate(initial: const SessionAuthenticated());

    expect(session.authenticated, isTrue);
    expect(calls, ['opens the scope']);
  });

  test('sign-in opens the scope and notifies the router', () async {
    final session = gate();

    changes.add(const SessionAuthenticated());
    await pumpEventQueue();

    expect(session.authenticated, isTrue);
    expect(calls, ['opens the scope', 'notifies the router']);
  });

  test(
    'the end of the session closes the scope before notifying the router',
    () async {
      final session = gate(initial: const SessionAuthenticated());
      calls.clear();

      changes.add(const SessionUnauthenticated());
      await pumpEventQueue();

      expect(session.authenticated, isFalse);
      expect(calls, ['closes the scope', 'notifies the router']);
    },
  );

  test('the boot waits for the stored session to be read', () async {
    final session = gate();
    final logger = FakeLogger();

    final waiting = session.waitUntilKnown(
      timeout: const Duration(seconds: 1),
      logger: logger,
    );
    changes.add(const SessionAuthenticated());
    await waiting;

    expect(session.authenticated, isTrue);
    expect(logger.logs, isEmpty);
  });

  test(
    'once the time is up, the boot goes on with no session and logs it',
    () async {
      final session = gate();
      final logger = FakeLogger();

      await session.waitUntilKnown(
        timeout: const Duration(milliseconds: 50),
        logger: logger,
      );

      expect(session.authenticated, isFalse);
      expect(logger.logs, ['boot: stored session not read in time']);

      // A read that arrives later still moves the user on.
      changes.add(const SessionAuthenticated());
      await pumpEventQueue();
      expect(calls, ['opens the scope', 'notifies the router']);
    },
  );

  test(
    'an expired session with pending changes leads to the sign-in without closing '
    'the scope',
    () async {
      final session = gate(initial: const SessionAuthenticated());
      calls.clear();

      changes.add(const SessionExpiredWithPendingChanges(pendingChanges: 2));
      await pumpEventQueue();

      expect(session.authenticated, isFalse);
      expect(calls, ['notifies the router']);

      // Signing in again does not open a second scope: the
      // openSessionScope guard takes care of that in the app.
      changes.add(const SessionAuthenticated());
      await pumpEventQueue();
      expect(calls, [
        'notifies the router',
        'opens the scope',
        'notifies the router',
      ]);
    },
  );
}
