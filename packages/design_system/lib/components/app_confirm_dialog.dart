import 'package:flutter/material.dart';

/// Asks the user to confirm an action that cannot be undone, such as
/// signing out with unsent changes. Returns `true` only when they confirm;
/// closing the dialog any other way counts as giving up. The strings come
/// ready, already translated, as in every component of the package.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      // With a large system font, the title and the message go past the
      // screen height; by scrolling, the buttons stay within reach
      // (chapter 39).
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
