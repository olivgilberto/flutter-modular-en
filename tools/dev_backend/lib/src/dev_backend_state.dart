import 'dart:convert';
import 'dart:math';

/// An account. The password stays in plain text because nothing here leaves
/// the memory of a development process; a real backend only stores the
/// hash.
final class DevUser {
  DevUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String password;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// A session's two tokens. The access one expires; the refresh one changes
/// on every use.
final class DevSession {
  DevSession({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String userId;
  String accessToken;
  String refreshToken;
  DateTime expiresAt;
}

/// A task, with the version that goes up on every accepted change and the
/// ids of the operations that produced it (chapter 12): resending an
/// operation already applied gets the task as it is, not a conflict.
final class DevTask {
  DevTask({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String ownerId;
  String title;
  String status;
  final DateTime createdAt;
  int version = 1;
  final Set<String> appliedOperations = {};

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'version': version,
  };
}

/// The next task write the backend will refuse, requested by the
/// development route: the way to see a refusal that is not a conflict.
final class DevRejection {
  const DevRejection({this.status = 422, this.code = 'rejected_by_dev'});

  final int status;
  final String code;
}

/// A response stored under an Idempotency-Key.
final class DevStoredResponse {
  const DevStoredResponse(this.requestBody, this.status, this.body);

  final String requestBody;
  final int status;
  final Object? body;
}

/// The backend's whole state, in memory.
final class DevBackendState {
  DevBackendState({
    DateTime Function()? now,
    this.tokenTtl = const Duration(minutes: 15),
    Random? random,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  final DateTime Function() _now;
  final Random _random;

  /// How long an access token is valid.
  final Duration tokenTtl;

  final users = <String, DevUser>{}; // by email, lowercased
  final sessions = <DevSession>[];
  final tasks = <String, DevTask>{}; // by the id the app generated
  final idempotency = <String, DevStoredResponse>{}; // user + key
  DevRejection? rejectNext;

  /// The next accepted write answers without the version: a server defect,
  /// to see the non-fatal error reach Crashlytics (chapter 38).
  var omitVersionNext = false;
  var _nextUser = 0;

  DateTime now() => _now();

  String newUserId() => 'u-${++_nextUser}';

  /// An opaque, random token.
  String newToken() =>
      base64Url.encode(List.generate(24, (_) => _random.nextInt(256)));

  DevSession openSession(DevUser user) {
    final session = DevSession(
      userId: user.id,
      accessToken: newToken(),
      refreshToken: newToken(),
      expiresAt: now().add(tokenTtl),
    );
    sessions.add(session);
    return session;
  }

  /// The session of a still valid access token.
  DevSession? sessionOf(String accessToken) {
    for (final session in sessions) {
      if (session.accessToken == accessToken) {
        return now().isBefore(session.expiresAt) ? session : null;
      }
    }
    return null;
  }

  DevUser? userById(String id) {
    for (final user in users.values) {
      if (user.id == id) return user;
    }
    return null;
  }

  /// Development route: every access token expires now.
  void expireTokens() {
    final past = now().subtract(const Duration(seconds: 1));
    for (final session in sessions) {
      session.expiresAt = past;
    }
  }

  void reset() {
    users.clear();
    sessions.clear();
    tasks.clear();
    idempotency.clear();
    rejectNext = null;
    omitVersionNext = false;
    _nextUser = 0;
  }
}
