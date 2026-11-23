import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/boot.dart';

import '../support/fakes.dart';

/// The network interface, controlled by the test.
final class _Monitor implements NetworkInterfaceMonitor {
  var hasInterface = true;
  final changes = StreamController<bool>.broadcast();

  @override
  Future<bool> hasNetworkInterface() async => hasInterface;

  @override
  Stream<bool> get networkInterfaceChanges => changes.stream;
}

/// The backend, which the test can take down.
final class _Probe implements ReachabilityProbe {
  var up = true;

  @override
  Future<bool> isBackendReachable() async => up;
}

/// The app's requests, which fail while the backend is down.
final class _Api implements ApiClient {
  _Api(this._probe);

  final _Probe _probe;

  Future<Object?> _reply() async => _probe.up
      ? {'version': 1}
      : throw const ApiError(ApiErrorKind.unreachable);

  @override
  Future<Object?> get(String path, {Map<String, String>? query}) => _reply();

  @override
  Future<Object?> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) => _reply();

  @override
  Future<Object?> put(String path, {Object? body, String? idempotencyKey}) =>
      _reply();

  @override
  Future<Object?> patch(String path, {Object? body, String? idempotencyKey}) =>
      _reply();

  @override
  Future<Object?> delete(String path, {String? idempotencyKey}) => _reply();
}

/// A queue that counts the sends.
final class _Outbox implements SyncableOutbox {
  var syncs = 0;

  @override
  String get name => 'tasks';

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<bool> sync() async {
    syncs++;
    return false;
  }
}

void main() {
  late _Monitor monitor;
  late _Probe probe;
  late _Outbox outbox;
  late DefaultConnectivityService connectivity;
  late SyncOrchestrator orchestrator;

  setUp(() {
    monitor = _Monitor();
    probe = _Probe();
    outbox = _Outbox();
    final registry = DefaultOutboxRegistry()..register(outbox);
    connectivity = DefaultConnectivityService(
      networkInterfaceMonitor: monitor,
      reachabilityProbe: probe,
    );
    orchestrator = SyncOrchestrator(
      connectivityService: connectivity,
      outboxSyncWorker: OutboxSyncWorker(
        registry: registry,
        logger: FakeLogger(),
      ),
      debounce: Duration.zero,
    );
  });
  tearDown(() async {
    await orchestrator.dispose();
    await connectivity.dispose();
  });

  /// The time of the orchestrator's interval and of the send.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test('at boot, the first online check sends the queues', () async {
    startConnectivity(connectivity: connectivity, orchestrator: orchestrator);
    await settle();

    expect(connectivity.status, ConnectivityStatus.online);
    expect(outbox.syncs, 1);
  });

  test(
    'a network that drops and comes back sends again; with no network, nothing is '
    'sent',
    () async {
      startConnectivity(connectivity: connectivity, orchestrator: orchestrator);
      await settle();

      monitor.hasInterface = false;
      monitor.changes.add(false);
      await settle();
      expect(connectivity.status, ConnectivityStatus.offline);
      expect(outbox.syncs, 1);

      monitor.hasInterface = true;
      monitor.changes.add(true);
      await settle();
      expect(connectivity.status, ConnectivityStatus.online);
      expect(outbox.syncs, 2);
    },
  );

  test(
    'a backend that goes down with the interface up shows the notice, and one that '
    'comes back sends the queue without waiting for another write (chapter 35)',
    () async {
      // The same pieces, with the new check in milliseconds, instead of the
      // app's 15 seconds.
      final quick = DefaultConnectivityService(
        networkInterfaceMonitor: monitor,
        reachabilityProbe: probe,
        minRecheckDelay: const Duration(milliseconds: 30),
      );
      final quickOrchestrator = SyncOrchestrator(
        connectivityService: quick,
        outboxSyncWorker: OutboxSyncWorker(
          registry: DefaultOutboxRegistry()..register(outbox),
          logger: FakeLogger(),
        ),
        debounce: Duration.zero,
      );
      addTearDown(() async {
        await quickOrchestrator.dispose();
        await quick.dispose();
      });
      final api = ConnectivityReportingApiClient(
        inner: _Api(probe),
        connectivityService: quick,
      );
      startConnectivity(connectivity: quick, orchestrator: quickOrchestrator);
      await settle();
      expect(outbox.syncs, 1);

      // The simulator script: "stop" on the dev_backend, and a write that does
      // not get through. The interface stays up.
      probe.up = false;
      await expectLater(api.put('/v1/tasks/t-1'), throwsA(isA<ApiError>()));
      await settle();
      expect(quick.status, ConnectivityStatus.noInternet);

      // "start", with no action in the app: the new check finds the backend,
      // and the transition to online sends the queue.
      probe.up = true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(quick.status, ConnectivityStatus.online);
      expect(outbox.syncs, 2);
    },
  );
}
