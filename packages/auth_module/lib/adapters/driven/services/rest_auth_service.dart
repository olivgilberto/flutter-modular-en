import 'package:core/core.dart';

import '../../../application/ports/auth_repository.dart';
import '../../../domain/auth_failure.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/value_objects/email_address.dart';
import '../../../domain/value_objects/password.dart';
import '../auth_api_paths.dart';
import '../auth_session_store.dart';
import '../models/auth_model.dart';

/// The [AuthRepository] port over the REST backend. A single source, so the
/// Service implements the port directly (chapter 8).
final class RestAuthService implements AuthRepository {
  RestAuthService({
    required ApiClient apiClient,
    required AuthSessionStore session,
  }) : _api = apiClient,
       _session = session;

  final ApiClient _api;
  final AuthSessionStore _session;

  @override
  Future<User> signInWithPassword(EmailAddress email, Password password) =>
      _authenticate(
        AuthApiPaths.signIn,
        body: {'email': email.value, 'password': password.value},
      );

  @override
  Future<User> registerAccount({
    required String name,
    required EmailAddress email,
    required Password password,
  }) => _authenticate(
    AuthApiPaths.register,
    body: {'name': name, 'email': email.value, 'password': password.value},
  );

  /// Read from the device, without the network: the app opens signed in even offline.
  @override
  Future<User?> restoreSession() async {
    final stored = await _session.current();
    if (stored == null) return null;
    try {
      return stored.toEntity();
    } on Failure {
      throw const LocalDatabaseError('stored session with an invalid email');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _api.post(AuthApiPaths.signOut);
    } finally {
      await _session.clear();
    }
  }

  @override
  Stream<void> watchSessionExpired() => _session.expirations;

  /// The session is only stored after the whole response has been read: an
  /// invalid response never leaves a token behind.
  Future<User> _authenticate(String path, {required Object body}) async {
    final auth = _readAuth(await _post(path, body: body));
    await _session.save(auth.model);
    return auth.user;
  }

  Future<Object?> _post(String path, {required Object body}) async {
    try {
      return await _api.post(path, body: body);
    } on ApiError catch (error) {
      if (_businessFailureOf(error) case final failure?) throw failure;
      rethrow;
    }
  }

  /// The only conversion of a technical error into a business failure
  /// (chapter 9): status and code, never the message text.
  static AuthFailure? _businessFailureOf(ApiError error) => switch (error) {
    ApiError(statusCode: 401, body: {'code': 'invalid_credentials'}) =>
      const InvalidCredentialsFailure(),
    ApiError(statusCode: 422, body: {'code': 'email_already_registered'}) =>
      const EmailAlreadyRegisteredFailure(),
    ApiError(statusCode: 422, body: {'code': 'weak_password'}) =>
      const WeakPasswordFailure(),
    _ => null,
  };

  /// Invalid data coming from the server is a defect of the response, not
  /// of what the user typed (chapter 9).
  static ({AuthModel model, User user}) _readAuth(Object? json) {
    try {
      final model = AuthModel.fromJson(json);
      return (model: model, user: model.toEntity());
    } on FormatException {
      throw const ApiError(ApiErrorKind.invalidResponse);
    } on Failure {
      throw const ApiError(ApiErrorKind.invalidResponse);
    }
  }
}
