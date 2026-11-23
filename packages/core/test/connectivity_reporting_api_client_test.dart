import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// The state controlled by the test, with the checks counted.
final class _Connectivity implements ConnectivityService {
  _Connectivity(this.status);

  @override
  ConnectivityStatus status;
  var checks = 0;

  @override
  Stream<ConnectivityStatus> get statusChanges => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<ConnectivityStatus> check() async {
    checks++;
    return status;
  }

  @override
  Future<void> dispose() async {}
}

/// Answers or throws whatever the test says, in any method.
final class _Api implements ApiClient {
  Object? answer;
  Object? error;

  Future<Object?> _reply() async {
    if (error case final error?) throw error;
    return answer;
  }

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

void main() {
  late _Api inner;

  setUp(() => inner = _Api());

  ConnectivityReportingApiClient over(ConnectivityService connectivity) =>
      ConnectivityReportingApiClient(
        inner: inner,
        connectivityService: connectivity,
      );

  const unreachable = ApiError(ApiErrorKind.unreachable);
  const rejected = ApiError(ApiErrorKind.rejected, statusCode: 409);

  test('online, a request that did not arrive asks for a check, and the '
      'error goes up unchanged', () async {
    final connectivity = _Connectivity(ConnectivityStatus.online);
    final api = over(connectivity);
    inner.error = unreachable;

    for (final call in <Future<Object?> Function()>[
      () => api.get('/a'),
      () => api.post('/a'),
      () => api.put('/a'),
      () => api.patch('/a'),
      () => api.delete('/a'),
    ]) {
      await expectLater(call(), throwsA(same(unreachable)));
    }

    expect(connectivity.checks, 5);
  });

  test('with no connection to the backend, any response asks for a check; '
      'a transport failure does not', () async {
    final connectivity = _Connectivity(ConnectivityStatus.noInternet);
    final api = over(connectivity);

    inner.answer = {'ok': true};
    expect(await api.get('/a'), {'ok': true});
    inner.error = rejected;
    await expectLater(api.patch('/a'), throwsA(same(rejected)));
    expect(connectivity.checks, 2);

    inner.error = unreachable;
    await expectLater(api.get('/a'), throwsA(same(unreachable)));
    expect(connectivity.checks, 2);
  });

  test(
    'online and answering, or with no state yet, nothing is checked',
    () async {
      final online = _Connectivity(ConnectivityStatus.online);
      inner.answer = 'ok';
      await over(online).get('/a');
      inner.error = rejected;
      await expectLater(over(online).get('/a'), throwsA(same(rejected)));
      expect(online.checks, 0);

      // Before start(), as in the background.
      final unknown = _Connectivity(ConnectivityStatus.unknown);
      inner.error = unreachable;
      await expectLater(over(unknown).get('/a'), throwsA(same(unreachable)));
      expect(unknown.checks, 0);
    },
  );

  test(
    'with the real service: a backend that goes down becomes noInternet, '
    'and one that comes back becomes online, with no interface change',
    () async {
      final probe = FakeProbe();
      final connectivity = DefaultConnectivityService(
        networkInterfaceMonitor: FakeMonitor(),
        reachabilityProbe: probe,
        // Long: only the requests trigger checks in this test.
        minRecheckDelay: const Duration(hours: 1),
      );
      addTearDown(connectivity.dispose);
      final seen = <ConnectivityStatus>[];
      connectivity.statusChanges.listen(seen.add);
      await connectivity.start();
      final api = over(connectivity);

      probe.reachable = false;
      inner.error = unreachable;
      await expectLater(api.put('/a'), throwsA(same(unreachable)));
      await pumpEventQueue();
      expect(connectivity.status, ConnectivityStatus.noInternet);

      probe.reachable = true;
      inner
        ..error = null
        ..answer = {'version': 1};
      await api.put('/a');
      await pumpEventQueue();

      expect(seen, [
        ConnectivityStatus.online,
        ConnectivityStatus.noInternet,
        ConnectivityStatus.online,
      ]);
    },
  );
}
