import 'package:flutter/services.dart';

/// The app's environments. Each one's name is the same in three places:
/// the Android and iOS `--flavor`, the `main_[flavor].dart`, and
/// `config/[flavor].json`.
enum Flavor { dev, staging, prod }

/// The values that change between environments (chapter 10). They come from
/// the file passed with `--dart-define-from-file`; the code is the same in all three.
final class AppConfig {
  const AppConfig({required this.flavor, required this.apiBaseUrl});

  /// Reads the build's environment. Only `mainCommon` and
  /// [AppConfig.forBackground] call it.
  factory AppConfig.fromEnvironment(Flavor entryPoint) => AppConfig.resolve(
    entryPoint: entryPoint,
    nativeFlavor: appFlavor,
    defines: const {
      'FLAVOR': String.fromEnvironment('FLAVOR'),
      'API_BASE_URL': String.fromEnvironment('API_BASE_URL'),
    },
  );

  /// The background entry point has no `main_[flavor].dart`: the flavor is
  /// the build's, the same as the app's, and goes through the same checks
  /// (chapter 32).
  factory AppConfig.forBackground() => AppConfig.fromEnvironment(
    Flavor.values.firstWhere(
      (flavor) => flavor.name == appFlavor,
      orElse: () => throw StateError('background run without --flavor.'),
    ),
  );

  /// Checks that the three sources of the flavor agree and that the values
  /// exist. A wrongly assembled build is a bug: it fails at startup, with
  /// the fix in the message, instead of running against another
  /// environment's backend.
  factory AppConfig.resolve({
    required Flavor entryPoint,
    required String? nativeFlavor,
    required Map<String, String> defines,
  }) {
    final name = entryPoint.name;
    if (nativeFlavor != name) {
      throw StateError(
        'main_$name.dart with --flavor ${nativeFlavor ?? '(none)'}: '
        'use --flavor $name.',
      );
    }
    final configFlavor = defines['FLAVOR'] ?? '';
    if (configFlavor != name) {
      throw StateError(
        'main_$name.dart with FLAVOR "$configFlavor": '
        'use --dart-define-from-file=config/$name.json.',
      );
    }
    final apiBaseUrl = defines['API_BASE_URL'] ?? '';
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'https' || _isLocalDevBackend(entryPoint, uri))) {
      throw StateError(
        'Invalid API_BASE_URL in config/$name.json: "$apiBaseUrl".',
      );
    }
    return AppConfig(flavor: entryPoint, apiBaseUrl: apiBaseUrl);
  }

  /// The only exception to https (chapter 35): the development backend in
  /// tools/dev_backend, in the dev flavor and only on the local interface,
  /// which the iOS simulator shares with the computer and the Android
  /// emulator reaches through `adb reverse`. Nothing leaves the machine without TLS.
  static bool _isLocalDevBackend(Flavor flavor, Uri uri) =>
      flavor == Flavor.dev &&
      uri.scheme == 'http' &&
      const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);

  final Flavor flavor;

  /// The backend address: https, or http on the local interface in the dev flavor.
  final String apiBaseUrl;
}
