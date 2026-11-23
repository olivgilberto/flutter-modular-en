import 'dart:async';

import 'package:core/core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get_it/get_it.dart';

import '../settings/app_settings.dart';
import 'dependency_injection.dart' show getIt;
import 'error_handling.dart';

/// The maximum time for each async step. The boot never waits for the
/// network or a plugin without a limit: once the time is up, it takes the fallback path.
const bootStepTimeout = Duration(seconds: 5);

/// Steps 1 to 8 of the boot sequence (section 25.1). Step 9 is `runApp`, in
/// `mainCommon`; step 10, the router's redirect. The functions are
/// parameters so the tests can swap Firebase, the handlers, the composition
/// root, and the scheduling; the composition root has no default because it
/// depends on the flavor (chapter 26).
Future<AppSettings> boot({
  Future<void> Function() initializeFirebase = initializeFirebaseApp,
  void Function() installErrorHandlers = installGlobalErrorHandlers,
  required void Function() configure,
  Future<void> Function() scheduleSync = _schedulePeriodicSync,
  Duration timeout = bootStepTimeout,
}) async {
  // 1. Firebase, with the flavor's options (chapter 38). A flavor with no
  //    Firebase project yet fails here; the app goes on, and the Firebase
  //    adapters write to the console.
  Object? firebaseFailure;
  try {
    await initializeFirebase().timeout(timeout);
  } on Exception catch (error) {
    firebaseFailure = error;
  }

  // 2. App Tracking Transparency: the request only appears with the app
  //    active, so it runs after runApp (chapter 38, in mainCommon).

  // 3. Global error handlers.
  installErrorHandlers();

  // 4. Dependency injection and waiting for the async services.
  configure();
  final logger = getIt<AppLogger>();
  try {
    await getIt.allReady(timeout: timeout);
  } on WaitingTimeOutException catch (error) {
    logger.log('boot: services not ready: ${error.notReadyYet}');
  }
  if (firebaseFailure != null) {
    logger.log('boot: Firebase unavailable (${firebaseFailure.runtimeType})');
  }

  // 4, end. Sync with the app closed (chapter 32). The open app's,
  //    SyncOrchestrator.start(), comes in with connectivity in chapter 33.
  //    A failure here does not stop the app from opening: the queue goes
  //    out with the app open, and the next boot schedules again.
  try {
    await scheduleSync().timeout(timeout);
  } on Exception catch (error, stackTrace) {
    logger.error('boot sync schedule', error, stackTrace);
  }

  // 5. Local preferences (theme and language), with a timeout and defaults.
  //    Connectivity closes the step, in mainCommon, after the session scope
  //    opens (startConnectivity, chapter 33).
  final settings = await AppSettings.load(
    preferences: getIt<AppPreferences>(),
    logger: logger,
    timeout: timeout,
  );

  // 6 to 8. Remote Config, forced update, and re-accepting the terms:
  //    mobile_tasks has none of the three (section 25.1).

  return settings;
}

/// Also step 1 of the background (chapter 32).
///
/// Public copy of the book: without [options], no flavor has a Firebase
/// project (see `firebase_options.dart`), and Firebase is not called; on
/// iOS, looking for a native configuration that does not exist would close
/// the app. The Firebase adapters write to the console. In the book, without
/// [options], Firebase looks for the flavor's native configuration.
Future<void> initializeFirebaseApp([FirebaseOptions? options]) async {
  if (options == null) return;
  await Firebase.initializeApp(options: options);
}

Future<void> _schedulePeriodicSync() =>
    getIt<SyncScheduler>().schedulePeriodicSync();

/// The end of step 5 (chapter 33). The orchestrator syncs on every
/// transition to online, and right away if the state is already online
/// when it starts. The check is never awaited, because it goes to the
/// network: the app opens with the `unknown` state, with no notice.
/// mainCommon calls this function after the session scope opens, so the
/// first sync already finds the modules' queues.
void startConnectivity({
  required ConnectivityService connectivity,
  required SyncOrchestrator orchestrator,
}) {
  orchestrator.start();
  unawaited(connectivity.start());
}
