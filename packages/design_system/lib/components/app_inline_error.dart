import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';

/// An error message inside the screen, near what caused it. It receives
/// the text ready and is announced by the screen reader when it appears.
final class AppInlineError extends StatelessWidget {
  const AppInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(Icons.error_outline, color: theme.colorScheme.error),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
