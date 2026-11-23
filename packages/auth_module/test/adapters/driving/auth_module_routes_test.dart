import 'package:auth_module/adapters/driving/bloc/login_bloc.dart';
import 'package:auth_module/adapters/driving/bloc/register_bloc.dart';
import 'package:auth_module/adapters/driving/views/login_view.dart';
import 'package:auth_module/adapters/driving/views/register_view.dart';
import 'package:auth_module/auth_module.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'driving_mocks.dart';

void main() {
  final getIt = GetIt.instance;

  // The Pages look up get_it; the test plays the host in a scope of its
  // own, undone at the end.
  setUp(
    () => getIt.pushNewScope(
      init: (scope) {
        final auth = MockAuthUseCase();
        when(
          () => auth.watchSignedIn(),
        ).thenAnswer((_) => const Stream.empty());
        when(
          () => auth.watchSessionExpired(),
        ).thenAnswer((_) => const Stream.empty());
        scope
          ..registerFactory<LoginBloc>(() => LoginBloc(auth: auth))
          ..registerFactory<RegisterBloc>(() => RegisterBloc(auth: auth))
          // The sign-in screen also reads the session state (chapter 29).
          ..registerLazySingleton<SessionBloc>(
            () => SessionBloc(auth: auth),
            dispose: (bloc) => bloc.close(),
          );
      },
    ),
  );
  tearDown(() async => getIt.popScope());

  testWidgets('names follow [module].[screen] and paths '
      '/[module]/[screen]', (tester) async {
    final router = GoRouter(
      initialLocation: '/auth/login',
      routes: authModuleRoutes,
    );
    addTearDown(router.dispose);

    expect(router.namedLocation(AuthRoutes.login), '/auth/login');
    expect(router.namedLocation(AuthRoutes.register), '/auth/register');
    expect(authModuleRoutes.clear, throwsUnsupportedError);
  });

  testWidgets('from sign-in, "Create an account" opens sign-up, and going '
      'back returns to sign-in', (tester) async {
    final router = GoRouter(
      initialLocation: '/auth/login',
      routes: authModuleRoutes,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AuthModuleLocalizations.localizationsDelegates,
        supportedLocales: AuthModuleLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    expect(find.byType(LoginView), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterView), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LoginView), findsOneWidget);
  });
}
