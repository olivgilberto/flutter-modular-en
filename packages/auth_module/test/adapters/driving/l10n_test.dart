import 'dart:convert';
import 'dart:io';

import 'package:auth_module/adapters/driving/bloc/login_bloc.dart';
import 'package:auth_module/adapters/driving/l10n/auth_module_localizations.dart';
import 'package:auth_module/adapters/driving/session/session_bloc.dart';
import 'package:auth_module/adapters/driving/views/login_view.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'driving_mocks.dart';

/// The module's translations (chapter 37). A key missing from a translation
/// is not an error for gen-l10n: the screen shows the template's English
/// text to whoever chose Portuguese. This test turns the warning into a
/// failure.
void main() {
  const arbDir = 'lib/adapters/driving/l10n';
  const template = 'auth_module_en.arb';

  Map<String, Object?> read(String name) =>
      jsonDecode(File('$arbDir/$name').readAsStringSync())
          as Map<String, Object?>;

  Set<String> messages(Map<String, Object?> arb) =>
      arb.keys.where((key) => !key.startsWith('@')).toSet();

  final translations = [
    for (final file in Directory(arbDir).listSync().whereType<File>())
      if (file.path.endsWith('.arb')) file.uri.pathSegments.last,
  ]..sort();

  test('there is the template and at least one translation', () {
    expect(translations, containsAll([template, 'auth_module_pt.arb']));
  });

  test('every translation has exactly the template\'s keys', () {
    final expected = messages(read(template));
    for (final name in translations) {
      final arb = read(name);
      expect(messages(arb), expected, reason: name);
      // The language declared in the file is the one in its name.
      expect(
        name,
        'auth_module_${arb['@@locale']}.arb',
        reason: 'the @@locale of $name',
      );
    }
  });

  test('the generated class supports every language with an ARB', () {
    for (final name in translations) {
      final tag = name.substring('auth_module_'.length, name.length - 4);
      expect(
        AuthModuleLocalizations.delegate.isSupported(Locale(tag)),
        isTrue,
        reason: tag,
      );
    }
  });

  test('every plural has the =0 case: in Portuguese, the "one" category '
      'covers 0 and 1', () {
    final pt = lookupAuthModuleLocalizations(const Locale('pt', 'BR'));
    expect(pt.logoutLostChanges(0), startsWith('Nenhuma alteração'));
    expect(pt.sessionExpiredChanges(0), 'Sua sessão expirou. Entre de novo.');
    expect(pt.logoutLostChanges(1), startsWith('1 alteração'));
  });

  group('the sign-in screen in each language', () {
    late MockLoginBloc bloc;

    setUp(() {
      bloc = MockLoginBloc();
      whenListen(
        bloc,
        const Stream<LoginState>.empty(),
        initialState: const LoginInitial(),
      );
    });

    Future<void> show(WidgetTester tester, Locale locale, int pending) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: locale,
            localizationsDelegates:
                AuthModuleLocalizations.localizationsDelegates,
            supportedLocales: AuthModuleLocalizations.supportedLocales,
            home: BlocProvider<LoginBloc>.value(
              value: bloc,
              child: LoginView(
                expiredSession: SessionExpiredWithPendingChanges(
                  pendingChanges: pending,
                ),
              ),
            ),
          ),
        );

    testWidgets('English, the template language, with the plural for one '
        'change', (tester) async {
      await show(tester, const Locale('en'), 1);

      expect(find.text('Sign in to your account'), findsOneWidget);
      expect(find.textContaining('there is 1 change'), findsOneWidget);
      // Material's built-in strings change too: the global delegate comes
      // in the generated class's list.
      final material = MaterialLocalizations.of(
        tester.element(find.byType(LoginView)),
      );
      expect(material.cancelButtonLabel, 'Cancel');
    });

    testWidgets('Brazilian Portuguese, which falls back to the "pt" ARB, with '
        'the plural for several', (tester) async {
      await show(tester, const Locale('pt', 'BR'), 3);

      expect(find.text('Acesse sua conta'), findsOneWidget);
      expect(find.textContaining('há 3 alterações'), findsOneWidget);
    });
  });
}
