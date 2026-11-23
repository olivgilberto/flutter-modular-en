import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/settings/app_settings.dart';

import '../support/fakes.dart';

void main() {
  late FakeLogger logger;

  setUp(() => logger = FakeLogger());

  Future<AppSettings> load(FakePreferences preferences) => AppSettings.load(
    preferences: preferences,
    logger: logger,
    timeout: const Duration(milliseconds: 50),
  );

  test('reads the stored theme and language', () async {
    final settings = await load(
      FakePreferences(
        storedThemeMode: AppThemeMode.dark,
        storedLanguage: 'pt-BR',
      ),
    );
    addTearDown(settings.dispose);

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.locale, const Locale('pt', 'BR'));
  });

  test('a language the app does not offer counts as not chosen', () async {
    final settings = await load(FakePreferences(storedLanguage: 'fr'));
    addTearDown(settings.dispose);

    expect(settings.locale, isNull);
  });

  test('a stuck read does not lock the boot: the defaults apply', () async {
    final settings = await load(FakePreferences(hang: true));
    addTearDown(settings.dispose);

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.locale, isNull);
    expect(logger.errors, ['boot preferences']);
  });

  test(
    'the choice writes through the port and comes back through the stream, notifying '
    'listeners',
    () async {
      final preferences = FakePreferences();
      final settings = await load(preferences);
      addTearDown(settings.dispose);
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.chooseLanguage(const Locale('en'));
      await preferences.saveThemeMode(AppThemeMode.light);
      // The change streams deliver the events asynchronously.
      await Future<void>.delayed(Duration.zero);

      expect(preferences.storedLanguage, 'en');
      expect(settings.locale, const Locale('en'));
      expect(settings.themeMode, ThemeMode.light);
      expect(notified, 2);
    },
  );
}
