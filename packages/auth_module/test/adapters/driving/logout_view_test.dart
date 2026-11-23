import 'dart:async';

import 'package:auth_module/adapters/driving/bloc/logout_bloc.dart';
import 'package:auth_module/adapters/driving/l10n/auth_module_localizations.dart';
import 'package:auth_module/adapters/driving/views/logout_view.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  late MockLogoutBloc bloc;
  late StreamController<LogoutState> states;

  setUpAll(() => registerFallbackValue(const LogoutRequested()));

  setUp(() {
    bloc = MockLogoutBloc();
    states = StreamController<LogoutState>();
    whenListen(bloc, states.stream, initialState: const LogoutInitial());
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('en'),
      localizationsDelegates: AuthModuleLocalizations.localizationsDelegates,
      supportedLocales: AuthModuleLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<LogoutBloc>.value(
          value: bloc,
          child: const LogoutView(),
        ),
      ),
    ),
  );

  Future<void> emit(WidgetTester tester, LogoutState state) async {
    states.add(state);
    await tester.pumpAndSettle();
  }

  testWidgets('tapping "Sign out" asks for the check', (tester) async {
    await show(tester);

    await tester.tap(find.text('Sign out'));

    verify(() => bloc.add(const LogoutRequested())).called(1);
  });

  testWidgets('with nothing pending, signs out without asking', (tester) async {
    await show(tester);

    await emit(tester, const LogoutCheckSuccess(pendingChanges: 0));

    expect(find.byType(AlertDialog), findsNothing);
    verify(() => bloc.add(const LogoutConfirmed())).called(1);
  });

  testWidgets('with pending changes, only signs out if the user confirms', (
    tester,
  ) async {
    await show(tester);

    await emit(tester, const LogoutCheckSuccess(pendingChanges: 2));
    expect(
      find.text(
        '2 changes made offline have not been sent yet and will be '
        'lost.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.add(const LogoutConfirmed()));

    await emit(tester, const LogoutCheckSuccess(pendingChanges: 1));
    expect(
      find.text(
        '1 change made offline has not been sent yet and will be lost.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign out anyway'));
    await tester.pumpAndSettle();
    verify(() => bloc.add(const LogoutConfirmed())).called(1);
  });

  testWidgets('unable to count, it also asks', (tester) async {
    await show(tester);

    await emit(tester, const LogoutCheckFailure());

    expect(find.byType(AlertDialog), findsOneWidget);
    verifyNever(() => bloc.add(const LogoutConfirmed()));
  });

  // Chapter 39: the system font enlarged, on a small phone. An overflow is a
  // Flutter error, which takeException returns; the chosen state is the one
  // that writes the most on screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets('at ${scale}x, the confirmation fits and "Sign out anyway" '
          'can be reached', (tester) async {
        useSmallPhone(tester, textScale: scale);
        await show(tester);
        await emit(tester, const LogoutCheckSuccess(pendingChanges: 2));

        expect(tester.takeException(), isNull);
        await expectReachable(tester, find.text('Sign out anyway'));
        await expectReachable(tester, find.text('Cancel'));
      });
    }
  });
}
