import '../models/auth_model.dart';

/// The local source of the session: a single row that survives the app
/// closing and can be read by background sync.
abstract interface class AuthSessionLocalService {
  Future<AuthModel?> read();
  Future<void> write(AuthModel session);
  Future<void> delete();
}
