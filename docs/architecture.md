# mobile_tasks — architecture

## Workspace structure
Neutral root, host in mobile_tasks_app/, libraries in packages/, tools in
tools/. Roles by name; check-deps in CI. Two tools: tools/workspace_lints
(check-deps, chapter 15) and tools/dev_backend (chapter 35), an in-memory
server that follows the modules' contract, for running the app in the
simulator without a real backend. Tools are never a dependency of another
package.

## Host
mobile_tasks_app/ (chapter 24), created with its final name, for Android and
iOS. It is the only package that depends on the adapters. Since chapter 28,
it opens on auth_module's sign-in when there is no session; with a session,
since chapter 34, on tasks_module's list, inside the host's frame.

### Flavors (chapter 26)
dev, staging, and prod. Each one has three names that must agree: the
Android and iOS --flavor, lib/main_[flavor].dart, and
config/[flavor].json (--dart-define-from-file). AppConfig checks all three
on launch (appFlavor, the Flavor enum, and the FLAVOR key) and requires an
https API_BASE_URL. The only exception (chapter 35): in the dev flavor,
http on the local interface (127.0.0.1, localhost, ::1), for
config/dev_local.json, which points to tools/dev_backend. Identifiers:
com.zayitbrazil.mobiletasks, with .dev and .staging; on-screen names: Tasks
Dev, Tasks Stg, and Tasks. Android: productFlavors with applicationIdSuffix
and strings.xml per source set. iOS: tool/configure_ios_flavors.rb
(xcodeproj gem) creates the [Debug|Profile|Release]-[flavor]
configurations, one xcconfig per configuration in ios/Flutter/, one shared
scheme per flavor, CFBundleDisplayName = $(APP_DISPLAY_NAME), and the
Podfile map.

## Modules (chapter 42)
The index of feature modules: one line per module, with its page. check-deps
checks that every module in the workspace has its page in docs/modules/, its
line in this table, and a line of its own in .github/CODEOWNERS, and that no
page is left over from a module that was removed.

| Module | Subject | get_it scope | Owner | Page |
|---|---|---|---|---|
| auth_module | sign-in, registration, session, and sign-out | base | @olivgilberto | [modules/auth_module.md](modules/auth_module.md) |
| tasks_module | offline-first tasks, sync, and conflicts | session | @olivgilberto | [modules/tasks_module.md](modules/tasks_module.md) |
| notes_module | chapter 42 draft | session | @olivgilberto | [modules/notes_module.md](modules/notes_module.md) |

