import 'dart:async';

import 'package:core/core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// [AppLogger] with Firebase Crashlytics:
///
/// | Port                        | Crashlytics                              |
/// |-----------------------------|------------------------------------------|
/// | `log(message)`              | `log(message)`                           |
/// | `error(reason, error, st)`  | `recordError(error, st, reason: reason)` |
/// | `fatal(error, st)`          | `recordError(error, st, fatal: true)`    |
/// | `setUserId(id)`             | `setUserIdentifier(id ?? '')`            |
///
/// While no Firebase app has been initialized (configuration files not
/// generated yet, or boot step 1 failed), it writes to the console instead
/// of sending. In debug, it also echoes to the console.
final class CrashlyticsAppLogger implements AppLogger {
  CrashlyticsAppLogger({FirebaseCrashlytics? crashlytics})
    : _injected = crashlytics;

  final FirebaseCrashlytics? _injected;

  /// Resolved on every call: `FirebaseCrashlytics.instance` throws before
  /// `Firebase.initializeApp()`.
  FirebaseCrashlytics? get _crashlytics =>
      _injected ??
      (Firebase.apps.isEmpty ? null : FirebaseCrashlytics.instance);

  @override
  void log(String message) {
    final crashlytics = _crashlytics;
    if (kDebugMode || crashlytics == null) debugPrint('[log] $message');
    if (crashlytics != null) unawaited(crashlytics.log(message));
  }

  @override
  void error(String reason, Object error, StackTrace stackTrace) {
    final crashlytics = _crashlytics;
    if (kDebugMode || crashlytics == null) {
      debugPrint('[error] $reason: $error\n$stackTrace');
    }
    if (crashlytics != null) {
      unawaited(crashlytics.recordError(error, stackTrace, reason: reason));
    }
  }

  @override
  void fatal(Object error, StackTrace stackTrace) {
    final crashlytics = _crashlytics;
    if (kDebugMode || crashlytics == null) {
      debugPrint('[fatal] $error\n$stackTrace');
    }
    if (crashlytics != null) {
      unawaited(crashlytics.recordError(error, stackTrace, fatal: true));
    }
  }

  @override
  void setUserId(String? opaqueId) {
    final crashlytics = _crashlytics;
    if (crashlytics != null) {
      unawaited(crashlytics.setUserIdentifier(opaqueId ?? ''));
    }
  }
}
