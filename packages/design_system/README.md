# design_system

The app's single visual source: the Material 3 tokens, the theme, and the
generic components the modules draw their screens on.

- **Contains:** colors (a seed and the semantic colors), bundled Inter
  typography, elevation, spacing, breakpoints, shape, motion, the `AppTheme`,
  and components with visual names (`AppEmptyState`, `AppConnectivityBanner`,
  `AppErrorPlaceholder`).
- **Never contains:** components with business names, text or translations,
  preference reads, Blocs, fonts or images fetched from the network, or a
  dependency on `core`, a module, or an adapter.

The seed color in `lib/tokens/app_color_scheme.dart` is provisional until the
brand is defined. The Inter font is distributed under the SIL Open Font
License 1.1 (`assets/fonts/OFL.txt`).
