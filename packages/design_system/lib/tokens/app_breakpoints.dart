import 'package:flutter/widgets.dart';

/// The Material 3 window width classes.
enum WindowWidthClass { compact, medium, expanded, large, extraLarge }

/// The Material 3 window height classes.
enum WindowHeightClass { compact, medium, expanded }

/// The layout adapts to the window class, never to the device's
/// orientation: a phone on its side and a tablet upright may fall in the
/// same class, and the width decides.
abstract final class AppBreakpoints {
  /// Where the compact class ends. Also the maximum width of a form,
  /// which does not stretch on a tablet.
  static const compactMaxWidth = 600.0;

  static WindowWidthClass widthClassOf(BuildContext context) =>
      widthClassFor(MediaQuery.sizeOf(context).width);

  static WindowHeightClass heightClassOf(BuildContext context) =>
      heightClassFor(MediaQuery.sizeOf(context).height);

  static WindowWidthClass widthClassFor(double width) => switch (width) {
    < compactMaxWidth => WindowWidthClass.compact,
    < 840 => WindowWidthClass.medium,
    < 1200 => WindowWidthClass.expanded,
    < 1600 => WindowWidthClass.large,
    _ => WindowWidthClass.extraLarge,
  };

  static WindowHeightClass heightClassFor(double height) => switch (height) {
    < 480 => WindowHeightClass.compact,
    < 900 => WindowHeightClass.medium,
    _ => WindowHeightClass.expanded,
  };
}
