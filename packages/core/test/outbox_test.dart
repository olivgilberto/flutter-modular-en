import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('DefaultOutboxRegistry', () {
    test('sums the pending operations of all queues', () async {
      final registry = DefaultOutboxRegistry()
        ..register(FakeOutbox('tasks', pending: 2))
        ..register(FakeOutbox('notes', pending: 3));

      expect(await registry.pendingOperations(), 5);
    });

    test('unregisterAll empties the registry', () async {
      final registry = DefaultOutboxRegistry()
        ..register(FakeOutbox('tasks', pending: 2))
        ..unregisterAll();

      expect(registry.outboxes, isEmpty);
      expect(await registry.pendingOperations(), 0);
    });
  });

  group('OutboxSyncWorker', () {
    late DefaultOutboxRegistry registry;
    late FakeLogger logger;
    late OutboxSyncWorker worker;

    setUp(() {
      registry = DefaultOutboxRegistry();
      logger = FakeLogger();
      worker = OutboxSyncWorker(registry: registry, logger: logger);
    });

    test('with no queues, nothing is left for later', () async {
      expect(await worker.run(), isFalse);
    });

    test('a queue with something to resend asks for a new round', () async {
      registry
        ..register(FakeOutbox('tasks'))
        ..register(FakeOutbox('notes', result: true));

      expect(await worker.run(), isTrue);
    });

    test(
      'a LocalDatabaseError in one queue does not stop the others',
      () async {
        final broken = FakeOutbox(
          'tasks',
          throws: const LocalDatabaseError('corrupted'),
        );
        final healthy = FakeOutbox('notes');
        registry
          ..register(broken)
          ..register(healthy);

        expect(await worker.run(), isTrue);
        expect(healthy.calls, 1);
        expect(logger.errors, ['outbox tasks']);
      },
    );

    test('a bug is rethrown after the other queues finish', () async {
      final buggy = FakeOutbox('tasks', throws: StateError('bug'));
      final healthy = FakeOutbox('notes');
      registry
        ..register(buggy)
        ..register(healthy);

      await expectLater(worker.run(), throwsA(isA<StateError>()));
      expect(healthy.calls, 1);
      expect(logger.errors, isEmpty);
    });
  });
}
