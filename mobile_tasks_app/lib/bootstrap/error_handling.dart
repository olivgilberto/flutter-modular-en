import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

import 'dependency_injection.dart';

/// Boot step 3, after `WidgetsFlutterBinding.ensureInitialized()` and
/// before dependency injection, so it also covers failures of the startup
/// itself (chapter 14). The user never sees a technical screen or the
/// gray rectangle of release mode.
void installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // still on the console in debug
    reportUncaughtError(details.exception, details.stack ?? StackTrace.current);
  };
  WidgetsBinding.instance.platformDispatcher.onError = reportUncaughtError;
  // Visual only and with no text: it can be built without localization.
  ErrorWidget.builder = (_) => const AppErrorPlaceholder();
}

/// The common destination of both handlers. Public for the tests: in
/// flutter_test, the `platformDispatcher.onError` setter does not keep the value.
///
/// The handlers are born before injection, so the AppLogger may not exist
/// yet.
@visibleForTesting
bool reportUncaughtError(Object error, StackTrace stack) {
  if (getIt.isRegistered<AppLogger>()) {
    getIt<AppLogger>().fatal(error, stack);
  } else {
    debugPrint('$error\n$stack');
  }
  return true; // handled: does not propagate
}
