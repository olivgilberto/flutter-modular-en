import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/connectivity/connectivity_banner_host.dart';
import 'package:mobile_tasks_app/l10n/mobile_tasks_localizations.dart';

import '../support/fakes.dart';

void main() {
  late FakeConnectivityService connectivity;
  late int taps;

  setUp(() {
    connectivity = FakeConnectivityService();
    taps = 0;
  });
  tearDown(() => connectivity.dispose());

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: MobileTasksLocalizations.localizationsDelegates,
      supportedLocales: MobileTasksLocalizations.supportedLocales,
      home: ConnectivityBannerHost(
        connectivity: connectivity,
        child: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => taps++,
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    ),
  );

  bool bannerVisible(WidgetTester tester) => tester
      .widget<AppConnectivityBanner>(find.byType(AppConnectivityBanner))
      .visible;

  test(
    'there is a notice only with no interface or no answer from the backend',
    () {
      final l10n = lookupMobileTasksLocalizations(const Locale('en'));
      String? message(ConnectivityStatus status) =>
          ConnectivityBannerHost.messageFor(l10n, status);

      expect(message(ConnectivityStatus.unknown), isNull);
      expect(message(ConnectivityStatus.online), isNull);
      expect(message(ConnectivityStatus.offline), startsWith('No connection.'));
      expect(
        message(ConnectivityStatus.noInternet),
        startsWith('No access to the server.'),
      );
    },
  );

  testWidgets(
    'the notice follows the state, and the screen stays tappable with it '
    'visible',
    (tester) async {
      await pumpHost(tester);
      expect(bannerVisible(tester), isFalse);

      connectivity.emit(ConnectivityStatus.noInternet);
      await tester.pumpAndSettle();
      expect(bannerVisible(tester), isTrue);
      expect(find.textContaining('No access to the server'), findsOneWidget);

      await tester.tap(find.text('Save'));
      expect(taps, 1);

      connectivity.emit(ConnectivityStatus.offline);
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection'), findsOneWidget);

      connectivity.emit(ConnectivityStatus.online);
      await tester.pumpAndSettle();
      expect(bannerVisible(tester), isFalse);
    },
  );

  testWidgets('a state already known appears on the first build', (
    tester,
  ) async {
    connectivity = FakeConnectivityService(ConnectivityStatus.offline);
    await pumpHost(tester);

    expect(bannerVisible(tester), isTrue);
  });
}
