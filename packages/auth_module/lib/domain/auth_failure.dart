import 'package:core/core.dart';

/// The business deviations of authentication: everything the user can
/// fix. No failure carries text; the View decides the message.
sealed class AuthFailure implements Failure {
  const AuthFailure();
}

/// The text is not shaped like an email (checked on the device).
final class InvalidEmailFailure extends AuthFailure {
  const InvalidEmailFailure();
}

/// The password does not meet the policy (the length, checked on the
/// device, or the list of compromised passwords, checked by the backend).
final class WeakPasswordFailure extends AuthFailure {
  const WeakPasswordFailure();
}

/// The backend rejected the email and the password.
final class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure();
}

/// The backend already has an account with that email.
final class EmailAlreadyRegisteredFailure extends AuthFailure {
  const EmailAlreadyRegisteredFailure();
}
