import 'package:flutter/material.dart';

import '../tokens/app_breakpoints.dart';
import '../tokens/app_margins.dart';
import '../tokens/app_spacing.dart';

/// A form screen: a bar with the [title], safe area, scrolling, and a
/// column no wider than the compact class, so the fields do not stretch
/// on a tablet. The [children] sit in an `AutofillGroup`, so the system's
/// password manager fills in and saves the fields
/// together.
final class AppForm extends StatelessWidget {
  const AppForm({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final margin = AppMargins.of(AppBreakpoints.widthClassOf(context));

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(margin),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.compactMaxWidth,
              ),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppSpacing.lg,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
