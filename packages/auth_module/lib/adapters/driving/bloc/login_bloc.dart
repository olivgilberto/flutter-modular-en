import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/use_cases/auth_use_case.dart';
import '../../../domain/auth_failure.dart';

part 'login_event.dart';
part 'login_state.dart';

/// The ViewModel of the sign-in screen. It depends only on the use case,
/// the module's driving port.
///
/// Not `final`: the View tests mock it with `implements`, like
/// `AuthUseCase` (chapter 20).
class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required AuthUseCase auth})
    : _auth = auth,
      super(const LoginInitial()) {
    // One submission at a time: repeated taps while submitting are ignored.
    on<LoginSubmitted>(_onSubmitted, transformer: droppable());
  }

  final AuthUseCase _auth;

  Future<void> _onSubmitted(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    emit(const LoginSubmitInProgress());
    try {
      await _auth.signInWithPassword(
        email: event.email,
        password: event.password,
      );
      emit(const LoginSubmitSuccess());
    } on AuthFailure catch (failure) {
      emit(LoginSubmitFailure(failure));
    } on ApiError {
      emit(const LoginSubmitFailure.unavailable());
    } on LocalDatabaseError {
      // The session is stored in the module's database (chapter 21).
      emit(const LoginSubmitFailure.unavailable());
    }
  }
}
