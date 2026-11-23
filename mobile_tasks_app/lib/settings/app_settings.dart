import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'app_languages.dart';

/// The theme and language the host applies to the app. Read once at boot
/// and updated on every write to `AppPreferences`, from any module, without
/// restarting the app. The router listens to this object for the redirect.
final class AppSettings extends ChangeNotifier {
  AppSettings._({
    required AppPreferences preferences,
    required AppThemeMode themeMode,
    required Locale? locale,
  }) : _preferences = preferences,
       _themeMode = themeMode,
       _locale = locale {
    _subscriptions = [
      preferences.themeModeChanges.listen((mode) {
        _themeMode = mode;
        notifyListeners();
      }),
      preferences.languageCodeChanges.listen((tag) {
        _locale = AppLanguages.fromTag(tag);
        notifyListeners();
      }),
    ];
  }

  /// Boot step 5. Each read has a timeout and a default: without the
  /// preference, the theme follows the system and the language is yet to be chosen.
  static Future<AppSettings> load({
    required AppPreferences preferences,
    required AppLogger logger,
    required Duration timeout,
  }) async {
    var themeMode = AppThemeMode.system;
    Locale? locale;
    try {
      themeMode = await preferences.themeMode().timeout(timeout);
      locale = AppLanguages.fromTag(
        await preferences.languageCode().timeout(timeout),
      );
    } on Exception catch (error, stackTrace) {
      // A TimeoutException or a plugin failure: the app opens with the defaults.
      logger.error('boot preferences', error, stackTrace);
    }
    return AppSettings._(
      preferences: preferences,
      themeMode: themeMode,
      locale: locale,
    );
  }

  final AppPreferences _preferences;
  late final List<StreamSubscription<Object>> _subscriptions;
  AppThemeMode _themeMode;
  Locale? _locale;

  ThemeMode get themeMode => switch (_themeMode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// `null` while the user has not chosen: the redirect leads to the choice.
  Locale? get locale => _locale;

  /// Only writes; the change stream applies it, the same path as a change
  /// made by a settings screen in any module.
  Future<void> chooseLanguage(Locale locale) =>
      _preferences.saveLanguageCode(locale.toLanguageTag());

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
