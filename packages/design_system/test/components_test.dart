import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {required ThemeData theme}) => MaterialApp(
  theme: theme,
  home: Scaffold(body: child),
);

void main() {
  for (final (mode, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('the connection notice appears and is announced ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const AppConnectivityBanner(visible: true, message: 'No connection'),
          theme: theme,
        ),
      );

      expect(find.text('No connection'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('No connection')),
        isSemantics(label: 'No connection', isLiveRegion: true),
      );
    });
  }

  testWidgets('hidden, the notice takes no height and has no text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Align(
          alignment: Alignment.topCenter,
          child: AppConnectivityBanner(
            visible: false,
            message: 'No connection',
          ),
        ),
        theme: AppTheme.light,
      ),
    );

    expect(find.text('No connection'), findsNothing);
    expect(tester.getSize(find.byType(AppConnectivityBanner)).height, 0);
  });

  testWidgets('the notice is at least 48 dp tall', (tester) async {
    await tester.pumpWidget(
      _app(
        const Align(
          alignment: Alignment.topCenter,
          child: AppConnectivityBanner(visible: true, message: 'No connection'),
        ),
        theme: AppTheme.light,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AppConnectivityBanner)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the empty state shows the title and message it receives', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          message: 'Create the first task',
        ),
        theme: AppTheme.dark,
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Create the first task'), findsOneWidget);
  });

  testWidgets('the error placeholder has no text', (tester) async {
    await tester.pumpWidget(const AppErrorPlaceholder());

    expect(find.byType(Text), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });
}
