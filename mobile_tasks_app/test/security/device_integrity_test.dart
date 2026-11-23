import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/l10n/mobile_tasks_localizations.dart';
import 'package:mobile_tasks_app/security/device_integrity.dart';

import '../support/fakes.dart';

void main() {
  late FakeLogger logger;
  late int jailbreakChecks;

  setUp(() {
    logger = FakeLogger();
    jailbreakChecks = 0;
  });

  Future<bool> check({
    bool real = true,
    bool jailBroken = false,
    Object? failure,
  }) => deviceCompromised(
    logger: logger,
    isRealDevice: () async {
      if (failure != null) throw failure;
      return real;
    },
    isJailBroken: () async {
      jailbreakChecks++;
      return jailBroken;
    },
  );

  test('emulators and simulators are left out', () async {
    expect(await check(real: false, jailBroken: true), isFalse);
    expect(jailbreakChecks, 0);
  });

  test('a real rooted or jailbroken device is flagged and '
      'logged', () async {
    expect(await check(), isFalse);
    expect(await check(jailBroken: true), isTrue);
    expect(logger.logs, ['device integrity: root or jailbreak']);
  });

  test('when in doubt, no notice', () async {
    expect(await check(failure: PlatformException(code: 'x')), isFalse);
    expect(logger.errors, ['device integrity']);
  });

  testWidgets(
    'the notice appears at the top, does not block the screen, and leaves when '
    'dismissed',
    (tester) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates:
              MobileTasksLocalizations.localizationsDelegates,
          supportedLocales: MobileTasksLocalizations.supportedLocales,
          scaffoldMessengerKey: messenger,
          home: Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => taps++,
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      );

      showDeviceIntegrityNotice(messenger.currentState!);
      await tester.pumpAndSettle();
      expect(find.textContaining('rooted or jailbroken'), findsOneWidget);

      await tester.tap(find.text('Save'));
      expect(taps, 1);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.textContaining('rooted or jailbroken'), findsNothing);
    },
  );
}
