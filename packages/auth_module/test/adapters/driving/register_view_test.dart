import 'package:auth_module/adapters/driving/bloc/register_bloc.dart';
import 'package:auth_module/adapters/driving/l10n/auth_module_localizations.dart';
import 'package:auth_module/adapters/driving/views/register_view.dart';
import 'package:auth_module/domain/auth_failure.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  for (final (state, message) in [
    (
      const RegisterSubmitFailure(EmailAlreadyRegisteredFailure()),
      'This email already has an account. Go back and sign in with it.',
    ),
    (
      const RegisterSubmitFailure(WeakPasswordFailure()),
      'Choose another password: at least 15 characters, '
          'and not a well-known one.',
    ),
  ]) {
    testWidgets('shows the sign-up message for '
        '${state.failure.runtimeType}', (tester) async {
      final bloc = MockRegisterBloc();
      whenListen(
        bloc,
        const Stream<RegisterState>.empty(),
        initialState: state,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates:
              AuthModuleLocalizations.localizationsDelegates,
          supportedLocales: AuthModuleLocalizations.supportedLocales,
          home: BlocProvider<RegisterBloc>.value(
            value: bloc,
            child: const RegisterView(),
          ),
        ),
      );

      expect(find.text(message), findsOneWidget);
    });
  }

  // Chapter 39: the system font enlarged, on a small phone, with the
  // longest message on the screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets(
        'at ${scale}x, nothing overflows and "Create account" can be reached',
        (tester) async {
          useSmallPhone(tester, textScale: scale);
          final bloc = MockRegisterBloc();
          whenListen(
            bloc,
            const Stream<RegisterState>.empty(),
            initialState: const RegisterSubmitFailure(WeakPasswordFailure()),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: const Locale('en'),
              localizationsDelegates:
                  AuthModuleLocalizations.localizationsDelegates,
              supportedLocales: AuthModuleLocalizations.supportedLocales,
              home: BlocProvider<RegisterBloc>.value(
                value: bloc,
                child: const RegisterView(),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          await expectReachable(tester, find.text('Create account'));
        },
      );
    }
  });
}
