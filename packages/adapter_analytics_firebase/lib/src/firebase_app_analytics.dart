import 'package:core/core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// [AppAnalytics] with Google Analytics for Firebase. Never throws: a plugin
/// failure goes to the [AppLogger], instead of becoming an async error the
/// global handlers would record as fatal (the UseCase does not await
/// events). Without an initialized Firebase, it writes to the console.
final class FirebaseAppAnalytics implements AppAnalytics {
  FirebaseAppAnalytics({
    required AppLogger logger,
    FirebaseAnalytics? analytics,
  }) : _logger = logger,
       _injected = analytics;

  final AppLogger _logger;
  final FirebaseAnalytics? _injected;

  FirebaseAnalytics? get _analytics =>
      _injected ?? (Firebase.apps.isEmpty ? null : FirebaseAnalytics.instance);

  /// `[module]_[object]_[action]`: snake_case, at least three parts,
  /// starting with a letter.
  static final _eventName = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+){2,}$');
  static const _reservedPrefixes = ['firebase_', 'google_', 'ga_'];

  /// Used in an assert: an invalid name shows up on the first debug run,
  /// not weeks later in the Firebase console.
  static bool isValidEventName(String name) =>
      name.length <= 40 &&
      _eventName.hasMatch(name) &&
      !_reservedPrefixes.any(name.startsWith);

  @override
  Future<void> logEvent(
    String name, [
    Map<String, Object> parameters = const {},
  ]) async {
    assert(isValidEventName(name), 'Invalid event name: $name');
    final analytics = _analytics;
    if (analytics == null) {
      debugPrint('[analytics] $name $parameters');
      return;
    }
    try {
      await analytics.logEvent(
        name: name,
        parameters: parameters.isEmpty ? null : parameters,
      );
    } on Exception catch (error, stackTrace) {
      _logger.error('analytics event', error, stackTrace);
    }
  }

  @override
  Future<void> logScreenView(String screenName) async {
    final analytics = _analytics;
    if (analytics == null) {
      debugPrint('[analytics] screen $screenName');
      return;
    }
    try {
      await analytics.logScreenView(screenName: screenName);
    } on Exception catch (error, stackTrace) {
      _logger.error('analytics screen view', error, stackTrace);
    }
  }
}
