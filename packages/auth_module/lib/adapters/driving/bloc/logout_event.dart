part of 'logout_bloc.dart';

sealed class LogoutEvent {
  const LogoutEvent();
}

/// The tap on "Sign out": first, count what has not been sent yet.
final class LogoutRequested extends LogoutEvent {
  const LogoutRequested();
}

/// The decision to sign out, direct (nothing pending) or confirmed by the user.
final class LogoutConfirmed extends LogoutEvent {
  const LogoutConfirmed();
}
