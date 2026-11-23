import 'dart:ui' show DartPluginRegistrant;

import 'package:adapter_sync_workmanager/adapter_sync_workmanager.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import 'app_config.dart';
import 'boot.dart' show bootStepTimeout, initializeFirebaseApp;
import 'firebase_options.dart';
import 'dependency_injection.dart';

/// The app's second entry point (chapter 10). The operating system calls
/// it in an isolate of its own, with an empty `get_it`, when it decides to
/// run the periodic sync the boot scheduled. The adapter connects it to
/// workmanager; the host never imports workmanager.
@pragma('vm:entry-point')
void outboxSyncDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  runWorkmanagerSyncTask(() {
    final config = AppConfig.forBackground();
    return syncInBackground(
      // The same Firebase options as the open app (chapter 38).
      initializeFirebase: () =>
          initializeFirebaseApp(firebaseOptionsFor(config.flavor)),
      configure: () => configureDependencies(config),
    );
  });
}

/// A background run. Returns whether the task ended well, which is what
/// workmanager passes on to the system; the worker answers the opposite
/// question, "was something left for later?", and the inversion lives only here.
///
/// The same composition functions as `main`, once per isolate: the
/// system may run several executions in the same isolate. The functions
/// are parameters for the tests.
Future<bool> syncInBackground({
  required void Function() configure,
  Future<void> Function() initializeFirebase = initializeFirebaseApp,
  void Function() openSession = openSessionScope,
  Duration timeout = bootStepTimeout,
}) async {
  if (!getIt.isRegistered<OutboxSyncWorker>()) {
    // Without Firebase, the crash log writes to the console, as at boot.
    try {
      await initializeFirebase().timeout(timeout);
    } on Exception {
      // The app goes on, and the open app's boot already logs the reason.
    }
    configure();
    try {
      await getIt.allReady(timeout: timeout);
    } on WaitingTimeOutException {
      // Goes on with what got ready; whatever is missing fails further on
      // and is logged.
    }
  }

  final logger = getIt<AppLogger>();
  try {
    // With no stored session, including after an expiry, the queue waits
    // for the next sign-in: there is nothing to retry now.
    if (await getIt<TokenProvider>().currentToken() == null) return true;

    openSession();
    final somethingLeft = await getIt<OutboxSyncWorker>().run();
    return !somethingLeft;
  } on LocalDatabaseError catch (error, stackTrace) {
    logger.error('background sync', error, stackTrace);
    return false;
  }
}