## Core ports
Catalog in packages/core/lib/core.dart (chapter 17). core has no
dependencies section; check-deps fails if one appears.
## Adapters
Seven adapter_* packages (chapter 18), one per technology, each with its
family registered in tools/workspace_lints/lib/src/dependency_rules.dart.
They throw core's errors (ApiError, LocalDatabaseError), never types of their
own.
## Design system
packages/design_system (chapter 19): Material 3 tokens over a provisional
seed color, bundled Inter font, light and dark AppTheme, and the
AppEmptyState, AppConnectivityBanner, and AppErrorPlaceholder components;
the form ones (AppForm, AppTextField, AppPrimaryButton, AppTextButton, and
AppInlineError) and the AppBreakpoints.compactMaxWidth token in chapter 22;
showAppConfirmDialog (confirmation of an action with no way back) in
chapter 29. It depends only on Flutter; check-deps rejects core, modules,
and adapters.
## Dependency injection and the session scope
Composition root in mobile_tasks_app/lib/bootstrap/dependency_injection.dart
(chapter 24). configureDependencies() connects each core port to its
adapter, always by the port type, and registers core's technology-free code
(registries, ConnectivityService, OutboxSyncWorker, SyncOrchestrator,
SyncScheduler). The session scope follows the data on the device, not the
sign-in (chapter 32): mainCommon opens it before reading the stored session,
and the SessionGate renews it (renewSessionScope: closes it and opens it
empty) when the session ends, always after the cleanup; disposing the scope
empties both registries. auth_module is registered in the base scope, after
the core ports (chapter 28): it provides the TokenProvider, which
HttpApiClient resolves on demand, and the SessionBloc, a single one from
boot to the end of the app; the host never observes the token. An expired
session with unsent changes (chapter 29) leads to the sign-in with the scope
open: the data and the queues wait for the user's decision. The owner of
that data is recorded in auth.db (chapter 32), which is why the same state
comes back after a restart. tasks_module registers itself in the session
scope's init (chapter 30) and registers its cleaner in the
LogoutCleanerRegistry and its queue in the OutboxRegistry (chapter 32).
### Background (chapter 32)
mobile_tasks_app/lib/bootstrap/background_sync.dart: outboxSyncDispatcher,
connected to workmanager through adapter_sync_workmanager (the host does not
import workmanager). Boot schedules the periodic outbox_sync task (1 h,
network only, ExistingPeriodicWorkPolicy.keep) at the end of step 4; a
failure goes to crash reporting and does not keep the app from opening. Each
run, in an isolate with an empty get_it: Firebase,
configureDependencies(AppConfig.forBackground()), and allReady once per
isolate; with no stored session, it ends without sending; with a session, it
opens the session scope and runs the OutboxSyncWorker, returning to the
system the opposite of "something was left for later". iOS: Info.plist with
BGTaskSchedulerPermittedIdentifiers (outbox_sync) and UIBackgroundModes
(fetch); the AppDelegate registers the plugins on the background engine and
the periodic task with the same identifier. Android: nothing beyond
workmanager.
### Connectivity (chapter 33)
Three layers, only as a hint: NetworkInterfaceMonitor (connectivity_plus),
ReachabilityProbe (HEAD on /v1/health, on an http client of its own, with no
token or retry, 3 s; any HTTP response counts as reachable), and core's
DefaultConnectivityService (unknown, offline, noInternet, online; a new check
with a growing wait from 15 s to 5 min while noInternet). mainCommon calls
startConnectivity() after opening the session scope and reading the stored
session: SyncOrchestrator.start() (syncs on every transition to online, 2 s
interval, one run at a time, and right away if already online) and
ConnectivityService.start(), never awaited. The ConnectivityBannerHost
(lib/connectivity/) sits in the MaterialApp.router builder, below every
screen: design_system's AppConnectivityBanner visible in offline and
noInternet, with the host's strings (MobileTasksLocalizations, chapter 37);
the screen stays whole and tappable. No module action checks the connection
state: tasks_module's test makes every write with the network down, and only
the refresh gesture shows the error.
Since chapter 35, the registered ApiClient is core's
ConnectivityReportingApiClient around HttpApiClient: a request that does not
arrive while the state is online asks for a check, and so does any response
while the state is noInternet. Without it, a backend that went down or came
back with the interface on went unnoticed (found in the simulator
walkthrough): no notice, and the queue only went up on the next write. With
the unknown state (background) nothing is requested.
## Routing and boot sequence
Boot in mobile_tasks_app/lib/bootstrap/boot.dart (chapter 25): Firebase
(failure tolerated, with a timeout), global error handlers, dependency
injection with allReady under a timeout, and reading the preferences
(AppSettings, with defaults if the read fails). Each step waits at most
bootStepTimeout (5 s). mainCommon (main_common.dart) reads the AppConfig,
calls boot(), asks the SessionBloc for the stored session and waits for the
read with the same timeout (the end of step 5), and calls runApp. The router
(app_router.dart) is a GoRouter with refreshListenable on AppSettings and
the SessionGate and a pure redirect, appRedirect, with two rules in order.
1: with no language chosen, everything goes to /language. 2: with no
session, everything that is not /auth/ goes to the sign-in; with a session,
the /auth/ screens lead to the destination. Both preserve the destination in
?from= (internal paths only). Host routes: app.home (/) and app.language
(/language); auth_module's come in spread (authModuleRoutes). Since chapter
34, app.home redirects to the task list (/tasks), and tasks_module's routes
come in inside a ShellRoute with the host's AppFrame
(lib/home/app_frame.dart): the module's screen and, below it, auth_module's
LogoutButton. HomePlaceholderPage is gone.

