import 'package:adapter_analytics_firebase/adapter_analytics_firebase.dart';
import 'package:adapter_connectivity_connectivity_plus/adapter_connectivity_connectivity_plus.dart';
import 'package:adapter_db_sqlcipher/adapter_db_sqlcipher.dart';
import 'package:adapter_http_http/adapter_http_http.dart';
import 'package:adapter_logging_crashlytics/adapter_logging_crashlytics.dart';
import 'package:adapter_prefs_shared_preferences/adapter_prefs_shared_preferences.dart';
import 'package:adapter_sync_workmanager/adapter_sync_workmanager.dart';
import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:get_it/get_it.dart';
import 'package:notes_module/notes_module.dart';
import 'package:tasks_module/tasks_module.dart';

import 'app_config.dart';
import 'background_sync.dart';

final getIt = GetIt.instance;

const sessionScope = 'session';

/// A light, unauthenticated path the reachability probe checks
/// (chapter 33). Any HTTP response, even a 404, counts as reachable.
const _healthCheckPath = '/v1/health';

/// The base scope, which lives as long as the app lives. Order: the core
/// ports bound to the adapters and to the core's technology-free code; then
/// the authentication module, which completes the core with TokenProvider
/// and has to exist before the session, because it is what shows the
/// sign-in. Each environment's values come from [AppConfig]; swapping an
/// adapter per environment would be a single `switch (config.flavor)` here
/// (chapter 10), and the project has none.
void configureDependencies(AppConfig config) {
  _registerCoreAdapters(getIt, config);
  registerAuthModuleDependencies(getIt);
}

/// The session scope, where the feature modules register, so that nothing
/// of theirs survives into the next session; the tasks module since
/// chapter 30. Since chapter 32, it follows the data on the device, not the
/// sign-in: it opens at boot, before the stored session is read, and is
/// renewed at the end of every session. Data from an expired session may be
/// on the device before anyone knows who will sign in, and only the modules
/// registered here know how to count and erase it. The background opens it only with a stored session.
void openSessionScope() {
  if (getIt.hasScope(sessionScope)) return;
  getIt.pushNewScope(
    scopeName: sessionScope,
    init: (scope) {
      registerTasksModuleDependencies(scope);
      registerNotesModuleDependencies(scope);
    },
    dispose: () {
      getIt<LogoutCleanerRegistry>().unregisterAll();
      getIt<OutboxRegistry>().unregisterAll();
    },
  );
}

/// With no scope open, there is nothing to close.
Future<void> closeSessionScope() async {
  if (!getIt.hasScope(sessionScope)) return;
  await getIt.popScopesTill(sessionScope);
}

/// The end of a session, after the cleanup (chapter 32): the scope closes,
/// taking the instances of the session that ended and emptying the
/// registries, and opens again, empty, waiting for the next one. A cleanup
/// that failed leaves the data owner stored, and the next sign-in by someone
/// else still finds the modules to erase what was left.
Future<void> renewSessionScope() async {
  await closeSessionScope();
  openSessionScope();
}

/// The only place that knows which adapter serves each core port. Always
/// by the port's type and with an explicit function, never a tear-off: the
/// list of dependencies stays visible and the build breaks when it changes.
void _registerCoreAdapters(GetIt getIt, AppConfig config) {
  getIt
    ..registerLazySingleton<AppLogger>(() => CrashlyticsAppLogger())
    ..registerLazySingleton<AppAnalytics>(
      () => FirebaseAppAnalytics(logger: getIt<AppLogger>()),
    )
    // The http package on the inside (chapter 41); on the outside, the core
    // tells the ConnectivityService what each request finds out about the
    // backend (chapter 35).
    ..registerLazySingleton<ApiClient>(
      () => ConnectivityReportingApiClient(
        inner: HttpApiClient(
          baseUrl: config.apiBaseUrl,
          // Null until an authentication module registers a TokenProvider.
          tokenProvider: () => getIt.isRegistered<TokenProvider>()
              ? getIt<TokenProvider>()
              : null,
          logger: getIt<AppLogger>(),
        ),
        connectivityService: getIt<ConnectivityService>(),
      ),
    )
    ..registerLazySingleton<LocalDatabaseFactory>(
      () => SqlcipherLocalDatabaseFactory(),
    )
    ..registerLazySingleton<AppPreferences>(
      () => SharedPreferencesAppPreferences(),
    )
    ..registerLazySingleton<NetworkInterfaceMonitor>(
      () => ConnectivityPlusNetworkInterfaceMonitor(),
    )
    ..registerLazySingleton<ReachabilityProbe>(
      () => HttpReachabilityProbe(
        baseUrl: config.apiBaseUrl,
        path: _healthCheckPath,
      ),
    )
    ..registerLazySingleton<ConnectivityService>(
      () => DefaultConnectivityService(
        networkInterfaceMonitor: getIt<NetworkInterfaceMonitor>(),
        reachabilityProbe: getIt<ReachabilityProbe>(),
      ),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<LogoutCleanerRegistry>(
      () => DefaultLogoutCleanerRegistry(),
    )
    ..registerLazySingleton<OutboxRegistry>(() => DefaultOutboxRegistry())
    ..registerLazySingleton<OutboxSyncWorker>(
      () => OutboxSyncWorker(
        registry: getIt<OutboxRegistry>(),
        logger: getIt<AppLogger>(),
      ),
    )
    // The background entry point belongs to the host; the adapter connects
    // it to workmanager (chapters 10 and 32).
    ..registerLazySingleton<SyncScheduler>(
      () => WorkmanagerSyncScheduler(callbackDispatcher: outboxSyncDispatcher),
    )
    ..registerLazySingleton<SyncOrchestrator>(
      () => SyncOrchestrator(
        connectivityService: getIt<ConnectivityService>(),
        outboxSyncWorker: getIt<OutboxSyncWorker>(),
      ),
      dispose: (orchestrator) => orchestrator.dispose(),
    );
}
