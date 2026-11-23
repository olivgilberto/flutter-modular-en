import 'package:adapter_analytics_firebase/adapter_analytics_firebase.dart';
import 'package:adapter_connectivity_connectivity_plus/adapter_connectivity_connectivity_plus.dart';
import 'package:adapter_db_sqlcipher/adapter_db_sqlcipher.dart';
import 'package:adapter_http_http/adapter_http_http.dart';
import 'package:adapter_logging_crashlytics/adapter_logging_crashlytics.dart';
import 'package:adapter_sync_workmanager/adapter_sync_workmanager.dart';
import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/app_config.dart';
import 'package:mobile_tasks_app/bootstrap/dependency_injection.dart';

/// A cleaner from a module that does not exist yet.
final class _Cleaner implements ClearableOnLogout {
  var cleared = 0;

  @override
  Future<void> clearLocalData() async => cleared++;
}

/// The queue of a module that does not exist yet.
final class _Outbox implements SyncableOutbox {
  @override
  String get name => 'other';

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<bool> sync() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Each test builds the composition root in its own scope, undone at the end:
  // never reset() or allowReassignment.
  setUp(() {
    getIt.pushNewScope(scopeName: 'test');
    configureDependencies(
      const AppConfig(
        flavor: Flavor.dev,
        apiBaseUrl: 'https://api.dev.mobiletasks.example',
      ),
    );
  });
  tearDown(() => getIt.popScopesTill('test'));

  test('every core port is bound to its adapter, by type', () {
    expect(getIt<AppLogger>(), isA<CrashlyticsAppLogger>());
    expect(getIt<AppAnalytics>(), isA<FirebaseAppAnalytics>());
    // HttpApiClient, inside the core's decorator (chapters 35 and 41).
    expect(getIt<ApiClient>(), isA<ConnectivityReportingApiClient>());
    expect(getIt<LocalDatabaseFactory>(), isA<SqlcipherLocalDatabaseFactory>());
    expect(
      getIt<NetworkInterfaceMonitor>(),
      isA<ConnectivityPlusNetworkInterfaceMonitor>(),
    );
    expect(getIt<ReachabilityProbe>(), isA<HttpReachabilityProbe>());
    expect(getIt<SyncScheduler>(), isA<WorkmanagerSyncScheduler>());
    // SharedPreferencesAsync requires the native plugin, which does not exist
    // in tests; the adapter has its own tests (chapter 18).
    expect(getIt.isRegistered<AppPreferences>(), isTrue);
  });

  test('the core\'s technology-free code is assembled from what was '
      'registered', () {
    expect(getIt<SyncOrchestrator>(), isNotNull);
    expect(getIt<ConnectivityService>(), isA<DefaultConnectivityService>());
    expect(getIt<LogoutCleanerRegistry>(), isA<DefaultLogoutCleanerRegistry>());
    expect(getIt<OutboxRegistry>(), isA<DefaultOutboxRegistry>());
  });

  test('auth_module completes the core with TokenProvider and publishes the '
      'session state', () {
    expect(getIt.isRegistered<TokenProvider>(), isTrue);
    expect(getIt<SessionBloc>().state, isA<SessionUnknown>());
  });

  test('the session scope opens once and, on closing, empties the '
      'registries', () async {
    final cleaner = _Cleaner();

    openSessionScope();
    openSessionScope();
    expect(getIt.hasScope(sessionScope), isTrue);
    getIt<LogoutCleanerRegistry>().register(cleaner);

    await closeSessionScope();
    expect(getIt.hasScope(sessionScope), isFalse);
    await getIt<LogoutCleanerRegistry>().clearAll();
    expect(cleaner.cleared, 0);

    // Closing with no scope open, as at boot with no session, is not an error.
    await closeSessionScope();
  });

  test('renewing the session scope empties the registries and leaves a new '
      'scope open, waiting for the next session', () async {
    openSessionScope();
    final tasksOutbox = getIt<OutboxRegistry>().outboxes.single;
    getIt<OutboxRegistry>().register(_Outbox());

    await renewSessionScope();

    // Only the queue the tasks module signed up in the new scope, and not the
    // previous session's. The cleaners are not called here: the module's
    // would open the SQLCipher database, which only exists on the device.
    expect(getIt.hasScope(sessionScope), isTrue);
    final outboxes = getIt<OutboxRegistry>().outboxes;
    expect(outboxes, hasLength(1));
    expect(outboxes.single, isNot(same(tasksOutbox)));
    expect(outboxes.single.name, 'tasks');

    await closeSessionScope();
  });
}
