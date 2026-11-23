import 'package:flutter/material.dart';

import '../tokens/app_spacing.dart';

/// The screen's main action. With [loading], the button is disabled and
/// shows the indicator next to the label, which stays visible: the screen
/// reader keeps announcing what the button does.
final class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.xxxl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const ExcludeSemantics(
              child: SizedBox.square(
                dimension: AppSpacing.lg,
                child: CircularProgressIndicator(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

/// A secondary action, such as a link to another screen.
final class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.xxxl),
      ),
      child: Text(label),
    );
  }
}
