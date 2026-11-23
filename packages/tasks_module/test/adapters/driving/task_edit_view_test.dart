import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driving/bloc/task_edit_bloc.dart';
import 'package:tasks_module/adapters/driving/l10n/tasks_module_localizations.dart';
import 'package:tasks_module/adapters/driving/views/task_edit_view.dart';
import 'package:tasks_module/domain/task_failure.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  late MockTaskEditBloc bloc;
  late StreamController<TaskEditState> states;

  setUpAll(() => registerFallbackValue(const TaskEditArchived()));

  setUp(() {
    bloc = MockTaskEditBloc();
    states = StreamController<TaskEditState>();
  });
  // No await: a StreamController nobody listened to never finishes
  // closing.
  tearDown(() => unawaited(states.close()));

  /// The edit screen stacked over a source screen, as from the list.
  Future<void> show(WidgetTester tester, TaskEditState state) async {
    whenListen(bloc, states.stream, initialState: state);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Text('origin'),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, _) => BlocProvider<TaskEditBloc>.value(
                value: bloc,
                child: const TaskEditView(),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: TasksModuleLocalizations.localizationsDelegates,
        supportedLocales: TasksModuleLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    unawaited(router.push('/edit'));
    // No pumpAndSettle: while loading and saving, the indicator spins forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('loading, the indicator', (tester) async {
    await show(tester, const TaskEditLoading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the task that left the list', (tester) async {
    await show(tester, const TaskEditNotFound());
    expect(find.text('This task is no longer on the list'), findsOneWidget);
  });

  testWidgets('the field starts with the title, only once', (tester) async {
    await show(tester, const TaskEditLoading());

    states.add(TaskEditReady(bread));
    await tester.pump();
    await tester.pump();
    expect(fieldText(tester), 'Buy bread');

    await tester.enterText(find.byType(TextField), 'Buy whole wheat bread');
    states.add(TaskEditReady(bread));
    await tester.pump();
    await tester.pump();
    expect(fieldText(tester), 'Buy whole wheat bread');
  });

  testWidgets('save sends the raw text, through the button or the keyboard', (
    tester,
  ) async {
    await show(tester, TaskEditReady(bread));

    await tester.enterText(find.byType(TextField), ' Another ');
    await tester.tap(find.text('Save'));
    await tester.testTextInput.receiveAction(TextInputAction.done);

    final submitted = verify(
      () => bloc.add(captureAny(that: isA<TaskEditSubmitted>())),
    ).captured.cast<TaskEditSubmitted>();
    expect([for (final e in submitted) e.title], [' Another ', ' Another ']);
  });

  testWidgets('archive asks for confirmation', (tester) async {
    await show(tester, TaskEditReady(bread));

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.add(any(that: isA<TaskEditArchived>())));

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    verify(() => bloc.add(any(that: isA<TaskEditArchived>()))).called(1);
  });

  for (final (state, message) in [
    (
      TaskEditReady(bread, failure: const EmptyTaskTitleFailure()),
      'Write a title for the task.',
    ),
    (
      TaskEditReady(bread, failure: const TaskTitleTooLongFailure()),
      'The title is over the maximum length.',
    ),
    (
      TaskEditReady(bread, failure: const TaskNotFoundFailure()),
      'This task is no longer on the list.',
    ),
    (
      TaskEditReady(bread, unavailable: true),
      'Something went wrong. Please try again.',
    ),
  ]) {
    testWidgets('shows "$message"', (tester) async {
      await show(tester, state);
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('while saving, the buttons wait', (tester) async {
    await show(tester, TaskEditSaving(bread));

    final archive = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Archive'),
        matching: find.byType(TextButton),
      ),
    );
    expect(archive.onPressed, isNull);
  });

  testWidgets('once saved, the screen closes', (tester) async {
    await show(tester, TaskEditReady(bread));

    states.add(const TaskEditDone());
    await tester.pumpAndSettle();

    expect(find.text('origin'), findsOneWidget);
  });

  // Chapter 39: the system font enlarged, on a small phone. An overflow is a
  // Flutter error, which takeException returns; the chosen state is the one
  // that writes the most on screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets(
        'at ${scale}x, nothing overflows and "Save" and "Archive" can be '
        'reached',
        (tester) async {
          useSmallPhone(tester, textScale: scale);
          await show(tester, const TaskEditLoading());
          states.add(TaskEditReady(bread));
          await tester.pump();
          await tester.pump();

          expect(tester.takeException(), isNull);
          await expectReachable(tester, find.text('Save'));
          await expectReachable(tester, find.text('Archive'));
        },
      );
    }
  });
}
