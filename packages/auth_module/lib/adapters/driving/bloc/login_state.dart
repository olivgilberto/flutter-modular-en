part of 'login_bloc.dart';

/// States never override `==`: every emission reaches the screen.
sealed class LoginState {
  const LoginState();
}

final class LoginInitial extends LoginState {
  const LoginInitial();
}

final class LoginSubmitInProgress extends LoginState {
  const LoginSubmitInProgress();
}

/// The sign-in succeeded. The screen does not navigate: the host's
/// redirect, which observes the session, moves the user on.
final class LoginSubmitSuccess extends LoginState {
  const LoginSubmitSuccess();
}

final class LoginSubmitFailure extends LoginState {
  const LoginSubmitFailure(AuthFailure this.failure);
  const LoginSubmitFailure.unavailable() : failure = null;

  /// The business failure, or `null` when the cause was technical.
  final AuthFailure? failure;
}
