import 'package:flutter/material.dart';

/// Every role color (primary, surfaces, error, outline...) comes from a
/// single seed. No other role hex value exists in the app.
abstract final class AppColorScheme {
  /// Provisional until the brand is defined: changing only this value
  /// recomputes every other color, in light and dark.
  static const _brandSeed = Color(0xFF2F6EEA);

  /// `fidelity` keeps the brand color recognizable; the default `tonalSpot`
  /// would desaturate it. A contrast of 0.5 is Material's medium.
  static final light = ColorScheme.fromSeed(
    seedColor: _brandSeed,
    brightness: Brightness.light,
    contrastLevel: 0.5,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  static final dark = ColorScheme.fromSeed(
    seedColor: _brandSeed,
    brightness: Brightness.dark,
    contrastLevel: 0.5,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
}
