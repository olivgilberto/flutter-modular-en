import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

/// Logs every screen the user sees, by the route name in the
/// `[owner].[screen]` format (chapter 7). The host does the logging; no
/// module logs its own screen (chapter 14).
///
/// An observer serves only one navigator. The host creates one for the
/// `GoRouter` and another for each `ShellRoute`, which has its own
/// navigator: without it, the frame's screens would never be seen.
final class ScreenViewObserver extends NavigatorObserver {
  ScreenViewObserver(this._analytics);

  final AppAnalytics _analytics;

  /// Screens only: a dialog is a route, but not a screen. A route with no
  /// name does not say which screen it is and is left out.
  void _record(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (route is PageRoute && name != null) {
      unawaited(_analytics.logScreenView(name));
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);

  /// Going back is also seeing a screen: the one that reappears.
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(previousRoute);
}
