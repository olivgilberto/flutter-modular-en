import '../../../domain/entities/user.dart';
import '../../../domain/value_objects/email_address.dart';

/// The session as the backend delivers it and as the local database stores
/// it: the user and both tokens. Hand-written serialization, in both formats.
final class AuthModel {
  const AuthModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
  });

  /// The sign-in and sign-up response. Extra keys are ignored; a missing
  /// key, or one of another type, is a [FormatException].
  factory AuthModel.fromJson(Object? json) {
    if (json case {
      'user': {'id': String userId, 'name': String name, 'email': String email},
      'accessToken': String accessToken,
      'refreshToken': String refreshToken,
    }) {
      return AuthModel(
        userId: userId,
        name: name,
        email: email,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    throw const FormatException(
      'Authentication response in an unexpected format',
    );
  }

  /// The row of the `session` table in the module's database.
  factory AuthModel.fromMap(Map<String, Object?> row) {
    if (row case {
      'user_id': String userId,
      'name': String name,
      'email': String email,
      'access_token': String accessToken,
      'refresh_token': String refreshToken,
    }) {
      return AuthModel(
        userId: userId,
        name: name,
        email: email,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    }
    throw const FormatException('Stored session in an unexpected format');
  }

  final String userId;
  final String name;
  final String email;
  final String accessToken;
  final String refreshToken;

  Map<String, Object?> toMap() => {
    'user_id': userId,
    'name': name,
    'email': email,
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };

  /// The same session with the refreshed tokens.
  AuthModel withTokens({
    required String accessToken,
    required String refreshToken,
  }) => AuthModel(
    userId: userId,
    name: name,
    email: email,
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  /// May throw `InvalidEmailFailure`: the caller decides what that means,
  /// because the data came from outside (chapter 9).
  User toEntity() =>
      User(id: userId, name: name, email: EmailAddress.parse(email));
}
