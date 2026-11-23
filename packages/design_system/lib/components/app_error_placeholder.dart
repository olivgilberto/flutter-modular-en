import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';

/// What the host's `ErrorWidget.builder` returns when a widget fails to
/// build: a neutral icon, with no text. It can be built without
/// localization and even without `Directionality`, so it depends on
/// neither; the failure itself goes to the `AppLogger` via the host's handler.
final class AppErrorPlaceholder extends StatelessWidget {
  const AppErrorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: AppSpacing.xxl,
          color: colors.onSurfaceVariant,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}
