part of 'register_bloc.dart';

sealed class RegisterState {
  const RegisterState();
}

final class RegisterInitial extends RegisterState {
  const RegisterInitial();
}

final class RegisterSubmitInProgress extends RegisterState {
  const RegisterSubmitInProgress();
}

/// The account was created and the session has already started; as with
/// sign-in, the host is the one that moves the user on.
final class RegisterSubmitSuccess extends RegisterState {
  const RegisterSubmitSuccess();
}

final class RegisterSubmitFailure extends RegisterState {
  const RegisterSubmitFailure(AuthFailure this.failure);
  const RegisterSubmitFailure.unavailable() : failure = null;

  final AuthFailure? failure;
}
