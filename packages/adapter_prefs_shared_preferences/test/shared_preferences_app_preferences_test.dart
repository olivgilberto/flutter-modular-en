import 'package:adapter_prefs_shared_preferences/adapter_prefs_shared_preferences.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _MockPreferences extends Mock implements SharedPreferencesAsync {}

void main() {
  setUpAll(() => registerFallbackValue(''));

  late _MockPreferences preferences;
  late SharedPreferencesAppPreferences adapter;

  setUp(() {
    preferences = _MockPreferences();
    adapter = SharedPreferencesAppPreferences(preferences: preferences);
  });

  test('no choice: system theme and no language', () async {
    when(() => preferences.getString(any())).thenAnswer((_) async => null);

    expect(await adapter.themeMode(), AppThemeMode.system);
    expect(await adapter.languageCode(), isNull);
  });

  test('an unknown value falls back to the system theme', () async {
    when(
      () => preferences.getString('app_preferences.theme_mode'),
    ).thenAnswer((_) async => 'sepia');

    expect(await adapter.themeMode(), AppThemeMode.system);
  });

  test('saving the theme writes the key and notifies listeners', () async {
    when(
      () => preferences.setString('app_preferences.theme_mode', 'dark'),
    ).thenAnswer((_) async {});
    final next = adapter.themeModeChanges.first;

    await adapter.saveThemeMode(AppThemeMode.dark);

    expect(await next, AppThemeMode.dark);
    verify(
      () => preferences.setString('app_preferences.theme_mode', 'dark'),
    ).called(1);
  });

  test('saving the language writes the key and notifies listeners', () async {
    when(
      () => preferences.setString('app_preferences.language_code', 'pt'),
    ).thenAnswer((_) async {});
    final next = adapter.languageCodeChanges.first;

    await adapter.saveLanguageCode('pt');

    expect(await next, 'pt');
  });
}
