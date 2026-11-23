import 'dart:async';

import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/app.dart';
import 'package:mobile_tasks_app/bootstrap/app_router.dart';
import 'package:mobile_tasks_app/bootstrap/dependency_injection.dart';
import 'package:mobile_tasks_app/language/language_selection_page.dart';
import 'package:mobile_tasks_app/session/session_gate.dart';
import 'package:mobile_tasks_app/settings/app_settings.dart';
import 'package:tasks_module/tasks_module.dart';

import 'support/fakes.dart';

void main() {
  late StreamController<SessionState> sessionChanges;
  late FakeConnectivityService connectivity;
  late FakeAnalytics analytics;

  // The real auth_module, assembled by its own registration function over
  // mocked core ports: the sign-in screen needs the LoginBloc. No test here
  // reaches the network or the database.
  setUp(() {
    sessionChanges = StreamController<SessionState>.broadcast();
    connectivity = FakeConnectivityService();
    analytics = FakeAnalytics();
    getIt.pushNewScope(
      scopeName: 'test',
      init: (scope) {
        scope
          ..registerSingleton<ApiClient>(UnusedApiClient())
          ..registerSingleton<LocalDatabaseFactory>(FailingDatabaseFactory())
          ..registerSingleton<LogoutCleanerRegistry>(
            DefaultLogoutCleanerRegistry(),
          )
          ..registerSingleton<OutboxRegistry>(DefaultOutboxRegistry())
          ..registerSingleton<AppLogger>(FakeLogger())
          ..registerSingleton<AppAnalytics>(analytics);
        registerAuthModuleDependencies(scope);
        registerTasksModuleDependencies(scope);
      },
    );
  });
  tearDown(() => getIt.popScopesTill('test'));

  Future<AppSettings> settingsWith(FakePreferences preferences) =>
      AppSettings.load(
        preferences: preferences,
        logger: FakeLogger(),
        timeout: const Duration(seconds: 1),
      );

  Future<void> pumpApp(
    WidgetTester tester,
    AppSettings settings, {
    required SessionState session,
  }) async {
    // Undone in reverse order: the router before what it listens to.
    addTearDown(settings.dispose);
    final gate = SessionGate(
      initial: session,
      changes: sessionChanges.stream,
      onSignedIn: () {},
      onSignedOut: () async {},
    );
    addTearDown(gate.dispose);
    final router = createAppRouter(settings, gate, analytics: analytics);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MobileTasksApp(
        settings: settings,
        router: router,
        connectivity: connectivity,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder loginScreen() => find.text('Sign in to your account');

  testWidgets('on first open, the app asks for the language and, with no '
      'session, moves on to the sign-in', (tester) async {
    final preferences = FakePreferences();
    final settings = await settingsWith(preferences);
    await pumpApp(tester, settings, session: const SessionUnauthenticated());

    expect(find.byType(LanguageSelectionPage), findsOneWidget);
    // While there is no choice, the locale is the template ARB's, never null.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(preferences.storedLanguage, 'en');
    expect(loginScreen(), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
  });

  testWidgets('with the language and the session stored, opens straight on the '
      'task list, with the chosen theme', (tester) async {
    final settings = await settingsWith(
      FakePreferences(storedLanguage: 'en', storedThemeMode: AppThemeMode.dark),
    );
    await pumpApp(tester, settings, session: const SessionAuthenticated());

    // The tasks module's list; with no database in the test, the failure of
    // the first load, with the option to try again.
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text("Couldn't load the tasks"), findsOneWidget);
    // auth_module's sign-out button, in the screen's frame (chapter 29).
    expect(find.text('Sign out'), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.colorScheme, AppTheme.dark.colorScheme);
  });

  testWidgets(
    'the sign-in leads to the start screen, and the end of the session, back to the '
    'sign-in',
    (tester) async {
      final settings = await settingsWith(
        FakePreferences(storedLanguage: 'en'),
      );
      await pumpApp(tester, settings, session: const SessionUnauthenticated());
      expect(loginScreen(), findsOneWidget);

      sessionChanges.add(const SessionAuthenticated());
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget);

      sessionChanges.add(const SessionUnauthenticated());
      await tester.pumpAndSettle();
      expect(loginScreen(), findsOneWidget);
    },
  );

  testWidgets(
    'with no connection, the notice appears below the screen, which keeps '
    'working',
    (tester) async {
      final settings = await settingsWith(
        FakePreferences(storedLanguage: 'en'),
      );
      await pumpApp(tester, settings, session: const SessionUnauthenticated());
      expect(find.byType(AppConnectivityBanner), findsOneWidget);
      expect(find.textContaining('No connection'), findsNothing);

      connectivity.emit(ConnectivityStatus.offline);
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection'), findsOneWidget);

      // The sign-in stays tappable: the notice neither covers nor blocks the screen.
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      expect(loginScreen(), findsNothing);
      expect(find.textContaining('No connection'), findsOneWidget);

      connectivity.emit(ConnectivityStatus.online);
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection'), findsNothing);
    },
  );

  testWidgets(
    'the chosen language translates the host and the modules, and a change takes '
    'effect right away, without restarting the app',
    (tester) async {
      final preferences = FakePreferences(storedLanguage: 'en');
      final settings = await settingsWith(preferences);
      await pumpApp(tester, settings, session: const SessionAuthenticated());

      // In English: the tasks module's list, auth_module's button, and the
      // host's notice.
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text("Couldn't load the tasks"), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      connectivity.emit(ConnectivityStatus.offline);
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection.'), findsOneWidget);

      // A settings screen in any module only writes through the port; the
      // host listens and applies it.
      await preferences.saveLanguageCode('pt-BR');
      await tester.pumpAndSettle();

      expect(find.text('Tarefas'), findsOneWidget);
      expect(find.text('Não foi possível carregar as tarefas'), findsOneWidget);
      expect(find.text('Sair'), findsOneWidget);
      expect(find.textContaining('Sem conexão.'), findsOneWidget);
      // Flutter's own strings too: the global delegate follows the locale.
      final context = tester.element(find.text('Tarefas'));
      expect(Localizations.localeOf(context), const Locale('pt', 'BR'));
      expect(MaterialLocalizations.of(context).cancelButtonLabel, 'Cancelar');
    },
  );

  testWidgets(
    'the system language never comes in: with another language on the '
    'device and nothing chosen, the app asks, in English',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pt', 'BR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final settings = await settingsWith(FakePreferences());
      await pumpApp(tester, settings, session: const SessionUnauthenticated());

      expect(find.byType(LanguageSelectionPage), findsOneWidget);
      final context = tester.element(find.byType(LanguageSelectionPage));
      expect(Localizations.localeOf(context), const Locale('en'));
    },
  );

  testWidgets(
    'every screen viewed is logged by its route name, including those '
    'in the frame, which has its own navigator',
    (tester) async {
      final settings = await settingsWith(FakePreferences());
      await pumpApp(tester, settings, session: const SessionUnauthenticated());
      expect(analytics.screens, ['app.language']);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      expect(analytics.screens, [
        'app.language',
        'auth.login',
        'auth.register',
      ]);

      // The task list lives in the host's ShellRoute.
      sessionChanges.add(const SessionAuthenticated());
      await tester.pumpAndSettle();
      expect(analytics.screens.last, 'tasks.list');
    },
  );
}
