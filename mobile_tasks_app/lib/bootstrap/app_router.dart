import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:tasks_module/tasks_module.dart';

import '../home/app_frame.dart';
import '../language/language_selection_page.dart';
import '../observability/screen_view_observer.dart';
import '../session/session_gate.dart';
import '../settings/app_settings.dart';

/// The host's own routes, in the modules' `[owner].[screen]` format.
abstract final class HostRoutes {
  static const home = 'app.home';
  static const homePath = '/';
  static const language = 'app.language';
  static const languagePath = '/language';
}

/// The app's router: the host's routes and the lists exported by the
/// modules, spread. It re-evaluates the redirect whenever the settings or
/// the session change. With [analytics], it logs every screen viewed
/// (chapter 38), in the main navigator and in the frame's.
GoRouter createAppRouter(
  AppSettings settings,
  SessionGate session, {
  AppAnalytics? analytics,
}) => GoRouter(
  initialLocation: HostRoutes.homePath,
  observers: [?_screenViews(analytics)],
  refreshListenable: Listenable.merge([settings, session]),
  redirect: (context, state) => appRedirect(
    state.uri,
    languageChosen: settings.locale != null,
    authenticated: session.authenticated,
  ),
  routes: [
    // The start screen for whoever signed in is the task list (chapter 34).
    GoRoute(
      name: HostRoutes.home,
      path: HostRoutes.homePath,
      redirect: (context, state) => TaskRoutes.listPath,
    ),
    GoRoute(
      name: HostRoutes.language,
      path: HostRoutes.languagePath,
      builder: (context, state) =>
          LanguageSelectionPage(onSelected: settings.chooseLanguage),
    ),
    ...authModuleRoutes,
    // The tasks module's screens, inside the host's frame.
    ShellRoute(
      observers: [?_screenViews(analytics)],
      builder: (context, state, child) => AppFrame(child: child),
      routes: tasksModuleRoutes,
    ),
  ],
);

/// A new observer for each navigator: an observer serves only one.
ScreenViewObserver? _screenViews(AppAnalytics? analytics) =>
    analytics == null ? null : ScreenViewObserver(analytics);

/// Boot step 10, as a pure function: the rules in order, the first one
/// that applies decides.
String? appRedirect(
  Uri uri, {
  required bool languageChosen,
  required bool authenticated,
}) {
  final atLanguage = uri.path == HostRoutes.languagePath;

  // 1. Language: nothing opens before the choice, not even an external link.
  //    The original destination comes along and is resumed afterwards.
  if (!languageChosen) {
    if (atLanguage) return null;
    return _withDestination(HostRoutes.languagePath, uri);
  }
  if (atLanguage) return _safeDestination(uri.queryParameters['from']);

  // 2. Session: without one, only auth_module's screens open, and the
  //    destination comes along, as with the language. With one, the sign-in
  //    screens have nothing left to do, and the user goes where they were going.
  final atAuth = uri.path.startsWith('${AuthRoutes.prefix}/');
  if (!authenticated) {
    if (atAuth) return null;
    return _withDestination(AuthRoutes.loginPath, uri);
  }
  if (atAuth) return _safeDestination(uri.queryParameters['from']);

  return null;
}

/// Leads to [path] with the original destination in the `from` parameter.
String _withDestination(String path, Uri destination) => Uri(
  path: path,
  queryParameters: {'from': destination.toString()},
).toString();

/// Internal paths only: a `from` with a scheme or with `//` would lead to
/// another host, and falls back to the start screen.
String _safeDestination(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) {
    return HostRoutes.homePath;
  }
  return from;
}
