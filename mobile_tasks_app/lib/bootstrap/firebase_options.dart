import 'package:firebase_core/firebase_core.dart';

import 'app_config.dart';

/// Each flavor's Firebase options.
///
/// In this public copy of the book, the `firebase_options_[flavor].dart`
/// files are not in the repository: they point to a Firebase project, and
/// each reader creates their own (chapter 38). Without them, every flavor
/// returns null, and the boot goes on without Firebase, with the adapters
/// writing to the console (chapter 25).
///
/// After running `flutterfire configure` for each flavor, replace the body
/// of this function with the book's:
///
/// ```dart
/// import '../firebase_options_dev.dart' as dev;
/// import '../firebase_options_prod.dart' as prod;
/// import '../firebase_options_staging.dart' as staging;
///
/// FirebaseOptions? firebaseOptionsFor(Flavor flavor) => switch (flavor) {
///   Flavor.dev => dev.DefaultFirebaseOptions.currentPlatform,
///   Flavor.staging => staging.DefaultFirebaseOptions.currentPlatform,
///   Flavor.prod => prod.DefaultFirebaseOptions.currentPlatform,
/// };
/// ```
FirebaseOptions? firebaseOptionsFor(Flavor flavor) => switch (flavor) {
  Flavor.dev || Flavor.staging || Flavor.prod => null,
};
