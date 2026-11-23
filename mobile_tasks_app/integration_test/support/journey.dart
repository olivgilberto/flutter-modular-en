import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/app_config.dart';
import 'package:mobile_tasks_app/main_common.dart';

// The steps the integration tests repeat (chapter 39). Each file in
// integration_test/ runs on an app installed from scratch: the script
// uninstalls the app before each one, and each test clears the dev_backend.

/// The whole app, as main_dev.dart builds it, with mainCommon's three test
/// exceptions: no Firebase, no global handlers, and no tracking
/// request.
Future<void> startApp(WidgetTester tester) async {
  await mainCommon(
    Flavor.dev,
    withFirebase: false,
    withErrorHandlers: false,
    withTrackingRequest: false,
  );
  await tester.pump();
}

/// Pumps frames until [finder] finds something. pumpAndSettle does not
/// work here: with the real network and database, there is always an
/// indicator spinning or a live timer, and it would wait forever.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => _pumpWhile(
  tester,
  () => finder.evaluate().isEmpty,
  'did not appear: $finder',
  timeout,
);

/// The opposite: pumps until [finder] finds nothing anymore.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => _pumpWhile(
  tester,
  () => finder.evaluate().isNotEmpty,
  'did not go away: $finder',
  timeout,
);

Future<void> _pumpWhile(
  WidgetTester tester,
  bool Function() waiting,
  String failure,
  Duration timeout,
) async {
  final end = DateTime.now().add(timeout);
  while (waiting()) {
    if (DateTime.now().isAfter(end)) {
      fail('in ${timeout.inSeconds} s, $failure');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps frames until [condition] is true. For what only the server
/// knows, such as a task that got there.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(end)) {
      fail('in ${timeout.inSeconds} s, it did not happen: $description');
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// The first opening: the language, and the sign-in screen.
Future<void> choosePortuguese(WidgetTester tester) async {
  await pumpUntil(tester, find.text('English'));
  await tester.tap(find.text('English'));
  await pumpUntil(tester, find.text('Sign in to your account'));
}

/// Creates an account with an email no earlier test used and waits for the
/// task list, empty.
Future<String> register(WidgetTester tester) async {
  final email = 'ana.${DateTime.now().millisecondsSinceEpoch}@example.com';
  await tapVisible(tester, find.text('Create an account'));
  await pumpUntil(tester, find.text('Create your account'));
  await tester.enterText(field('Name'), 'Ana');
  await tester.enterText(field('Email'), email);
  await tester.enterText(field('Password (at least'), password);
  await tapVisible(tester, find.text('Create account'));
  await pumpUntil(tester, find.text('No tasks here'));
  return email;
}

/// A password that passes the chapter 20 policy.
const password = 'correct-horse-battery-staple';

/// Writes a task in the field at the top of the list and taps "Add".
Future<void> createTask(WidgetTester tester, String title) async {
  await tester.enterText(field('New task'), title);
  await tester.tap(find.byTooltip('Add'));
  await pumpUntil(tester, taskTile(title));
}

/// The list row with the task [title]. Not the loose text: the field at the
/// top may also be showing the same title.
Finder taskTile(String title) => find.widgetWithText(CheckboxListTile, title);

/// Scrolls to [finder] and taps it: with the keyboard open, a form's button
/// may be off screen, and the tap would land somewhere else.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

/// The text field whose label starts with [label].
Finder field(String label) => find.ancestor(
  of: find.textContaining(label),
  matching: find.byType(TextField),
);
