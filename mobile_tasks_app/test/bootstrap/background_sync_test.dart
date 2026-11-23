import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/background_sync.dart';
import 'package:mobile_tasks_app/bootstrap/dependency_injection.dart';

import '../support/fakes.dart';

/// The stored session, as auth_module hands it to the core.
final class _FakeTokenProvider implements TokenProvider {
  _FakeTokenProvider(this.token);

  String? token;
  Object? failure;

  @override
  Future<String?> currentToken() async {
    if (failure case final Object error) throw error;
    return token;
  }

  @override
  Future<String?> refreshToken() async => null;
}

/// A module's queue: counts how many times it was sent and says whether
/// something was left for later.
final class _FakeOutbox implements SyncableOutbox {
  var syncs = 0;
  var somethingLeft = false;

  @override
  String get name => 'tasks';

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<bool> sync() async {
    syncs++;
    return somethingLeft;
  }
}

void main() {
  late FakeLogger logger;
  late _FakeTokenProvider tokens;
  late _FakeOutbox outbox;
  late List<String> steps;

  setUp(() {
    logger = FakeLogger();
    tokens = _FakeTokenProvider('at-1');
    outbox = _FakeOutbox();
    steps = [];
  });
  // The background isolate starts with an empty get_it; so does each test.
  tearDown(getIt.reset);

  /// The test's composition root: only what the run uses.
  void configure() {
    steps.add('injection');
    final registry = DefaultOutboxRegistry();
    getIt
      ..registerSingleton<AppLogger>(logger)
      ..registerSingleton<TokenProvider>(tokens)
      ..registerSingleton<OutboxRegistry>(registry)
      ..registerSingleton<OutboxSyncWorker>(
        OutboxSyncWorker(registry: registry, logger: logger),
      );
  }

  /// What the session scope does: the modules sign up their queues, once,
  /// because the scope only opens if it is not open yet.
  void openSession() {
    steps.add('scope');
    final registry = getIt<OutboxRegistry>();
    if (registry.outboxes.isEmpty) registry.register(outbox);
  }

  Future<bool> run() => syncInBackground(
    configure: configure,
    initializeFirebase: () async => steps.add('firebase'),
    openSession: openSession,
  );

  test(
    'with a stored session, opens the scope and sends; with nothing for later, '
    'the task ended well',
    () async {
      expect(await run(), isTrue);

      expect(steps, ['firebase', 'injection', 'scope']);
      expect(outbox.syncs, 1);
    },
  );

  test('something left for later asks the system for a retry', () async {
    outbox.somethingLeft = true;

    expect(await run(), isFalse);
  });

  test(
    'with no stored session, nothing is sent and the queue waits for the sign-in',
    () async {
      tokens.token = null;

      expect(await run(), isTrue);

      expect(steps, isNot(contains('scope')));
      expect(outbox.syncs, 0);
    },
  );

  test('the composition runs once per isolate, even with several '
      'runs', () async {
    await run();
    await run();

    expect(steps.where((step) => step == 'injection'), hasLength(1));
    expect(outbox.syncs, 2);
  });

  test('without Firebase, the run goes on', () async {
    final result = await syncInBackground(
      configure: configure,
      initializeFirebase: () => Future.error(Exception('no configuration')),
      openSession: openSession,
      timeout: const Duration(milliseconds: 50),
    );

    expect(result, isTrue);
    expect(outbox.syncs, 1);
  });

  test('an unreadable database goes to the crash log and asks for a '
      'retry', () async {
    tokens.failure = const LocalDatabaseError('database locked');

    expect(await run(), isFalse);

    expect(logger.errors, ['background sync']);
  });
}
