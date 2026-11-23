import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/boot.dart';
import 'package:mobile_tasks_app/bootstrap/dependency_injection.dart';

import '../support/fakes.dart';

void main() {
  late FakeLogger logger;
  late FakePreferences preferences;

  setUp(() {
    logger = FakeLogger();
    preferences = FakePreferences(storedLanguage: 'pt-BR');
  });
  // The boot waits for everything in the global get_it; each test starts
  // from an empty get_it, without what the previous test left pending.
  tearDown(getIt.reset);

  /// The test's composition root: only the two ports the boot uses.
  void configure() => getIt
    ..registerSingleton<AppLogger>(logger)
    ..registerSingleton<AppPreferences>(preferences);

  Future<void> noop() async {}

  test('without Firebase, the boot finishes and logs the reason', () async {
    final settings = await boot(
      initializeFirebase: () => Future.error(Exception('no configuration')),
      installErrorHandlers: () {},
      configure: configure,
      scheduleSync: noop,
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(settings.dispose);

    expect(settings.locale, const Locale('pt', 'BR'));
    expect(logger.logs, ['boot: Firebase unavailable (_Exception)']);
  });

  test('a Firebase that does not answer falls into the timeout', () async {
    final settings = await boot(
      initializeFirebase: () => Completer<void>().future,
      installErrorHandlers: () {},
      configure: configure,
      scheduleSync: noop,
      timeout: const Duration(milliseconds: 50),
    );
    addTearDown(settings.dispose);

    expect(logger.logs.single, startsWith('boot: Firebase unavailable'));
  });

  test('the steps run in order: handlers before injection', () async {
    final steps = <String>[];

    final settings = await boot(
      initializeFirebase: () async => steps.add('firebase'),
      installErrorHandlers: () => steps.add('handlers'),
      configure: () {
        steps.add('injection');
        configure();
      },
      scheduleSync: () async => steps.add('scheduling'),
    );
    addTearDown(settings.dispose);

    expect(steps, ['firebase', 'handlers', 'injection', 'scheduling']);
    expect(logger.logs, isEmpty);
  });

  test(
    'an async service that never gets ready does not lock the boot',
    () async {
      final settings = await boot(
        initializeFirebase: noop,
        installErrorHandlers: () {},
        configure: () {
          configure();
          getIt.registerSingletonAsync<_SlowService>(
            () => Completer<_SlowService>().future,
          );
        },
        scheduleSync: noop,
        timeout: const Duration(milliseconds: 50),
      );
      addTearDown(settings.dispose);

      // get_it lists each pending one as "instanceName : Type".
      expect(logger.logs, ['boot: services not ready: [null : _SlowService]']);
    },
  );

  test('a scheduling that fails or does not answer does not stop the app from '
      'opening, and goes to the crash log', () async {
    for (final schedule in [
      () => Future<void>.error(Exception('workmanager missing')),
      () => Completer<void>().future,
    ]) {
      logger.errors.clear();
      final settings = await boot(
        initializeFirebase: noop,
        installErrorHandlers: () {},
        configure: configure,
        scheduleSync: schedule,
        timeout: const Duration(milliseconds: 50),
      );
      settings.dispose();
      await getIt.reset();

      expect(logger.errors, ['boot sync schedule']);
    }
  });
}

/// A service whose initialization never finishes.
final class _SlowService {}