### Wiring a module (chapter 28)
A new module changes only these places outside its own package: 1. the root
workspace: list; 2. the host's pubspec.yaml; 3. one line in
configureDependencies() (base scope) or in openSessionScope()'s init
(session scope, feature modules); 4. one spread in createAppRouter; 5. one
rule in the redirect, only if the module decides who gets in (auth_module);
6. the module's translation delegate in app.dart's
moduleLocalizationsDelegates list, when the module has screens (chapter 37);
7. background sync, when it has a send queue (chapter 32);
8. docs/modules/[module].md, the line in this page's Modules index, and the
line in .github/CODEOWNERS, checked by check-deps (chapter 42); 9. verify.sh.
## Network
adapter_http_http (chapter 41, replacing chapters 18 and 27's
adapter_http_dio): HttpApiClient, with the http package. Authentication,
within the send itself: it adds the token when there is a TokenProvider and,
on a 401 to a request that carried the token, asks for a refresh (once) and
repeats with a new request; post(..., authenticated: false) goes through
with no token and no refresh, and it is what the refresh itself uses. A
refresh with no network surfaces as its own ApiError (transient), not as the
401. Log: method, path, status, and duration, never headers, query, or
bodies. Log and timeout (20 s), per attempt, in an inner client. Retry: the
package's RetryClient, transient failures only (5xx and transport), three
attempts, exponential backoff with jitter; the Idempotency-Key goes on all of
them. Dio remains forbidden in the modules, through check-deps' list of
retired technologies. HTTPS only: AppConfig requires https,
network_security_config.xml on Android (no cleartext, system CAs only), and
the default ATS on iOS, with no exceptions in Info.plist.
## Persistence and sync
One SQLCipher database per module (auth.db, tasks.db), opened through the
LocalDatabaseFactory port (chapters 18 and 30): a random 256-bit key per
database in secure storage (Keychain with first_unlock_this_device on iOS),
files in Application Support/local_databases. Out of backups: on iOS, the
AppDelegate flags the folder with isExcludedFromBackup on every launch; on
Android, allowBackup="false" and data_extraction_rules.xml exclude
files/local_databases/ and shared_prefs (where secure storage lives) from
cloud backup and device-to-device transfer. Each module declares its
DatabaseSchema with the full schema of the current version and the
migrations; a published version never changes (a schema test per module).
Stale-while-revalidate reads with a TTL per data type and cursor pagination;
writes record the operation in the module's queue in the same transaction
(chapter 31). Sending the queue (chapter 32) follows the recording order
with one send at a time in each isolate; creation by PUT with the app's id,
changes and archiving by PATCH with the base version, the operation id in
the body and in the Idempotency-Key. Outcomes: 2xx leaves the queue and
rebases the task's following operations on the new version; transient,
unreadable response, 401, 429, and a 409 that is not about the version stay
and stop the round; 404 on an archive leaves; a version 409 and other 4xx
go to sync_conflicts, and the task's following operations wait for the
decision. Device preferences (theme, language) in AppPreferences; user
preferences in the module's database, erased on sign-out.
Manual check before each published release (no automated test covers it): a
device backup, restored on another device, arrives without the
local_databases folder and without secure storage, and the app opens empty
and downloads the data on the first sync. Also before each release that
brings a migration: install the previous release on a simulator, create
data, install the new one over it, and open it. The schema tests run on the
computer's SQLite, not on the device's SQLCipher (tasks.db migration 2 uses
json_object, built into SQLite since 3.38.0). Since chapter 32, also:
background sync on a real device (Android: app closed, a change made with no
network, network back, the queue empties within one cycle; iOS: the
outbox_sync task fired from the Xcode debugger), and two people on the same
device (Ana is signed out by expiration with pending changes, the app is
closed, Bia signs in and sees nothing of Ana's).
## Internationalization
Chapter 37. Each package with screens has its own ARBs and its own class
generated by gen-l10n (l10n.yaml in the package; the English ARB is the
template, with a description on every key and =0 in every plural):
auth_module, tasks_module, and the host. The host gathers the delegates in
moduleLocalizationsDelegates, in app.dart, and a test checks that each one
translates every language in AppLanguages (en and pt). The language is
chosen on first use, stored through the AppPreferences port, and changed on
the app.language screen. design_system has no ARB: components receive their
text ready.

## Observability
Chapters 14 and 38. AppLogger → CrashlyticsAppLogger
(adapter_logging_crashlytics); AppAnalytics → FirebaseAppAnalytics
(adapter_analytics_firebase). One Firebase project per flavor
(mobile-tasks-dev, -staging, -prod), with the options chosen by
firebaseOptionsFor(flavor). Global handlers (lib/bootstrap/error_handling.dart)
take Flutter's and the platform's errors to the AppLogger; the
AppBlocObserver, those that escape the Blocs. Viewed screens are logged by
the host, by route name (ScreenViewObserver, one per navigator). Product
events belong to the use cases, after the operation succeeds, in the
[module]_[object]_[verb] format; no personal data, secrets, or unique values
(the user is an opaque id). Symbols of the obfuscated builds uploaded by CI.

## Security
Chapters 14, 30, and 38. Encrypted local database (SQLCipher), with the key
in the platform's secure storage; one file per module, erased on sign-out by
the LogoutCleanerRegistry. Android: allowBackup="false" and
data_extraction_rules, so that nothing goes to backup;
network_security_config with no cleartext traffic and only the system's
certificate authorities (chapter 27). API on https only, except the local
interface in the dev flavor (AppConfig, chapter 35). Obfuscated production
builds; no secrets in the app or in --dart-define-from-file. iOS: App
Tracking Transparency after the first frame, with the app active, and no
feature depends on the answer. Root and jailbreak checked with safe_device
only on real devices, with a notice in a MaterialBanner, without blocking the
app. No certificate pinning: the app handles neither financial nor health
data.
## CI/CD
Private repository on GitHub (chapter 40). `.github/workflows/ci.yml`: on every pull request and push to `main`, formatting, `melos analyze` (with the `workspace_lints` plugin), `check-deps`, and tests, each with `if: !cancelled()`; on pull requests, debug APKs of the three flavors; on `main`, staging and prod app bundles signed with the upload key (`ANDROID_*` secrets), certificate checked with `keytool`, `--obfuscate --split-debug-info`, `--build-number` = `github.run_number`, Dart symbols uploaded with `firebase crashlytics:symbols:upload` and the R8 mapping uploaded by the Crashlytics Gradle plugin (service accounts `FIREBASE_SA_STAGING`/`FIREBASE_SA_PROD`, with the Crashlytics role only), and prod iOS with `--no-codesign`. `.github/workflows/integration.yml`: the integration tests on the Android emulator (api 35), by hand only (since November 5, 2026, because online_journey does not load on the CI emulator). `renovate.json`: patch with automerge, major with approval on the dashboard.
Open: KGP and `--strip` warnings, `main` protection (account plan), the Renovate app, iOS signing.

## Recorded decisions
| Date | Decision | Reason |
|---|---|---|
| 2026-10-18 | Host for Android and iOS, with org com.zayitbrazil | The product's platforms; the final identifiers per flavor come in chapter 26 |
| 2026-10-18 | SyncScheduler registered only in chapter 32 | The adapter requires the background dispatcher, which is born with the outbox (registered in chapter 32) |
| 2026-10-26 | Language selection screen in the host since chapter 25 | It is the redirect's first rule; without it, boot would have no real destination. The ARB and the translations remain in chapter 37 |
| 2026-10-26 | Platform configuration for deep links postponed | App Links and Universal Links require a domain of one's own; the redirect already accepts internal destinations via ?from= |
| 2026-10-26 | Identifiers com.zayitbrazil.mobiletasks (+ .dev and .staging) and names Tasks Dev, Tasks Stg, and Tasks | The store identifier does not derive from the Dart package name; the three flavors install side by side |
| 2026-10-26 | App name on Android via strings.xml in each source set, without resValue | resValue fails by default from AGP 9 on |
| 2026-10-26 | Icon per flavor postponed until the product has an icon | Without a brand, an icon per environment would be a placeholder to replace later |
| 2026-10-26 | config/[flavor].json files versioned, with no secrets | Only addresses and names; secrets come in through CI (chapter 40) |
| 2026-10-26 | ApiClient.post gained authenticated (default true) | The refresh request cannot carry the expired token or trigger another refresh; only post because the product's sessionless requests are all post |
| 2026-10-27 | auth_module in the base scope; the host observes the SessionBloc, never the token | It shows the sign-in, so it exists before the session; the state only becomes "ended" after the cleanup (chapter 11) |
| 2026-10-27 | Sign-out as a LogoutButton exported by auth_module, in the frame of the host's screens | Signing out is an action, not a screen; a route under /auth/ would be diverted by the redirect for those with a session |
| 2026-10-27 | Owner of the local data in memory only until chapter 32 | With no send queue, there is no expired session with pending changes in the app; the queue brings the case and the persistence (resolved in chapter 32) |
| 2026-10-27 | Stored session read at the end of boot step 5, with a timeout | Without it, those with a session would see the sign-in for an instant; after the timeout, the app opens on the sign-in and moves on by itself when the read finishes |
| 2026-10-27 | User preferences in the module's database; AppPreferences only for the device's | The user's go away on sign-out with their data; theme and language belong to the device and survive it |
| 2026-10-27 | allowBackup="false" and data_extraction_rules on Android; local_databases folder out of backup on iOS | The databases' keys never leave the device; a database restored without its key would be unreadable |
| 2026-10-27 | Task ids generated on the device (UUID v4, no dependency) | The task exists before it reaches the backend, and resending the creation does not duplicate it (chapter 32) |
| 2026-10-27 | Writes record the operation in the queue since chapter 31; sending comes in 32 | The refresh from the network needs to know what the user did that the server does not know yet; without the queue, it would erase the tasks created on the device |
| 2026-10-27 | Between chapters 31 and 32, the task queue exists but is not in the OutboxRegistry: sign-out does not count it | Registering only the count would require a sync() that sends nothing; no user reaches that path without the screen, and chapter 32 registers the real queue (closed in chapter 32) |
| 2026-10-28 | Data owner recorded in auth.db (version 2), not in tasks_module's queue as planned | After a restart with no session, the session scope was not open: auth_module would not read the owner in another module's queue, nor find whom to erase. Only the id, erased after the data; an unreadable owner rejects the sign-in |
| 2026-10-28 | Session scope opened at boot and renewed at each end of session | Data from an expired session may be on the device before anyone knows who signs in; only the registered modules know how to count and erase it. The screens remain protected by the redirect |
| 2026-10-28 | tasks.db version 3: sync_conflicts only | The owner went to auth.db; the rejections table is born with sending |
| 2026-10-28 | A successful send reads the new version and rebases the task's following operations | Without it, creating and then renaming with no network would produce a 409 against the user's own change |
| 2026-10-28 | A 409 is a conflict only with {"code": "version_conflict"}; any other 409 stays in the queue | The Idempotency-Key draft answers 409 to the same key still being processed, the case of the open app and the background sending together |
| 2026-10-28 | SyncOrchestrator.start() in chapter 33, not 32 | It depends on ConnectivityService.start(), which comes in with connectivity; until then, the queue goes up after each write and in the background |
| 2026-10-28 | Connectivity started in mainCommon, after the session scope, not in boot() | The first sync needs the modules' queues, registered in the session scope; boot() still knows nothing about sessions |
| 2026-10-28 | Connection notice below the screens, in the MaterialApp.router builder, never modal | It is a hint, not a rule: the screen stays tappable, and no action depends on the state |
| 2026-10-28 | The orchestrator syncs even with no session | Queues with no token get 401 and stay; only an expired session with pending changes has a queue in that state, and sending works again on sign-in |
| 2026-10-28 | The signed-in user's start screen is the task list, by a redirect from / to /tasks | The host still owns /, and the module, its own paths; a second feature module changes only the destination |
| 2026-10-28 | Screen frame (sign-out button) in a host ShellRoute | tasks_module does not know auth_module; the host is what brings the two together |
| 2026-10-28 | The server version is queried again at the moment of deciding on a conflict | Between opening the screen and deciding, the task may have changed again; the old base would produce another 409 |
| 2026-10-28 | "Redo" stores the server version and opens the task's screen | The rejected change would never go through as it is; the user acts again on the current state |
| 2026-10-28 | In-memory development backend in tools/dev_backend (shelf), chosen with the user for chapter 35's walkthrough | The project has no backend; a server that follows the contract, with "someone else" routes, lets you trigger conflicts, rejections, and refreshes in the simulator. The contract test reads it with DioApiClient and the modules' Services |
| 2026-10-28 | http accepted only in the dev flavor and only on the local interface | The iOS simulator shares the computer's 127.0.0.1, and the Android emulator reaches it through adb reverse; nothing leaves the machine without TLS, and staging and prod remain https only |
| 2026-10-28 | Requests feed the ConnectivityService through a core decorator on the ApiClient | The service only checked on start and when the interface changed; in chapter 35's walkthrough, the backend being down showed no notice and the queue did not go up by itself when it came back. The decorator lives in core, with no technology, and no module starts reading the connection state |
| 2026-10-28 | The technologies a module cannot declare come from the adapters' families, not from a second list | The hand-written list let flutter_secure_storage and path_provider through, from the database family; a new adapter starts protecting its technologies when it enters the table |
| 2026-10-28 | Imports-by-layer test inside tasks_module until the analyzer plugin (chapter 40) | check-deps sees the whole package's pubspec.yaml; the layers are folders of the same package, and only reading the files tells them apart |
| 2026-10-27 | 5-minute TTL for the task list, with a refresh forced by the pull gesture | The user already sees their own changes; the TTL only covers those made on another device |
| 2026-10-26 | No certificate pinning | Outages on certificate rotation; network_security_config keeps only the system CAs (chapter 14) |
| 2026-10-29 | Per-package translations with gen-l10n: l10n.yaml and ARBs in each module with screens and in the host; ARBs and generated class on the module's driving side (lib/adapters/driving/l10n) | Text belongs to screens; the domain has none, and the imports test accepts flutter_localizations and intl only on the driving side |
| 2026-10-29 | "pt" ARB (Brazilian Portuguese) and "en" (template); the host offers en and pt-BR | The generated delegate decides by language code, and pt-BR falls back to "pt"; a pt_PT, if it comes, gets its own ARB |
| 2026-10-29 | nullable-getter: false and required-resource-attributes: true in every l10n.yaml | No `!` on every screen, and every key with its description for translators |
| 2026-10-29 | A test per package checks that every translation has the template's keys, and a host test that every delegate translates every app language | For gen-l10n, a key with no translation is a warning, and the screen would show the template's text |
| 2026-10-29 | Real Firebase only in the dev flavor (mobile-tasks-dev project); staging and prod in chapter 40 | The user's decision. firebaseOptionsFor(flavor) delivers the options generated by flutterfire configure; with no options, boot goes on without Firebase. On Android, missingGoogleServicesStrategy = WARN for the flavors without google-services.json |
| 2026-10-29 | App Tracking Transparency after runApp, when the app becomes active, not in boot step 2 | Apple ignores, with no error, a request made while the app is still inactive |
| 2026-10-29 | Root and jailbreak with safe_device, only on real devices, notice in a host MaterialBanner | The user's decision on the package; emulators and simulators often look like rooted devices; mobile_tasks has no sensitive feature to turn off |
| 2026-10-29 | Viewed screens logged by one ScreenViewObserver on the GoRouter and another on the ShellRoute; Bloc errors through the AppBlocObserver | A NavigatorObserver serves a single navigator, and the frame has its own |
| 2026-10-29 | Obfuscated production build, with symbols in build/symbols/prod | Uploading the symbols to Crashlytics is CI's job (chapter 40) |
| 2026-11-02 | Every View is tested with the system font at 1.0, 2.0, and 3.0 on a 375 × 667 point phone: nothing overflows and the main actions are reachable | Android 14 goes to 200%, iOS's largest size exceeds 3×; the tests found the confirmation dialog without scrolling and the conflicts notice squeezed |
| 2026-11-02 | Integration tests in mobile_tasks_app/integration_test, in a separate script (verify_integration.sh), on the iOS simulator and the Android emulator | The user's decision; they need devices and minutes, and verify.sh stays fast. Each file runs on an app installed from scratch, against dev_backend |
| 2026-11-02 | The integration test uses the real mainCommon, without Firebase, global handlers, or the tracking request | Test events do not go to the usage console; the test framework handles the errors; the system alert is out of the test's reach |
| 2026-11-02 | dev_backend with a control port (--control-port): /control/stop and /control/start close and open the API port | The user's decision; the offline test, on the device, needs a truly refused connection, like a server that is down |
| 2026-11-02 | No Android cleartext exception for dev_backend | Dio uses Dart sockets, to which Android's network policy does not apply; tested on the emulator without the file. It comes back, with a test, if the app gains a native network stack |
| 2026-11-03 | Private GitHub repository, with GitHub Actions | The user's decision; the signing and service account secrets live in the repository's secrets |
| 2026-11-03 | The CI checks all run, even after a failure (`if: !cancelled()`) | The pull request shows every problem at once; `always()` would run even after a cancellation |
| 2026-11-03 | Release builds only on `main`: signed and obfuscated staging and prod Android; unsigned iOS | The user's decision; pull requests build the three flavors in debug, with no secrets; signed iOS requires the Apple Developer Program |
| 2026-11-03 | Integration tests in CI only on Android, on every merge to `main` and by hand | The user's decision; an emulator and almost twenty minutes per run do not fit in every pull request; iOS stays in verify_integration.sh |
| 2026-11-03 | One Firebase project per flavor (dev, staging, and prod); the google-services WARN strategy is gone | The user's decision; production numbers do not mix with test numbers |
| 2026-11-03 | Each package's `analysis_options.yaml` includes the root's, which declares the `workspace_lints` plugin | The analyzer uses the nearest options file; without the include, the plugin loads and does not run in the packages (dart-lang/sdk#62161) |
| 2026-11-03 | The `workspace_lints` tests run with `dart test` | `test_reflective_loader` uses `dart:mirrors`, which `flutter test` does not compile |
| 2026-11-03 | Upload key outside the repository; a release without `key.properties` comes out with the debug key, and CI fails if the secret is missing or the certificate is the debug one | Local release builds remain possible without the key; the store never receives a wrongly signed build |
| 2026-11-03 | Dio leaves and the http package comes in, in an adapter_http_http; adapter_http_dio is removed from the workspace | The user's decision (chapter 41): proof of a technology swap with no external service; no module changes |
| 2026-11-03 | The Dio adapter's 17 tests are ported one by one, with the same names and expectations; only the simulated server changes (MockClient) | The user's decision: the old tests are the new adapter's contract |
| 2026-11-03 | Retry through the http package's RetryClient, with Dio's rules (3 attempts, 5xx and transport, exponential with jitter) | The user's decision; RetryClient's default only retries 503 |
| 2026-11-03 | A removed adapter's technology goes into check-deps' retiredTechnologies | Without it, the family leaves with the adapter and Dio would be accepted in a module again |
| 2026-11-05 | In CI integration, Gradle uses up to 3 GB, with no daemon, and Kotlin compiles inside it | A private repository's machine has 8 GB, and the template's gradle.properties reserves up to 8 GB; with the emulator on, the machine went down (chapter 41) |
| 2026-11-05 | check-deps checks, for each feature module, the page in docs/modules/, the line in this page's index, and a line of its own in .github/CODEOWNERS | With twenty modules, documentation and ownership can no longer be remembered by heart; a page with no module is rejected too |
| 2026-11-05 | New module through chapter 28's checklist, with no Mason brick and no copy of an existing module | A copied template ages with the project, and six of the nine steps are outside the package; check-deps points out what was missing, wherever the module came from |
| 2026-11-05 | Lists of packages with translations and of modules with coverage derived from the root workspace: list, in verify.sh and in CI | A hand-written list is one more step, and a forgettable one, for every module |
| 2026-11-05 | integration.yml by hand only (workflow_dispatch), without the push to main | The third file does not load on the CI emulator ("Failed to start Dart Development Service") in four runs in a row and passes on the Mac; a permanent X teaches people to ignore CI. Integration stays in verify_integration.sh before each release |
| 2026-11-05 | Crashlytics Gradle plugin (com.google.firebase.crashlytics 3.0.8): the Android release build uploads the R8 mapping | The user's decision: the Dart symbols already arrived through CI, but a crash in a plugin's Kotlin/Java code would arrive obfuscated. With the plugin, both sides of the stack arrive readable |
