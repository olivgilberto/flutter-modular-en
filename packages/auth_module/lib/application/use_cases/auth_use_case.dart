import 'dart:async';

import 'package:core/core.dart';

import '../../domain/entities/user.dart';
import '../../domain/value_objects/email_address.dart';
import '../../domain/value_objects/password.dart';
import '../ports/auth_repository.dart';
import '../ports/data_owner_repository.dart';

/// The authentication's driving port: one use case for the whole feature.
/// It receives raw text from the screen and only hands valid value objects
/// to the port.
///
/// Not `final`: the Bloc tests (chapter 22) mock it with `implements`, which a `final class` would forbid outside this file.
class AuthUseCase {
  AuthUseCase({
    required AuthRepository repository,
    required DataOwnerRepository owner,
    required LogoutCleanerRegistry cleaners,
    required OutboxRegistry outboxes,
    required AppLogger logger,
    required AppAnalytics analytics,
  }) : _repository = repository,
       _owner = owner,
       _cleaners = cleaners,
       _outboxes = outboxes,
       _logger = logger,
       _analytics = analytics;

  final AuthRepository _repository;

  /// The owner of the data the modules store on the device. A session that
  /// expired with unsent changes has not erased that data yet, and the
  /// owner stays stored until it leaves, even after a restart
  /// (chapters 29 and 32).
  final DataOwnerRepository _owner;
  final LogoutCleanerRegistry _cleaners;
  final OutboxRegistry _outboxes;
  final AppLogger _logger;
  final AppAnalytics _analytics;
  final _signedIn = StreamController<bool>.broadcast();

  /// The expiry noticed at boot: someone's data on the device and no
  /// stored session (chapter 32).
  final _expiredBeforeStart = StreamController<void>.broadcast();

  /// The session state, from the use case's point of view: `true` when
  /// someone signed in (sign-in, sign-up, or restored session), `false` when
  /// the session ended, always after the data cleanup (chapter 11).
  /// The `SessionBloc` observes it, never the token.
  Stream<bool> watchSignedIn() => _signedIn.stream;

  /// `async` so that a validation failure arrives as an error of the
  /// `Future`, not as a synchronous exception before the future exists.
  ///
  /// The owner is read before going to the backend: if it cannot be read,
  /// the sign-in is refused before any token is stored (chapter 32).
  Future<User> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final validEmail = EmailAddress.parse(email);
    final validPassword = Password.parse(password);
    final previousOwner = await _owner.currentOwner();
    final user = await _repository.signInWithPassword(
      validEmail,
      validPassword,
    );
    await _takeOwnership(user, previousOwner);
    _sessionStarted(user, method: 'password');
    return user;
  }

  Future<User> registerAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final validEmail = EmailAddress.parse(email);
    final validPassword = Password.parse(password);
    final previousOwner = await _owner.currentOwner();
    final user = await _repository.registerAccount(
      name: name.trim(),
      email: validEmail,
      password: validPassword,
    );
    await _takeOwnership(user, previousOwner);
    _identify(user);
    _signedIn.add(true);
    unawaited(_analytics.logEvent('auth_account_registered'));
    return user;
  }

  /// Called at boot. A restored session identifies the user in crash
  /// reports, but it is not a product event.
  ///
  /// With no stored session, but with someone's data on the device, that
  /// person's session expired with unsent changes before the app was
  /// closed: the boot returns to the same point, along the same path as the
  /// expiry (chapter 32).
  Future<User?> restoreSession() async {
    final previousOwner = await _owner.currentOwner();
    final user = await _repository.restoreSession();
    if (user == null) {
      if (previousOwner == null) {
        _signedIn.add(false);
      } else {
        _expiredBeforeStart.add(null);
      }
      return null;
    }
    await _takeOwnership(user, previousOwner);
    _identify(user);
    _signedIn.add(true);
    return user;
  }

  /// How many changes made offline have not been sent yet. The screen asks
  /// for confirmation before signing out when there are any.
  Future<int> pendingChanges() => _outboxes.pendingOperations();

  /// Ends the session on the backend and, whatever happens, erases every
  /// module's local data and forgets the user in the reports.
  Future<void> signOut() async {
    try {
      await _repository.signOut();
    } finally {
      await _forgetLocalSession();
    }
    unawaited(_analytics.logEvent('auth_session_ended'));
  }

  /// The expiry noticed by the refused refresh and the one noticed at boot.
  Stream<void> watchSessionExpired() => Stream.multi((controller) {
    final subscriptions = [
      _repository.watchSessionExpired().listen(controller.add),
      _expiredBeforeStart.stream.listen(controller.add),
    ];
    controller.onCancel = () => Future.wait([
      for (final subscription in subscriptions) subscription.cancel(),
    ]);
  });

  /// Ends a session that has already expired on the server: it only cleans
  /// up the local data, because there is nothing to end on the backend.
  Future<void> endExpiredSession() async {
    await _forgetLocalSession();
    unawaited(_analytics.logEvent('auth_session_expired'));
  }

  void _sessionStarted(User user, {required String method}) {
    _identify(user);
    _signedIn.add(true);
    unawaited(_analytics.logEvent('auth_session_started', {'method': method}));
  }

  void _identify(User user) => _logger.setUserId(user.id);

  /// Someone else signing in after an expired session that still held
  /// changes: the previous person's data is erased before the new session
  /// starts (chapter 11), and only then does the owner change. If the
  /// cleanup fails, the previous owner stays stored, and the next sign-in
  /// tries again. The same person finds everything as they left it, and the outbox goes on.
  Future<void> _takeOwnership(User user, String? previousOwner) async {
    if (previousOwner == user.id) return;
    if (previousOwner != null) await _clearAll();
    await _owner.saveOwner(user.id);
  }

  /// A cleanup failure goes to the crash log and up to the caller: someone
  /// else's data may have been left on the device.
  Future<void> _clearAll() async {
    try {
      await _cleaners.clearAll();
    } on Exception catch (error, stackTrace) {
      _logger.error('auth clear local data', error, stackTrace);
      rethrow;
    }
  }

  /// The owner only leaves after the data: a cleanup that failed leaves the
  /// owner stored, and the next sign-in by someone else erases again.
  Future<void> _forgetLocalSession() async {
    try {
      await _clearAll();
      await _owner.clearOwner();
    } finally {
      _logger.setUserId(null);
      // After the cleanup, even if it fails: the tokens are already erased,
      // and the session is over either way.
      _signedIn.add(false);
    }
  }
}
