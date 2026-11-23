part of 'login_bloc.dart';

sealed class LoginEvent {
  const LoginEvent();
}

/// The raw text of the fields: the use case does the validating.
final class LoginSubmitted extends LoginEvent {
  const LoginSubmitted({required this.email, required this.password});

  final String email;
  final String password;
}
