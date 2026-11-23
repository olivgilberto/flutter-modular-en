import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/app_config.dart';

const _url = 'https://api.dev.mobiletasks.example';

Matcher _stateError(String hint) => throwsA(
  isA<StateError>().having((e) => e.message, 'message', contains(hint)),
);

void main() {
  test('the three sources of the flavor agree: the app receives the file\'s '
      'values', () {
    final config = AppConfig.resolve(
      entryPoint: Flavor.dev,
      nativeFlavor: 'dev',
      defines: {'FLAVOR': 'dev', 'API_BASE_URL': _url},
    );

    expect(config.flavor, Flavor.dev);
    expect(config.apiBaseUrl, _url);
  });

  test(
    'without --flavor, or with another environment\'s, the app does not open',
    () {
      for (final nativeFlavor in [null, 'prod']) {
        expect(
          () => AppConfig.resolve(
            entryPoint: Flavor.dev,
            nativeFlavor: nativeFlavor,
            defines: {'FLAVOR': 'dev', 'API_BASE_URL': _url},
          ),
          _stateError('use --flavor dev'),
        );
      }
    },
  );

  test(
    'with another environment\'s file, or with no file, the app does not open',
    () {
      for (final defines in [
        {'FLAVOR': 'prod', 'API_BASE_URL': 'https://api.mobiletasks.example'},
        <String, String>{},
      ]) {
        expect(
          () => AppConfig.resolve(
            entryPoint: Flavor.dev,
            nativeFlavor: 'dev',
            defines: defines,
          ),
          _stateError('--dart-define-from-file=config/dev.json'),
        );
      }
    },
  );

  test('with no backend address, or without https, the app does not open', () {
    for (final url in ['', 'http://api.dev.mobiletasks.example', 'api']) {
      expect(
        () => AppConfig.resolve(
          entryPoint: Flavor.dev,
          nativeFlavor: 'dev',
          defines: {'FLAVOR': 'dev', 'API_BASE_URL': url},
        ),
        _stateError('Invalid API_BASE_URL'),
      );
    }
  });

  test(
    'the local development backend accepts http, only in dev and only on the '
    'local interface (chapter 35)',
    () {
      for (final url in ['http://127.0.0.1:8080', 'http://localhost:8080']) {
        final config = AppConfig.resolve(
          entryPoint: Flavor.dev,
          nativeFlavor: 'dev',
          defines: {'FLAVOR': 'dev', 'API_BASE_URL': url},
        );
        expect(config.apiBaseUrl, url);
      }
      // Off the machine, or outside dev, it is still https or nothing.
      for (final (flavor, url) in [
        (Flavor.dev, 'http://192.168.0.10:8080'),
        (Flavor.dev, 'http://127.0.0.1.example:8080'),
        (Flavor.staging, 'http://127.0.0.1:8080'),
        (Flavor.prod, 'http://localhost:8080'),
      ]) {
        expect(
          () => AppConfig.resolve(
            entryPoint: flavor,
            nativeFlavor: flavor.name,
            defines: {'FLAVOR': flavor.name, 'API_BASE_URL': url},
          ),
          _stateError('Invalid API_BASE_URL'),
          reason: url,
        );
      }
    },
  );

  test('config/dev_local.json points dev to the local backend', () {
    final json = File('config/dev_local.json').readAsStringSync();
    final defines = (jsonDecode(json) as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, value as String),
    );

    final config = AppConfig.resolve(
      entryPoint: Flavor.dev,
      nativeFlavor: 'dev',
      defines: defines,
    );
    expect(config.apiBaseUrl, 'http://127.0.0.1:8080');
  });

  test('each flavor has a valid configuration file and an entry '
      'point', () {
    for (final flavor in Flavor.values) {
      final json = File('config/${flavor.name}.json').readAsStringSync();
      final defines = (jsonDecode(json) as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      );

      final config = AppConfig.resolve(
        entryPoint: flavor,
        nativeFlavor: flavor.name,
        defines: defines,
      );

      expect(config.flavor, flavor);
      expect(
        File('lib/main_${flavor.name}.dart').readAsStringSync(),
        contains('mainCommon(Flavor.${flavor.name})'),
      );
    }
  });
}
