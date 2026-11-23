import 'package:flutter/widgets.dart';

/// A language the app offers, with its name written in that language: the
/// selection screen needs no translation (chapter 13).
typedef AppLanguage = ({Locale locale, String nativeName});

/// The product's languages. Which languages the app offers is the host's
/// decision; each module brings its own translations (chapter 37).
abstract final class AppLanguages {
  static const all = <AppLanguage>[
    (locale: Locale('en'), nativeName: 'English'),
    (locale: Locale('pt', 'BR'), nativeName: 'Português (Brasil)'),
  ];

  static final supported = [for (final language in all) language.locale];

  /// The language of the modules' template ARBs. It is only used while the
  /// user has not chosen yet, for Material's built-in strings: the app's
  /// `locale` is never null, because null would mean the system language.
  static const template = Locale('en');

  /// The language stored by `AppPreferences`, as a BCP 47 tag
  /// ('pt-BR', 'en'). A tag the app does not offer counts as "not chosen
  /// yet".
  static Locale? fromTag(String? tag) {
    for (final locale in supported) {
      if (locale.toLanguageTag() == tag) return locale;
    }
    return null;
  }
}
