import 'package:auth_module/adapters/driving/bloc/logout_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'driving_mocks.dart';

void main() {
  late MockAuthUseCase auth;

  setUp(() => auth = MockAuthUseCase());

  blocTest<LogoutBloc, LogoutState>(
    'the request counts the pending changes and does not sign out yet',
    setUp: () => when(() => auth.pendingChanges()).thenAnswer((_) async => 2),
    build: () => LogoutBloc(auth: auth),
    act: (bloc) => bloc.add(const LogoutRequested()),
    expect: () => [
      isA<LogoutCheckInProgress>(),
      isA<LogoutCheckSuccess>().having(
        (state) => state.pendingChanges,
        'pendingChanges',
        2,
      ),
    ],
    verify: (_) => verifyNever(() => auth.signOut()),
  );

  blocTest<LogoutBloc, LogoutState>(
    'unable to count, the request ends in a check failure',
    setUp: () => when(
      () => auth.pendingChanges(),
    ).thenThrow(const LocalDatabaseError('unreadable queue')),
    build: () => LogoutBloc(auth: auth),
    act: (bloc) => bloc.add(const LogoutRequested()),
    expect: () => [isA<LogoutCheckInProgress>(), isA<LogoutCheckFailure>()],
  );

  blocTest<LogoutBloc, LogoutState>(
    'the confirmation ends the session through the use case',
    setUp: () => when(() => auth.signOut()).thenAnswer((_) async {}),
    build: () => LogoutBloc(auth: auth),
    act: (bloc) => bloc.add(const LogoutConfirmed()),
    expect: () => [isA<LogoutSubmitInProgress>(), isA<LogoutSubmitSuccess>()],
    verify: (_) => verify(() => auth.signOut()).called(1),
  );

  blocTest<LogoutBloc, LogoutState>(
    'with no network, the session ends just the same: the local data is gone',
    setUp: () => when(
      () => auth.signOut(),
    ).thenThrow(const ApiError(ApiErrorKind.unreachable)),
    build: () => LogoutBloc(auth: auth),
    act: (bloc) => bloc.add(const LogoutConfirmed()),
    expect: () => [isA<LogoutSubmitInProgress>(), isA<LogoutSubmitSuccess>()],
  );

  blocTest<LogoutBloc, LogoutState>(
    'a cleanup failure ends in a submission failure',
    setUp: () => when(
      () => auth.signOut(),
    ).thenThrow(const LocalDatabaseError('database locked')),
    build: () => LogoutBloc(auth: auth),
    act: (bloc) => bloc.add(const LogoutConfirmed()),
    expect: () => [isA<LogoutSubmitInProgress>(), isA<LogoutSubmitFailure>()],
  );
}
