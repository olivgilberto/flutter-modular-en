part of 'session_bloc.dart';

sealed class SessionEvent {
  const SessionEvent();
}

/// Fired by the host at boot: reads the session stored on the device.
final class SessionRestoreRequested extends SessionEvent {
  const SessionRestoreRequested();
}

/// From the sign-in screen, after an expired session with unsent changes:
/// the user prefers to discard them rather than sign in again.
final class SessionDiscardRequested extends SessionEvent {
  const SessionDiscardRequested();
}

/// Internal: what the use case published.
final class _SignedInChanged extends SessionEvent {
  const _SignedInChanged(this.signedIn);

  final bool signedIn;
}

final class _SessionExpired extends SessionEvent {
  const _SessionExpired();
}
