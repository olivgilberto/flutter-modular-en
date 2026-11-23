import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/dev_backend_client.dart';
import 'support/journey.dart';

/// The tasks module's offline flow, on the device (chapter 39): the backend
/// goes down through the control port, the write stays on the device and in
/// the queue, the notice appears, and the queue goes out on its own when the
/// backend comes back. The API port really closes: the app sees the
/// connection refused, as with a server that is down.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final backend = DevBackendClient();
  tearDownAll(() async {
    // If the test fails halfway, the backend does not stay down for the
    // next file.
    await backend.start();
    backend.close();
  });

  testWidgets(
    'with no server, the task stays on the device and goes out when it '
    'comes back',
    (tester) async {
      await backend.reset();
      await startApp(tester);
      await choosePortuguese(tester);
      await register(tester);

      await backend.stop();
      await createTask(tester, 'Call the dentist');

      // The send fails, the ConnectivityReportingApiClient asks for a check,
      // and the probe does not reach the server: the host's notice (chapter 35).
      await pumpUntil(tester, find.textContaining('No access to the server'));
      expect(taskTile('Call the dentist'), findsOneWidget);

      await backend.start();
      // Nobody touches anything: the ConnectivityService's next check, from
      // 15 s on, finds the server, and the SyncOrchestrator sends the queue.
      await pumpUntilTrue(
        tester,
        () async => await backend.statusOf('Call the dentist') == 'open',
        description: 'the task made with no server reached it',
        timeout: const Duration(seconds: 90),
      );
      await pumpUntilGone(
        tester,
        find.textContaining('No access to the server'),
      );
    },
  );
}
