import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:notes_module/notes_module.dart';

void main() {
  test('registration asks nothing of the scope', () {
    registerNotesModuleDependencies(GetIt.asNewInstance());
  });

  testWidgets('the module route opens the screen, in English', (tester) async {
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('pt')],
        localizationsDelegates: const [
          NotesModuleLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        routerConfig: GoRouter(
          initialLocation: NoteRoutes.listPath,
          routes: notesModuleRoutes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
  });
}
