import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/dependency_injection.dart';
import 'package:mobile_tasks_app/bootstrap/error_handling.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeLogger logger;

  // The handlers are global: each test keeps the originals and restores them.
  late FlutterExceptionHandler? flutterOnError;
  late ErrorWidgetBuilder errorWidgetBuilder;

  setUp(() {
    flutterOnError = FlutterError.onError;
    errorWidgetBuilder = ErrorWidget.builder;
    logger = FakeLogger();
    getIt.pushNewScope(scopeName: 'test');
  });
  tearDown(() async {
    FlutterError.onError = flutterOnError;
    ErrorWidget.builder = errorWidgetBuilder;
    await getIt.popScopesTill('test');
  });

  test('a build or layout error goes to the AppLogger', () {
    getIt.registerSingleton<AppLogger>(logger);
    installGlobalErrorHandlers();

    FlutterError.onError!(FlutterErrorDetails(exception: StateError('bug')));

    expect(logger.fatals.single, isA<StateError>());
  });

  test('an unhandled async error goes to the AppLogger and counts '
      'as handled', () {
    getIt.registerSingleton<AppLogger>(logger);

    final handled = reportUncaughtError(StateError('bug'), StackTrace.current);

    expect(handled, isTrue);
    expect(logger.fatals.single, isA<StateError>());
  });

  test(
    'before injection, the error is neither lost nor brings the handler down',
    () {
      expect(
        () => reportUncaughtError(StateError('bug'), StackTrace.current),
        returnsNormally,
      );
    },
  );

  test('a failing widget becomes the design_system placeholder', () {
    installGlobalErrorHandlers();

    final widget = ErrorWidget.builder(
      FlutterErrorDetails(exception: StateError('bug')),
    );

    expect(widget, isA<AppErrorPlaceholder>());
  });
}
