# mobile_tasks_app

The mobile_tasks host: the only package in the workspace that builds an app,
for Android and iOS, and the only one that depends on the `adapter_*`
packages. It connects each `core` port to its adapter in the composition root
(`lib/bootstrap/dependency_injection.dart`) and brings the feature modules
together. It contains no business rules.

Architecture: [`../docs/architecture.md`](../docs/architecture.md).

## Status

- `auth_module` wired (chapter 28): with no session, the app opens on the
  sign-in; with a session, on the `tasks_module` list (chapter 34), inside the
  host's frame with the sign-out button. The session state comes from the
  module's `SessionBloc`, observed by the `SessionGate` (`lib/session/`),
  which opens and closes the session scope.
- Boot in `lib/bootstrap/boot.dart` (chapter 25): every asynchronous step has
  a timeout and a fallback path. Router in `lib/bootstrap/app_router.dart`;
  theme and language in `lib/settings/`.
- Three flavors (chapter 26): `dev`, `staging`, and `prod`, with a
  `lib/main_[flavor].dart` and a `config/[flavor].json` for each. The
  identifiers and on-screen names are in `android/app/build.gradle.kts`,
  `android/app/src/[flavor]/res/values/strings.xml`, and the xcconfigs that
  `tool/configure_ios_flavors.rb` generates in `ios/Flutter/`.
- Icon per flavor: once the product has an icon (recorded decision).
- Firebase not configured yet: boot step 1 fails and the app goes on; the
  logging and analytics adapters write to the console until
  `flutterfire configure` (chapter 38).
- The `SyncScheduler` (workmanager) is registered together with the
  background sync dispatcher, in chapter 32.

## Run

Always with the flavor's three parameters, which must agree (the app checks
them on launch):

```sh
cd mobile_tasks_app
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=config/dev.json
```

For `staging` and `prod`, change the name in all three places.

### With the local backend (chapter 35)

With no real backend, the `dev` flavor runs against `tools/dev_backend`, an
in-memory server that follows the contract. In one terminal, from the
workspace root:

```sh
dart run tools/dev_backend/bin/dev_backend.dart
```

In another, the app with `config/dev_local.json`:

```sh
cd mobile_tasks_app
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=config/dev_local.json
```

The iOS simulator reaches the computer's `127.0.0.1`. On the Android
emulator, run `adb reverse tcp:8080 tcp:8080` first. Plain http without TLS
is only accepted in the `dev` flavor and only on the local interface;
stopping the server erases accounts and tasks.

## Verify

From the workspace root:

```sh
dart run melos run analyze
dart run melos run test
dart run melos run check-deps
```

## Integration tests (chapter 39)

In `integration_test/`, they run on the device: the happy path, the offline
flow, and the adapters with the real technology. With an Android emulator
running (the script starts the iOS simulator on its own) and ports 8080 and
8081 free:

```sh
bash code/verify_integration.sh            # both platforms
PLATFORMS=ios FILES=offline_test.dart bash code/verify_integration.sh
```

The script starts `dev_backend` with `--control-port 8081`, connects the
ports to the emulator with `adb reverse`, and runs each file on an app
installed from scratch. The tests assemble the app through `mainCommon`,
without Firebase, without the global handlers, and without the tracking
request.
