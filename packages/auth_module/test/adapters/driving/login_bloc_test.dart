import 'dart:async';

import 'package:auth_module/adapters/driving/bloc/login_bloc.dart';
import 'package:auth_module/domain/auth_failure.dart';
import 'package:auth_module/domain/entities/user.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'driving_mocks.dart';

void main() {
  late MockAuthUseCase auth;

  setUp(() => auth = MockAuthUseCase());

  void signInAnswers(Future<User> Function() answer) => when(
    () => auth.signInWithPassword(
      email: any(named: 'email'),
      password: any(named: 'password'),
    ),
  ).thenAnswer((_) => answer());

  const submitted = LoginSubmitted(
    email: 'ana@example.com',
    password: strongPassword,
  );

  blocTest<LoginBloc, LoginState>(
    'hands the raw text to the use case and emits InProgress and Success',
    setUp: () => signInAnswers(() async => ana),
    build: () => LoginBloc(auth: auth),
    act: (bloc) => bloc.add(submitted),
    expect: () => [isA<LoginSubmitInProgress>(), isA<LoginSubmitSuccess>()],
    verify: (_) => verify(
      () => auth.signInWithPassword(
        email: 'ana@example.com',
        password: strongPassword,
      ),
    ).called(1),
  );

  blocTest<LoginBloc, LoginState>(
    'a Failure becomes a failure state that carries it',
    setUp: () =>
        signInAnswers(() => Future.error(const InvalidCredentialsFailure())),
    build: () => LoginBloc(auth: auth),
    act: (bloc) => bloc.add(submitted),
    expect: () => [
      isA<LoginSubmitInProgress>(),
      isA<LoginSubmitFailure>().having(
        (state) => state.failure,
        'failure',
        isA<InvalidCredentialsFailure>(),
      ),
    ],
  );

  for (final (name, error) in [
    ('ApiError', const ApiError(ApiErrorKind.unreachable)),
    ('LocalDatabaseError', const LocalDatabaseError('session write')),
  ]) {
    blocTest<LoginBloc, LoginState>(
      '$name becomes the technical failure, with no Failure',
      setUp: () => signInAnswers(() => Future.error(error)),
      build: () => LoginBloc(auth: auth),
      act: (bloc) => bloc.add(submitted),
      expect: () => [
        isA<LoginSubmitInProgress>(),
        isA<LoginSubmitFailure>().having(
          (state) => state.failure,
          'failure',
          isNull,
        ),
      ],
    );
  }

  blocTest<LoginBloc, LoginState>(
    'a bug is not caught: it reaches onError and no failure state comes out',
    setUp: () => signInAnswers(() => Future.error(StateError('bug'))),
    build: () => LoginBloc(auth: auth),
    act: (bloc) => bloc.add(submitted),
    expect: () => [isA<LoginSubmitInProgress>()],
    errors: () => [isA<StateError>()],
  );

  final pending = Completer<User>();
  blocTest<LoginBloc, LoginState>(
    'droppable: a second submission during the first one is ignored',
    setUp: () => signInAnswers(() => pending.future),
    build: () => LoginBloc(auth: auth),
    act: (bloc) async {
      bloc
        ..add(submitted)
        ..add(submitted);
      await Future<void>.delayed(Duration.zero);
      pending.complete(ana);
      await Future<void>.delayed(Duration.zero);
    },
    expect: () => [isA<LoginSubmitInProgress>(), isA<LoginSubmitSuccess>()],
    verify: (_) => verify(
      () => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      ),
    ).called(1),
  );
}
