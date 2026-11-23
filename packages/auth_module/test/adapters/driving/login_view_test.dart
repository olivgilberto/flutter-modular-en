import 'package:auth_module/adapters/driving/bloc/login_bloc.dart';
import 'package:auth_module/adapters/driving/l10n/auth_module_localizations.dart';
import 'package:auth_module/adapters/driving/session/session_bloc.dart';
import 'package:auth_module/adapters/driving/views/login_view.dart';
import 'package:auth_module/domain/auth_failure.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  late MockLoginBloc bloc;

  setUpAll(
    () => registerFallbackValue(const LoginSubmitted(email: '', password: '')),
  );

  setUp(() => bloc = MockLoginBloc());

  /// The View receives a mocked Bloc in a fixed state: no get_it, no use
  /// case, no network.
  Future<void> show(
    WidgetTester tester,
    LoginState state, {
    SessionExpiredWithPendingChanges? expiredSession,
    VoidCallback? onDiscard,
  }) async {
    whenListen(bloc, const Stream<LoginState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AuthModuleLocalizations.localizationsDelegates,
        supportedLocales: AuthModuleLocalizations.supportedLocales,
        home: BlocProvider<LoginBloc>.value(
          value: bloc,
          child: LoginView(
            expiredSession: expiredSession,
            onDiscard: onDiscard,
          ),
        ),
      ),
    );
  }

  for (final (state, message) in [
    (
      const LoginSubmitFailure(InvalidCredentialsFailure()),
      'Incorrect email or password.',
    ),
    (
      const LoginSubmitFailure(WeakPasswordFailure()),
      'Incorrect email or password.',
    ),
    (
      const LoginSubmitFailure(InvalidEmailFailure()),
      'Check the email you typed.',
    ),
    (
      const LoginSubmitFailure.unavailable(),
      'We couldn\'t sign you in right now. Please try again.',
    ),
  ]) {
    testWidgets('shows "$message" for ${state.failure.runtimeType}', (
      tester,
    ) async {
      await show(tester, state);

      expect(find.text(message), findsOneWidget);
      // Trying again means tapping "Sign in" once more.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  }

  testWidgets('while submitting, the buttons are disabled', (tester) async {
    await show(tester, const LoginSubmitInProgress());

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
  });

  testWidgets('"Sign in" sends the text as typed', (tester) async {
    await show(tester, const LoginInitial());

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      ' Ana@Example.com ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      strongPassword,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));

    final event =
        verify(() => bloc.add(captureAny())).captured.single as LoginSubmitted;
    expect(event.email, ' Ana@Example.com ');
    expect(event.password, strongPassword);
  });

  group('after an expired session with unsent changes', () {
    testWidgets(
      'the screen says how many there are and offers to discard them',
      (tester) async {
        await show(
          tester,
          const LoginInitial(),
          expiredSession: const SessionExpiredWithPendingChanges(
            pendingChanges: 2,
          ),
        );

        expect(
          find.text(
            'Your session has expired, and there are 2 changes not sent yet. '
            'Sign in again to send them, or discard them.',
          ),
          findsOneWidget,
        );
        expect(find.text('Discard changes'), findsOneWidget);
      },
    );

    testWidgets('discarding only happens after confirmation', (tester) async {
      var discarded = 0;
      await show(
        tester,
        const LoginInitial(),
        expiredSession: const SessionExpiredWithPendingChanges(
          pendingChanges: null,
        ),
        onDiscard: () => discarded++,
      );
      expect(
        find.textContaining('there may be changes not sent yet'),
        findsOneWidget,
      );

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(discarded, 0);

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(discarded, 1);
    });

    testWidgets('with no expired session, no notice', (tester) async {
      await show(tester, const LoginInitial());

      expect(find.text('Discard changes'), findsNothing);
    });
  });

  // Chapter 39: the system font enlarged, on a small phone. An overflow is a
  // Flutter error, which takeException returns; the chosen state is the one
  // that writes the most on screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets(
        'at ${scale}x, nothing overflows and "Sign in" can be reached',
        (tester) async {
          useSmallPhone(tester, textScale: scale);
          await show(
            tester,
            const LoginSubmitFailure.unavailable(),
            expiredSession: const SessionExpiredWithPendingChanges(
              pendingChanges: 2,
            ),
          );

          expect(tester.takeException(), isNull);
          await expectReachable(tester, find.text('Sign in'));
          await expectReachable(tester, find.text('Create an account'));
        },
      );
    }
  });
}
