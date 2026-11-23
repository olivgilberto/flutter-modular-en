import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'the password field hides the text and the button says what it does',
    (tester) async {
      final controller = TextEditingController(
        text: 'correct-horse-battery-staple',
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          AppTextField.password(
            controller: controller,
            label: 'Password',
            showLabel: 'Show password',
            hideLabel: 'Hide password',
          ),
        ),
      );

      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      expect(field().enableSuggestions, isFalse);
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();

      expect(field().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    },
  );

  testWidgets('while loading, the main button is disabled and keeps its '
      'label', (tester) async {
    await tester.pumpWidget(
      _app(AppPrimaryButton(label: 'Sign in', loading: true, onPressed: () {})),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the error inside the screen is announced', (tester) async {
    await tester.pumpWidget(
      _app(const AppInlineError(message: 'Incorrect email or password.')),
    );

    expect(
      tester.getSemantics(find.text('Incorrect email or password.')),
      isSemantics(label: 'Incorrect email or password.', isLiveRegion: true),
    );
  });

  testWidgets('on a tablet, the form is no wider than compact', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AppForm(
          title: 'Sign in to your account',
          children: [
            AppTextButton(label: 'Create an account', onPressed: () {}),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(TextButton)).width,
      AppBreakpoints.compactMaxWidth,
    );
  });
}
