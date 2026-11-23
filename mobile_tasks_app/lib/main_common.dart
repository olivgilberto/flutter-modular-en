import 'package:auth_module/auth_module.dart';
import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'bootstrap/app_config.dart';
import 'bootstrap/app_router.dart';
import 'bootstrap/boot.dart';
import 'bootstrap/dependency_injection.dart';
import 'bootstrap/error_handling.dart';
import 'bootstrap/firebase_options.dart';
import 'observability/app_bloc_observer.dart';
import 'security/device_integrity.dart';
import 'security/tracking_authorization.dart';
import 'session/session_gate.dart';

/// The entry point shared by the three flavors (chapter 26). Each
/// `main_[flavor].dart` only says which one it is.
///
/// The three named parameters belong to the integration tests (chapter 39),
/// which build the whole app on the device and turn off only what cannot
/// run in a test: Firebase, so that test events and errors do not mix with
/// real usage in the console; the global handlers, because in a test the
/// error handler is the framework's own, which turns each error into a
/// failure; and the tracking request, a system alert the test cannot
/// reach. In production, all three stay on.
Future<void> mainCommon(
  Flavor flavor, {
  bool withFirebase = true,
  bool withErrorHandlers = true,
  bool withTrackingRequest = true,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment(flavor);
  final settings = await boot(
    initializeFirebase: withFirebase
        ? () => initializeFirebaseApp(firebaseOptionsFor(flavor))
        : () async {},
    installErrorHandlers: withErrorHandlers
        ? installGlobalErrorHandlers
        : () {},
    configure: () => configureDependencies(config),
  );
  final logger = getIt<AppLogger>();
  // An error that escapes a Bloc reaches the crash log (chapter 38).
  Bloc.observer = AppBlocObserver(logger);

  // The end of step 5: the session stored on the device (chapter 28). The
  // session scope opens before the read: data from a session that expired
  // before the app closed may be on the device, and only the modules know
  // how to count and erase it (chapter 32).
  openSessionScope();
  final sessionBloc = getIt<SessionBloc>();
  final session = SessionGate(
    initial: sessionBloc.state,
    changes: sessionBloc.stream,
    onSignedIn: openSessionScope,
    onSignedOut: renewSessionScope,
  );
  sessionBloc.add(const SessionRestoreRequested());
  await session.waitUntilKnown(timeout: bootStepTimeout, logger: logger);
  // And connectivity, with the scope already open (chapter 33).
  startConnectivity(
    connectivity: getIt<ConnectivityService>(),
    orchestrator: getIt<SyncOrchestrator>(),
  );

  // 9. runApp. Step 10, the redirect, runs on every navigation.
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  runApp(
    MobileTasksApp(
      settings: settings,
      router: createAppRouter(
        settings,
        session,
        analytics: getIt<AppAnalytics>(),
      ),
      connectivity: getIt<ConnectivityService>(),
      messengerKey: messengerKey,
    ),
  );

  // With the first screen in view and the app active (chapter 38): the
  // tracking request, which Apple only shows at that moment, and the root
  // or jailbreak notice, which needs a screen to appear on.
  if (withTrackingRequest) {
    await appActive(WidgetsBinding.instance);
    await requestTrackingAuthorization(logger: logger);
  }
  if (await deviceCompromised(logger: logger)) {
    final messenger = messengerKey.currentState;
    if (messenger != null) showDeviceIntegrityNotice(messenger);
  }
}
