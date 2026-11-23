import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Opens the dialog through a button and stores the answer.
  Future<List<bool>> open(WidgetTester tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => answers.add(
                await showAppConfirmDialog(
                  context,
                  title: 'Sign out?',
                  message: 'Two changes have not been sent yet.',
                  confirmLabel: 'Sign out anyway',
                  cancelLabel: 'Cancel',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('confirming returns true', (tester) async {
    final answers = await open(tester);
    expect(find.text('Two changes have not been sent yet.'), findsOneWidget);

    await tester.tap(find.text('Sign out anyway'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
  });

  testWidgets('cancel or tap outside returns false', (tester) async {
    final answers = await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(answers, [false, false]);
  });

  // Chapter 39: the system font at 3.0, on a small phone (375 × 667
  // points), with a message as long as the ones the modules send. Without
  // scrolling, the dialog overflowed.
  testWidgets('with the system font at 3.0, the dialog scrolls and both '
      'buttons can be reached', (tester) async {
    tester.view
      ..physicalSize = const Size(750, 1334)
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppConfirmDialog(
                context,
                title: 'Sign out?',
                message:
                    '2 changes made offline have not been sent yet '
                    'and will be lost.',
                confirmLabel: 'Sign out anyway',
                cancelLabel: 'Cancel',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final label in ['Sign out anyway', 'Cancel']) {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.text(label));
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(667), reason: label);
    }
  });
}
