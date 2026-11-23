import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/security/tracking_authorization.dart';

import '../support/fakes.dart';

void main() {
  late FakeLogger logger;
  late int requests;

  setUp(() {
    logger = FakeLogger();
    requests = 0;
  });

  Future<void> run({
    bool iOS = true,
    TrackingStatus status = TrackingStatus.notDetermined,
    Object? failure,
  }) => requestTrackingAuthorization(
    logger: logger,
    isIOS: () => iOS,
    status: () async {
      if (failure != null) throw failure;
      return status;
    },
    request: () async {
      requests++;
      return TrackingStatus.denied;
    },
  );

  test('asks once, only on iOS, and only while nobody has answered', () async {
    await run(iOS: false);
    expect(requests, 0);

    await run(status: TrackingStatus.authorized);
    await run(status: TrackingStatus.denied);
    expect(requests, 0);

    await run();
    expect(requests, 1);
    expect(logger.logs, ['tracking authorization: denied']);
  });

  test('a plugin failure goes to the log and not to the app', () async {
    await run(failure: PlatformException(code: 'x'));

    expect(requests, 0);
    expect(logger.errors, ['tracking authorization']);
  });

  testWidgets('waits for the app to become active', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    var active = false;
    final future = appActive(tester.binding)..then((_) => active = true);
    await tester.pump();
    expect(active, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await future;
    expect(active, isTrue);

    // Already active, it completes right away.
    await appActive(tester.binding);
  });
}
