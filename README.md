# Flutter Modular: the book's code

This repository holds `mobile_tasks`, the app built in Part II of the book
**Flutter Modular: Ports, Adapters, DDD, and Monorepos with Dart and Flutter:
From Workspace to CI/CD, with Offline-First and Testing**, by Gilberto Oliveira.

The code is in the state the book ends in, in chapter 43, and was verified
with **Flutter 3.47.5** in November 2026. The `edition-1` tag marks exactly
that state; the `main` branch may receive fixes later.

## What's here

```
mobile_tasks_app/      the host app: composition root, boot, routes, flavors (ch. 24 to 29)
packages/core/         the ports, in pure Dart with no dependencies (ch. 17)
packages/adapter_*/    the seven adapters, one per technology (ch. 18 and 41)
packages/design_system/
packages/auth_module/  the authentication module (ch. 20 to 23 and 28)
packages/tasks_module/ the tasks module, offline-first (ch. 30 to 36)
tools/workspace_lints/ check-deps and the boundaries plugin (ch. 15, 16, and 40)
tools/dev_backend/     the local development backend (ch. 35)
docs/                  the architecture documentation (Appendix E)
```

To find which files each chapter works on, use the book's Appendix G, which
maps each chapter by region of the architecture and by package.

## How to run it

You need Flutter 3.47.5 (later versions may need small adjustments), Xcode for
iOS (macOS only), and Android Studio or the Android command-line tools.

```sh
# at the root: resolves the whole workspace
flutter pub get

# each package's translations (chapter 37)
for p in $(grep -oE '^  - [^ ]+' pubspec.yaml | sed 's/^  - //'); do
  [ -f "$p/l10n.yaml" ] && (cd "$p" && flutter gen-l10n)
done

# workspace checks (chapters 15 and 40)
dart run melos run analyze --no-select
dart run melos run check-deps --no-select
dart run melos run test --no-select
```

To use the app for real, run the local backend in one terminal and the app in
another (chapter 35):

```sh
# terminal A, at the root
dart run tools/dev_backend/bin/dev_backend.dart

# terminal B, in mobile_tasks_app/
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=config/dev_local.json
```

On the Android emulator, connect the backend port first: `adb reverse tcp:8080 tcp:8080`.

The app opens in English and also speaks Brazilian Portuguese; the language
is chosen on first launch and can be changed later (chapter 37).

## Firebase (chapter 38)

The Firebase files are not part of this repository: they point to a Firebase
project, and each reader creates their own. Without them, the app builds and
runs normally, and the logging and analytics adapters write to the console.

To turn on Crashlytics and Analytics, follow chapter 38 (and chapter 40 for
staging and prod): create one project per flavor, run `flutterfire configure`
for each, and replace the body of
`mobile_tasks_app/lib/bootstrap/firebase_options.dart` with the book's, which
is in the file's own comment. The generated files are already in
`.gitignore`. Also replace the identifier `com.zayitbrazil.mobiletasks` with
your own (chapter 26).

## Differences from the book

So that the repository works without Firebase and without secrets, five files
have a small adjustment, marked with the comment "Public copy of the book":

| File | In the book | Here |
| --- | --- | --- |
| `mobile_tasks_app/lib/bootstrap/firebase_options.dart` | each flavor's options | `null` for all, until `flutterfire configure` |
| `mobile_tasks_app/lib/bootstrap/boot.dart` | with no options, Firebase looks for the native configuration | with no options, Firebase is not called |
| `mobile_tasks_app/android/app/build.gradle.kts` | Firebase plugins always applied | applied only when a `google-services.json` exists |
| `mobile_tasks_app/ios/Runner.xcodeproj/project.pbxproj` | the FlutterFire phase always runs | skipped, with a warning, without `firebase.json` |
| `.github/workflows/ci.yml` | the release build runs on every push to main | runs only when the upload key secrets exist |

The test `test/bootstrap/firebase_options_test.dart` checks the behavior
without Firebase.

## Demonstration branches

- `demo/boundaries`: the tasks module imports `auth_module` and `get_it` in
  its domain, on purpose. This branch's CI fails, and that is the point: the
  workspace rejects the violation (chapters 15 and 36).
- `ch42/skeleton`: the draft of `notes_module`, created by chapter 28's
  checklist, as in chapter 42. It never goes into `main`.

## Errors and questions

Found an error in the code or in the book? Open an issue, stating the chapter
and the section.

## License

The code is under the MIT license (`LICENSE` file). The book's text is not part
of this repository and is all rights reserved. The Inter fonts, in
`packages/design_system/assets/fonts`, are under the SIL Open Font License
(`OFL.txt`).
