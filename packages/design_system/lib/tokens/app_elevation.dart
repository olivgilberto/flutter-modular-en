import 'package:flutter/painting.dart';

/// Five shadow levels. M3 elevation combines three techniques: the
/// surface tone (the `ColorScheme`'s `surfaceContainer*`), this shadow,
/// and the [AppScrim]; never the shadow alone.
abstract final class AppElevation {
  /// Surface on the base plane.
  static const level0 = <BoxShadow>[];
  static const level1 = <BoxShadow>[
    BoxShadow(color: Color(0x21000000), blurRadius: 2),
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 4),
  ];

  /// Cards.
  static const level2 = <BoxShadow>[
    BoxShadow(color: Color(0x21000000), blurRadius: 2),
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// Notices and menus.
  static const level3 = <BoxShadow>[
    BoxShadow(color: Color(0x21000000), blurRadius: 2),
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 8), blurRadius: 16),
  ];

  /// Popovers and the highlighted element.
  static const level4 = <BoxShadow>[
    BoxShadow(color: Color(0x21000000), blurRadius: 2),
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 14), blurRadius: 28),
  ];
}

/// The translucent layer that separates a modal from the rest of the screen.
abstract final class AppScrim {
  static const color = Color(0x8A000000);
}
