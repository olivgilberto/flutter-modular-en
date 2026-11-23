import '../../domain/entities/user.dart';
import '../../domain/value_objects/email_address.dart';
import '../../domain/value_objects/password.dart';

/// The authentication's driven port: what the module needs from the
/// outside world, in its own terms. Technical failures arrive as the
/// `core` errors (`ApiError`, `LocalDatabaseError`).
abstract interface class AuthRepository {
  /// Throws `InvalidCredentialsFailure` when the backend rejects the email
  /// and password.
  Future<User> signInWithPassword(EmailAddress email, Password password);

  /// Throws `EmailAlreadyRegisteredFailure` when the email already exists
  /// and `WeakPasswordFailure` when the backend rejects the password.
  Future<User> registerAccount({
    required String name,
    required EmailAddress email,
    required Password password,
  });

  /// The user of the session stored on the device, or `null` if there is none.
  Future<User?> restoreSession();

  /// Ends the session on the backend and discards the local token.
  Future<void> signOut();

  /// Emits when the session expires and cannot be refreshed (chapter 11).
  Stream<void> watchSessionExpired();
}
