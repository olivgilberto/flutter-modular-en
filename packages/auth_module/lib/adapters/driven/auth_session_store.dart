import 'models/auth_model.dart';

/// What `RestAuthService` needs from the session beyond the `core`'s
/// `TokenProvider` port. Internal to the module, never exported: no other
/// module can store or erase the session.
abstract interface class AuthSessionStore {
  /// The stored session, or `null` if there is none.
  Future<AuthModel?> current();

  Future<void> save(AuthModel session);

  Future<void> clear();

  /// Emits when the session expires and cannot be refreshed.
  Stream<void> get expirations;
}
