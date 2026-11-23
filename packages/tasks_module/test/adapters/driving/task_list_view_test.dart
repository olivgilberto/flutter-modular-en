import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driving/bloc/task_list_bloc.dart';
import 'package:tasks_module/adapters/driving/l10n/tasks_module_localizations.dart';
import 'package:tasks_module/adapters/driving/routes/tasks_module_routes.dart';
import 'package:tasks_module/adapters/driving/views/task_list_view.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  late MockTaskListBloc bloc;
  late StreamController<TaskListState> states;

  setUpAll(() => registerFallbackValue(const TaskListStarted()));

  setUp(() {
    bloc = MockTaskListBloc();
    states = StreamController<TaskListState>();
  });
  // No await: a StreamController nobody listened to never finishes
  // closing.
  tearDown(() => unawaited(states.close()));

  /// The View with a mocked Bloc and a router with the neighboring routes
  /// in place of the real screens.
  Future<void> show(WidgetTester tester, TaskListState state) async {
    whenListen(bloc, states.stream, initialState: state);
    final router = GoRouter(
      initialLocation: TaskRoutes.listPath,
      routes: [
        GoRoute(
          name: TaskRoutes.list,
          path: TaskRoutes.listPath,
          builder: (_, _) => BlocProvider<TaskListBloc>.value(
            value: bloc,
            child: const TaskListView(),
          ),
        ),
        GoRoute(
          name: TaskRoutes.edit,
          path: TaskRoutes.editPath,
          builder: (_, state) => Text('edit ${state.pathParameters['taskId']}'),
        ),
        GoRoute(
          name: TaskRoutes.conflicts,
          path: TaskRoutes.conflictsPath,
          builder: (_, _) => const Text('conflicts'),
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
    await tester.pump();
  }

  TaskListState ready({int conflicts = 0, bool showCompleted = true}) =>
      TaskListState(
        status: TaskListStatus.ready,
        tasks: [bread, light],
        conflicts: conflicts,
        showCompleted: showCompleted,
      );

  testWidgets('shows the tasks, with the done one struck through', (
    tester,
  ) async {
    await show(tester, ready());

    expect(find.text('Buy bread'), findsOneWidget);
    final done = tester.widget<Text>(find.text('Pay the power bill'));
    expect(done.style?.decoration, TextDecoration.lineThrough);
    expect(find.textContaining('decision'), findsNothing);
  });

  testWidgets('with done tasks hidden, only the open ones appear', (
    tester,
  ) async {
    await show(tester, ready(showCompleted: false));

    expect(find.text('Pay the power bill'), findsNothing);
    await tester.tap(find.byTooltip('Show completed'));
    verify(() => bloc.add(any(that: isA<ShowCompletedToggled>()))).called(1);
  });

  testWidgets('with no tasks, the empty state invites writing the first one', (
    tester,
  ) async {
    await show(tester, const TaskListState(status: TaskListStatus.ready));

    expect(find.text('No tasks here'), findsOneWidget);
  });

  testWidgets('loading, the indicator', (tester) async {
    await show(tester, const TaskListState());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a failed first load offers to try again', (tester) async {
    await show(tester, const TaskListState(status: TaskListStatus.failure));

    expect(find.text('Couldn\'t load the tasks'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    verify(() => bloc.add(any(that: isA<TaskListStarted>()))).called(1);
  });

  testWidgets('create sends the raw text, through the button or the keyboard', (
    tester,
  ) async {
    await show(tester, ready());

    await tester.enterText(find.byType(TextField), '  Wash the car ');
    await tester.tap(find.byTooltip('Add'));
    await tester.testTextInput.receiveAction(TextInputAction.done);

    final created = verify(
      () => bloc.add(captureAny(that: isA<TaskCreated>())),
    ).captured.cast<TaskCreated>();
    expect(
      [for (final e in created) e.title],
      ['  Wash the car ', '  Wash the car '],
    );
  });

  testWidgets('a created task clears the field', (tester) async {
    await show(tester, ready());
    await tester.enterText(find.byType(TextField), 'Wash the car');

    states.add(ready().copyWith(notice: TaskListNotice.created));
    await tester.pump();

    expect(find.text('Wash the car'), findsNothing);
  });

  testWidgets('toggling sends the tapped task', (tester) async {
    await show(tester, ready());

    await tester.tap(find.byType(Checkbox).first);

    final toggled =
        verify(
              () => bloc.add(captureAny(that: isA<TaskToggled>())),
            ).captured.single
            as TaskToggled;
    expect(toggled.task, bread);
  });

  testWidgets('edit opens the task\'s screen', (tester) async {
    await show(tester, ready());

    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();

    expect(find.text('edit t-1'), findsOneWidget);
  });

  testWidgets(
    'with conflicts, the notice counts them and leads to the decision screen',
    (tester) async {
      await show(tester, ready(conflicts: 2));

      expect(find.text('2 changes need your decision'), findsOneWidget);
      // The list stays whole below the notice.
      expect(find.text('Buy bread'), findsOneWidget);
      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();

      expect(find.text('conflicts'), findsOneWidget);
    },
  );

  testWidgets('one conflict, in the singular', (tester) async {
    await show(tester, ready(conflicts: 1));

    expect(find.text('1 change needs your decision'), findsOneWidget);
  });

  for (final (notice, message) in [
    (TaskListNotice.emptyTitle, 'Write a title for the task.'),
    (TaskListNotice.titleTooLong, 'The title is over the maximum length.'),
    (TaskListNotice.notFound, 'This task is no longer on the list.'),
    (
      TaskListNotice.refreshFailed,
      'Couldn\'t refresh right now. The list on this device is still here.',
    ),
    (TaskListNotice.unavailable, 'Something went wrong. Please try again.'),
  ]) {
    testWidgets('the ${notice.name} notice appears once', (tester) async {
      await show(tester, ready());

      states.add(ready().copyWith(notice: notice));
      await tester.pump();
      // The SnackBar comes in on the frame after the notice.
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('pull to refresh waits for the refresh to finish', (
    tester,
  ) async {
    await show(tester, ready());

    await tester.fling(find.text('Buy bread'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    verify(() => bloc.add(any(that: isA<TaskListRefreshed>()))).called(1);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);

    states
      ..add(ready().copyWith(refreshing: true))
      ..add(ready());
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  // Chapter 39: the system font enlarged, on a small phone. An overflow is a
  // Flutter error, which takeException returns; the chosen state is the one
  // that writes the most on screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets('at ${scale}x, nothing overflows, and the field, "Add", and '
          'the conflicts notice can be reached', (tester) async {
        useSmallPhone(tester, textScale: scale);
        await show(tester, ready(conflicts: 2));

        expect(tester.takeException(), isNull);
        // Top to bottom: the list builds its rows on demand, and a row that
        // scrolled far out of view is no longer in the tree.
        await expectReachable(tester, find.text('Resolve'));
        await expectReachable(tester, find.byTooltip('Add'));
        await expectReachable(tester, find.text('Buy bread'));
      });
    }
  });
}
