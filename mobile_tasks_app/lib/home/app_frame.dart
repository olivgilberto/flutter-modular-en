import 'package:auth_module/auth_module.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The frame of the signed-in screens (chapter 29): the feature module's
/// screen and, below it, auth_module's sign-out button. Since chapter 34,
/// the frame wraps the tasks module's routes and takes the place of the
/// provisional start screen. The host builds the frame; the tasks module
/// does not know auth_module.
final class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: child),
      Material(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: const LogoutButton(),
          ),
        ),
      ),
    ],
  );
}
