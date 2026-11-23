import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasks_module/adapters/driving/bloc/task_conflicts_bloc.dart';
import 'package:tasks_module/adapters/driving/l10n/tasks_module_localizations.dart';
import 'package:tasks_module/adapters/driving/routes/tasks_module_routes.dart';
import 'package:tasks_module/adapters/driving/views/task_conflicts_view.dart';
import 'package:tasks_module/domain/entities/task.dart';
import 'package:tasks_module/domain/entities/task_conflict.dart';

import '../../support/text_scale.dart';
import 'driving_mocks.dart';

void main() {
  late MockTaskConflictsBloc bloc;
  late StreamController<TaskConflictsState> states;
  final mine = conflictOf(task('t-1', 'Buy whole wheat bread'));
  final refused = conflictOf(
    task('t-2', 'Pay the power bill'),
    id: 'c-2',
    reason: TaskConflictReason.rejected,
  );

  setUpAll(() => registerFallbackValue(const TaskConflictsStarted()));

  setUp(() {
    bloc = MockTaskConflictsBloc();
    states = StreamController<TaskConflictsState>();
  });
  // No await: a StreamController nobody listened to never finishes
  // closing.
  tearDown(() => unawaited(states.close()));

  Future<void> show(WidgetTester tester, TaskConflictsState state) async {
    whenListen(bloc, states.stream, initialState: state);
    final router = GoRouter(
      initialLocation: TaskRoutes.conflictsPath,
      routes: [
        GoRoute(
          name: TaskRoutes.conflicts,
          path: TaskRoutes.conflictsPath,
          builder: (_, _) => BlocProvider<TaskConflictsBloc>.value(
            value: bloc,
            child: const TaskConflictsView(),
          ),
        ),
        GoRoute(
          name: TaskRoutes.edit,
          path: TaskRoutes.editPath,
          builder: (_, state) => Text('edit ${state.pathParameters['taskId']}'),
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

  TaskConflictsState withServers(Map<String, ServerVersion> servers) =>
      TaskConflictsState(
        loading: false,
        conflicts: [mine, refused],
        servers: servers,
      );

  TextButton button(WidgetTester tester, String label) =>
      tester.widget<TextButton>(
        find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
      );

  List<TaskConflictResolved> resolved() => verify(
    () => bloc.add(captureAny(that: isA<TaskConflictResolved>())),
  ).captured.cast<TaskConflictResolved>();

  testWidgets('loading, the indicator', (tester) async {
    await show(tester, const TaskConflictsState());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('with no conflicts, nothing waits for a decision', (
    tester,
  ) async {
    await show(tester, const TaskConflictsState(loading: false));
    expect(find.text('Nothing waiting for your decision'), findsOneWidget);
  });

  testWidgets('both versions side by side, with the decisions for each '
      'reason', (tester) async {
    await show(
      tester,
      withServers({
        'c-1': ServerVersionFound(task('t-1', 'Buy French bread')),
        'c-2': ServerVersionFound(
          task('t-2', 'Pay the power bill', status: TaskStatus.done),
        ),
      }),
    );

    expect(find.text('This task changed somewhere else'), findsOneWidget);
    expect(find.text('The server rejected this change'), findsOneWidget);
    expect(
      find.textContaining('On this device: "Buy whole wheat bread"'),
      findsOneWidget,
    );
    expect(
      find.textContaining('On the server: "Buy French bread"'),
      findsOneWidget,
    );
    for (final label in [
      'Keep mine',
      'Keep the server\'s',
      'Redo',
      'Discard',
    ]) {
      expect(button(tester, label).onPressed, isNotNull, reason: label);
    }
  });

  testWidgets('while fetching the server version, only discard is '
      'enabled', (tester) async {
    await show(tester, withServers({}));

    expect(find.text('Fetching the server version…'), findsNWidgets(2));
    expect(button(tester, 'Keep mine').onPressed, isNull);
    expect(button(tester, 'Keep the server\'s').onPressed, isNull);
    expect(button(tester, 'Redo').onPressed, isNull);
    expect(button(tester, 'Discard').onPressed, isNotNull);
  });

  testWidgets('with no network, the fetch can be repeated', (tester) async {
    await show(
      tester,
      withServers({
        'c-1': const ServerVersionUnavailable(),
        'c-2': const ServerVersionUnavailable(),
      }),
    );

    await tester.tap(find.text('Try again').first);

    final requested =
        verify(
              () => bloc.add(captureAny(that: isA<ServerVersionRequested>())),
            ).captured.single
            as ServerVersionRequested;
    expect(requested.conflict, mine);
  });

  testWidgets('deleted on the server: keep mine is still possible, '
      'redo is not', (tester) async {
    await show(
      tester,
      withServers({
        'c-1': const ServerVersionFound(null),
        'c-2': const ServerVersionFound(null),
      }),
    );

    expect(
      find.text('On the server: the task no longer exists.'),
      findsNWidgets(2),
    );
    expect(button(tester, 'Keep mine').onPressed, isNotNull);
    expect(button(tester, 'Redo').onPressed, isNull);
  });

  testWidgets('the decision goes to the Bloc with the conflict', (
    tester,
  ) async {
    await show(
      tester,
      withServers({
        'c-1': ServerVersionFound(task('t-1', 'Buy French bread')),
        'c-2': ServerVersionFound(task('t-2', 'Pay the power bill')),
      }),
    );

    await tester.tap(find.text('Keep mine'));
    await tester.tap(find.text('Keep the server\'s'));
    await tester.tap(find.text('Redo'));

    expect(
      [for (final e in resolved()) (e.conflict.id, e.choice)],
      [
        ('c-1', TaskConflictChoice.keepMine),
        ('c-1', TaskConflictChoice.keepServer),
        ('c-2', TaskConflictChoice.redo),
      ],
    );
  });

  testWidgets('discard asks for confirmation', (tester) async {
    await show(tester, withServers({}));

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => bloc.add(any(that: isA<TaskConflictResolved>())));

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard').last);
    await tester.pumpAndSettle();
    expect(resolved().single.choice, TaskConflictChoice.discard);
  });

  testWidgets('during the decision, the conflict\'s buttons wait', (
    tester,
  ) async {
    await show(
      tester,
      TaskConflictsState(
        loading: false,
        conflicts: [refused],
        servers: {'c-2': ServerVersionFound(task('t-2', 'Pay the power bill'))},
        resolving: 'c-2',
      ),
    );

    expect(button(tester, 'Redo').onPressed, isNull);
    expect(button(tester, 'Discard').onPressed, isNull);
  });

  testWidgets('redo opens the task\'s screen in place of this one', (
    tester,
  ) async {
    await show(tester, withServers({}));

    states.add(withServers({}).copyWith(redoTaskId: 't-2'));
    await tester.pumpAndSettle();

    expect(find.text('edit t-2'), findsOneWidget);
  });

  for (final (notice, message) in [
    (
      TaskConflictsNotice.offline,
      'No connection to the server. Try again when it is back.',
    ),
    (
      TaskConflictsNotice.unavailable,
      'Something went wrong. Please try again.',
    ),
  ]) {
    testWidgets('the ${notice.name} notice', (tester) async {
      await show(tester, withServers({}));

      states.add(withServers({}).copyWith(notice: notice));
      await tester.pump();
      // The SnackBar comes in on the frame after the notice.
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text(message), findsOneWidget);
    });
  }

  // Chapter 39: the system font enlarged, on a small phone. An overflow is a
  // Flutter error, which takeException returns; the chosen state is the one
  // that writes the most on screen.
  group('with the system font enlarged', () {
    for (final scale in systemTextScales) {
      testWidgets('at ${scale}x, nothing overflows and both conflicts\' '
          'decisions can be reached', (tester) async {
        useSmallPhone(tester, textScale: scale);
        await show(
          tester,
          withServers({
            'c-1': ServerVersionFound(task('t-1', 'Buy French bread')),
            'c-2': ServerVersionFound(
              task('t-2', 'Pay the power bill', status: TaskStatus.done),
            ),
          }),
        );

        expect(tester.takeException(), isNull);
        for (final label in [
          'Keep mine',
          'Keep the server\'s',
          'Redo',
          'Discard',
        ]) {
          await expectReachable(tester, find.text(label));
        }
      });
    }
  });
}
