import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contrast.dart';

void main() {
  final themes = {'light': AppTheme.light, 'dark': AppTheme.dark};

  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    group('theme $mode', () {
      test('includes the semantic colors', () {
        expect(theme.extension<AppSemanticColors>(), isNotNull);
      });

      test('the ColorScheme text pairs pass AA', () {
        final c = theme.colorScheme;
        final pairs = {
          'primary': (c.primary, c.onPrimary),
          'primaryContainer': (c.primaryContainer, c.onPrimaryContainer),
          'secondary': (c.secondary, c.onSecondary),
          'tertiary': (c.tertiary, c.onTertiary),
          'error': (c.error, c.onError),
          'surface': (c.surface, c.onSurface),
          'surfaceVariant': (c.surfaceContainerHighest, c.onSurfaceVariant),
          'inverseSurface': (c.inverseSurface, c.onInverseSurface),
        };
        for (final MapEntry(key: role, value: (bg, fg)) in pairs.entries) {
          expect(
            contrastRatio(bg, fg),
            greaterThanOrEqualTo(aaNormalText),
            reason: role,
          );
        }
      });

      test('the semantic colors pass AA', () {
        final s = theme.extension<AppSemanticColors>()!;
        expect(contrastRatio(s.critical, s.onCritical), greaterThan(4.5));
        expect(contrastRatio(s.positive, s.onPositive), greaterThan(4.5));
        expect(contrastRatio(s.neutral, s.onNeutral), greaterThan(4.5));
      });
    });
  }

  test('each theme has the brightness its name says', () {
    expect(AppTheme.light.colorScheme.brightness, Brightness.light);
    expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
  });

  test('the transition between modes interpolates the semantic colors', () {
    final middle = AppSemanticColors.light.lerp(AppSemanticColors.dark, 0.5);

    expect(middle.critical, isNot(AppSemanticColors.light.critical));
    expect(middle.critical, isNot(AppSemanticColors.dark.critical));
  });
}
