import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/observability/app_bloc_observer.dart';

import '../support/fakes.dart';

final class _CounterCubit extends Cubit<int> {
  _CounterCubit() : super(0);

  /// What a handler would do with an error it does not know how to handle.
  void fail() => addError(StateError('bug'));
}

void main() {
  test('an error that escapes a Bloc reaches the crash log, as non-'
      'fatal', () async {
    final previous = Bloc.observer;
    addTearDown(() => Bloc.observer = previous);
    final logger = FakeLogger();
    Bloc.observer = AppBlocObserver(logger);

    final cubit = _CounterCubit()..fail();
    await cubit.close();

    expect(logger.errors, ['bloc _CounterCubit']);
    expect(logger.fatals, isEmpty);
  });
}
