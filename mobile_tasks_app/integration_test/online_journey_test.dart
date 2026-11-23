import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/dev_backend_client.dart';
import 'support/journey.dart';

/// The happy path, on the device, with everything real: SQLCipher, secure
/// storage, the preferences, and HTTP to the dev_backend (chapter 39).
/// Nothing here is mocked; what the test checks on the server, it reads
/// through GET /dev/state.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final backend = DevBackendClient();
  tearDownAll(backend.close);

  testWidgets('create, complete, and archive reach the server, and the next '
      'sign-in brings the list from there', (tester) async {
    await backend.reset();
    await startApp(tester);

    await choosePortuguese(tester);
    final email = await register(tester);

    await createTask(tester, 'Buy bread');
    await createTask(tester, 'Pay the electricity bill');
    await pumpUntilTrue(
      tester,
      () async =>
          await backend.statusOf('Buy bread') == 'open' &&
          await backend.statusOf('Pay the electricity bill') == 'open',
      description: 'the two open tasks on the server',
    );

    // Complete: the row's checkbox.
    await tester.tap(
      find.descendant(
        of: taskTile('Buy bread'),
        matching: find.byType(Checkbox),
      ),
    );
    await pumpUntilTrue(
      tester,
      () async => await backend.statusOf('Buy bread') == 'done',
      description: '"Buy bread" done on the server',
    );

    // Archive: through the edit screen, with the confirmation.
    await tester.tap(
      find.descendant(
        of: taskTile('Pay the electricity bill'),
        matching: find.byTooltip('Edit'),
      ),
    );
    await pumpUntil(tester, find.text('Archive'));
    await tapVisible(tester, find.text('Archive'));
    await pumpUntil(tester, find.text('Archive task?'));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Archive'),
      ),
    );
    await pumpUntilTrue(
      tester,
      () async =>
          await backend.statusOf('Pay the electricity bill') == 'archived',
      description: '"Pay the electricity bill" archived on the server',
    );
    await pumpUntil(tester, find.text('Tasks'));

    // Sign out: with nothing pending, no question. Logout erases the
    // device's data (chapter 29).
    await tapVisible(tester, find.text('Sign out'));
    await pumpUntil(tester, find.text('Sign in to your account'));

    // Sign in again: the first list comes from the server.
    await tester.enterText(field('Email'), email);
    await tester.enterText(field('Password'), password);
    await tapVisible(tester, find.text('Sign in'));
    // The done task appears: until the user chooses, the list shows done
    // tasks, and the logout erased the choice with the rest of the data.
    await pumpUntil(tester, taskTile('Buy bread'));
    expect(find.byTooltip('Hide completed'), findsOneWidget);

    expect(
      tester.widget<CheckboxListTile>(taskTile('Buy bread')).value,
      isTrue,
    );
    expect(taskTile('Pay the electricity bill'), findsNothing);
  });
}
