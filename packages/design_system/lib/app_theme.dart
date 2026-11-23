import 'package:flutter/material.dart';

import 'tokens/app_color_scheme.dart';
import 'tokens/app_semantic_colors.dart';
import 'tokens/app_shape.dart';
import 'tokens/app_typography.dart';

/// The app's only `ThemeData`. The host picks between [light] and [dark]
/// with the theme the user stored through the `AppPreferences` port; this
/// package never reads or writes preferences.
abstract final class AppTheme {
  static ThemeData get light => _build(
    colorScheme: AppColorScheme.light,
    semanticColors: AppSemanticColors.light,
  );

  static ThemeData get dark => _build(
    colorScheme: AppColorScheme.dark,
    semanticColors: AppSemanticColors.dark,
  );

  static ThemeData _build({
    required ColorScheme colorScheme,
    required AppSemanticColors semanticColors,
  }) => ThemeData(
    colorScheme: colorScheme,
    textTheme: AppTypography.textTheme,
    extensions: [semanticColors],
    cardTheme: const CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppBorderRadius.medium),
    ),
  );
}
