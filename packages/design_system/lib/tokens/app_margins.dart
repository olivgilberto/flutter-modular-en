import 'app_breakpoints.dart';

/// Side margins come from the width class, never from a fixed value.
abstract final class AppMargins {
  static const compact = 16.0;
  static const wide = 24.0;

  static double of(WindowWidthClass widthClass) => switch (widthClass) {
    WindowWidthClass.compact => compact,
    WindowWidthClass.medium ||
    WindowWidthClass.expanded ||
    WindowWidthClass.large ||
    WindowWidthClass.extraLarge => wide,
  };
}
