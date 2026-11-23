/// Theme choice stored by [AppPreferences]. A pure Dart mirror of
/// Flutter's `ThemeMode`; the host does the conversion.
enum AppThemeMode { system, light, dark }

/// Non-sensitive preferences (theme, language). Never tokens, personal
/// data, or business data. Modules only write; the host listens to the
/// changes and applies them without restarting the app.
abstract interface class AppPreferences {
  /// [AppThemeMode.system] until the user chooses.
  Future<AppThemeMode> themeMode();
  Future<void> saveThemeMode(AppThemeMode mode);
  Stream<AppThemeMode> get themeModeChanges;

  /// `null` until the user chooses a language: it is never inferred from
  /// the system language (chapter 13).
  Future<String?> languageCode();
  Future<void> saveLanguageCode(String languageCode);
  Stream<String> get languageCodeChanges;
}
