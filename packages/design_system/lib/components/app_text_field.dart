import 'package:flutter/material.dart';

import '../tokens/app_shape.dart';

/// A text field with a label. The [AppTextField.password] variant hides
/// the text and offers a button to show it; both labels of that button
/// are required, because the package has no strings of its own and the
/// screen reader has to say what the icon does.
final class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  }) : obscure = false,
       showLabel = null,
       hideLabel = null;

  const AppTextField.password({
    super.key,
    required this.controller,
    required this.label,
    required String this.showLabel,
    required String this.hideLabel,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  }) : obscure = true,
       keyboardType = TextInputType.visiblePassword;

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final String? showLabel;
  final String? hideLabel;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

final class _AppTextFieldState extends State<AppTextField> {
  // Ephemeral state: showing or hiding the password matters to nobody
  // outside the field.
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      // A password goes through neither autocorrect nor keyboard suggestions.
      autocorrect: !widget.obscure,
      enableSuggestions: !widget.obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(
          borderRadius: AppBorderRadius.extraSmall,
        ),
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _hidden ? widget.showLabel : widget.hideLabel,
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}
