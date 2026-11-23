import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late FakeMonitor monitor;
  late FakeProbe probe;
  late DefaultConnectivityService service;

  setUp(() {
    monitor = FakeMonitor();
    probe = FakeProbe();
    service = DefaultConnectivityService(
      networkInterfaceMonitor: monitor,
      reachabilityProbe: probe,
    );
  });

  tearDown(() => service.dispose());

  test('starts as unknown', () {
    expect(service.status, ConnectivityStatus.unknown);
  });

  test('with no interface it is offline, without calling the probe', () async {
    monitor.hasInterface = false;

    expect(await service.check(), ConnectivityStatus.offline);
    expect(probe.calls, 0);
  });

  test('an interface without a backend is noInternet', () async {
    probe.reachable = false;

    expect(await service.check(), ConnectivityStatus.noInternet);
  });

  test('an interface change triggers a check', () async {
    monitor.hasInterface = false;
    await service.start();
    expect(service.status, ConnectivityStatus.offline);

    monitor.hasInterface = true;
    final online = service.statusChanges.firstWhere(
      (status) => status == ConnectivityStatus.online,
    );
    monitor.changes.add(true);

    expect(await online, ConnectivityStatus.online);
  });
}
