import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/app.dart';
import 'package:mobile_tasks_app/l10n/mobile_tasks_localizations.dart';
import 'package:mobile_tasks_app/settings/app_languages.dart';

/// Which languages the app offers is the host's decision; translating the
/// screens belongs to each module (chapter 37). This test covers the gap
/// between the two: a new module that only brings English does not get past here.
void main() {
  test('every delegate translates every app language', () {
    for (final locale in AppLanguages.supported) {
      for (final delegate in [
        MobileTasksLocalizations.delegate,
        ...moduleLocalizationsDelegates,
      ]) {
        expect(
          delegate.isSupported(locale),
          isTrue,
          reason: '${delegate.type} without $locale',
        );
      }
    }
  });

  test('every delegate loads in all the app\'s languages', () async {
    for (final locale in AppLanguages.supported) {
      for (final delegate in appLocalizationsDelegates) {
        await expectLater(delegate.load(locale), completes, reason: '$locale');
      }
    }
  });

  test('the template language, used only before the choice, is one of those '
      'offered', () {
    expect(AppLanguages.supported, contains(AppLanguages.template));
  });

  test('Brazilian Portuguese falls back to the "pt" ARB', () {
    final l10n = lookupMobileTasksLocalizations(const Locale('pt', 'BR'));
    expect(l10n.appTitle, 'Tarefas');
  });
}
