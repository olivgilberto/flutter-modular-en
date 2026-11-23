import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../settings/app_languages.dart';

/// The language choice on first use (chapter 13). Each language appears in
/// its own language, so the screen has nothing to translate.
final class LanguageSelectionPage extends StatelessWidget {
  const LanguageSelectionPage({super.key, required this.onSelected});

  final ValueChanged<Locale> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppForm(
      title: 'Idioma · Language',
      children: [
        for (final language in AppLanguages.all)
          AppPrimaryButton(
            label: language.nativeName,
            onPressed: () => onSelected(language.locale),
          ),
      ],
    );
  }
}
