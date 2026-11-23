# auth_module

## Scope
Sign-in with email and password, registration, session restored at boot,
sign-out that clears every module's data, and expired sessions.

## Architecture
- domain/: User (equality by id), EmailAddress and Password (value objects
  with parse), the sealed AuthFailure family.
- application/: the AuthRepository port and the AuthUseCase, which validates
  the screen's text, identifies the user in the AppLogger (opaque id), and
  logs the auth_session_started, auth_account_registered,
  auth_session_ended, and auth_session_expired events.
- adapters/driven/: chapter 21. adapters/driving/: chapter 22.

## Password policy
NIST SP 800-63B-4, password as the only factor: 15 to 128 characters,
counted as code points, with no composition rules. The list of compromised
passwords is checked by the backend, which answers with the weak password
code (WeakPasswordFailure).

## Tests
Domain and application in pure Dart, with mocktail for the ports
(chapter 20). Driven side with a simulated ApiClient and the session database
on the computer (chapter 21). Driving side (chapter 22): Blocs with
bloc_test and a simulated AuthUseCase, Views with a MockBloc in a fixed
state, routes with a test GoRouter. Chapter 39: each View also with the
system font at 1.0, 2.0, and 3.0, on a 375 × 667 point phone
(test/support/text_scale.dart); the sign-out confirmation scrolls, through
design_system's showAppConfirmDialog. On the device, registration, sign-in,
and sign-out go through the host's integration tests.

## Driven adapters (chapter 21)
- RestAuthService implements AuthRepository over the ApiClient.
- AuthTokenProvider implements TokenProvider (core) and AuthSessionStore
  (internal): session read once, shared refresh, a rejection (ApiError
  rejected) ends the session, a missing network preserves it.
- The session (user and two tokens) lives in the session table of the
  auth.db database, opened through LocalDatabaseFactory (SQLCipher, key in
  the Keychain, out of backups).
- Since chapter 32, auth.db is at version 2 (auth_database_schema.dart,
  with a schema test): the data_owner table, one row with the id of the
  owner of the data stored on the device, read and written by
  SqliteDataOwnerService (DataOwnerRepository port).

## Error contracts with the backend
| Status | Code | Failure |
| --- | --- | --- |
| 401 | invalid_credentials | InvalidCredentialsFailure |
| 422 | email_already_registered | EmailAlreadyRegisteredFailure |
| 422 | weak_password | WeakPasswordFailure |
Any other error remains an ApiError.

## Driving adapters (chapter 22)
- LoginPage/LoginView/LoginBloc and RegisterPage/RegisterView/RegisterBloc.
  The Blocs depend only on the AuthUseCase, use droppable() on submit, and
  handle AuthFailure (a message per failure, chosen by the View) and
  ApiError or LocalDatabaseError (a generic message; trying again means
  tapping the button again).
- After success the screen does not navigate: the host's redirect, which
  observes the session state, takes the user onward.
- Visual components only from design_system (AppForm, AppTextField,
  AppPrimaryButton, AppTextButton, AppInlineError). Strings in the module's
  ARBs (chapter 37): lib/adapters/driving/l10n/auth_module_en.arb
  (template) and auth_module_pt.arb, generating AuthModuleLocalizations,
  exported by the entry file. Plurals in the ARB (expired session with
  changes, sign-out with changes).

## Navigation (public contract)
| Name | Path | Screen |
| --- | --- | --- |
| auth.login | /auth/login | LoginPage |
| auth.register | /auth/register | RegisterPage |
The host uses AuthRoutes.prefix and AuthRoutes.loginPath in the redirect.
Renaming a route breaks the host: names and paths only change together with
it.

## Session state (public contract, chapter 28)
The SessionBloc, exported with the SessionUnknown, SessionAuthenticated, and
SessionUnauthenticated states and the SessionRestoreRequested event, is what
the host observes in place of the token. A single one, registered in the
base scope. It listens to AuthUseCase.watchSignedIn(), which publishes true
on sign-in, registration, and a restored session, and false when the session
ends, always after clearAll(). An expiration (refresh rejected) with no
pending changes is ended by the Bloc itself with endExpiredSession(); with
some (or when they cannot be counted), the Bloc emits
SessionExpiredWithPendingChanges(pendingChanges) and waits: the sign-in
screen gives notice and offers to sign in again or discard
(SessionDiscardRequested, with confirmation). An unreadable session
database on restore becomes SessionUnauthenticated.

## Sign-out (chapter 29)
The exported LogoutButton is the sign-out entry point: the host puts it in
the screens' frame. LogoutBloc (factory): LogoutRequested →
LogoutCheckInProgress → LogoutCheckSuccess(pendingChanges) or
LogoutCheckFailure; the View asks for confirmation when there are pending
changes (or when they could not be counted) and only then sends
LogoutConfirmed → LogoutSubmitInProgress → LogoutSubmitSuccess (also with no
network: the local data has already been erased) or LogoutSubmitFailure
(cleanup failed). The confirmation uses design_system's
showAppConfirmDialog.

## Someone else after an expired session
The data owner is recorded in auth.db (chapter 32): only the opaque id,
never a name or email. Sign-in and registration read the owner before going
to the backend (an unreadable owner rejects the sign-in before any token is
stored); if the person who signed in is someone else, the previous person's
data is erased (clearAll) and only then does the owner change, before the new
session is published. The same person finds everything as they left it.
Sign-out and discard erase the owner after the data; a cleanup that fails
leaves the owner recorded, and the next sign-in by someone else erases again.
A session restored at boot makes the same comparison. With no stored
session but with an owner, the session expired before the app closed:
restoreSession() publishes nothing and reports the expiration through
watchSessionExpired(), and the SessionBloc follows the usual path (counts the
pending changes; with some, SessionExpiredWithPendingChanges; with none, it
ends the session). The host opens the session scope before that read, so
that the modules' queues and cleaners are registered. A cleanup failure goes
to the AppLogger and is rethrown.

## Wiring to the host (chapter 28)
The host depends on the package, calls registerAuthModuleDependencies(getIt)
in the base scope, spreads authModuleRoutes into the GoRouter, uses
AuthRoutes in the redirect, observes the SessionBloc, and puts the
LogoutButton in the screens' frame (chapter 29). Step 6 (chapter 37):
AuthModuleLocalizations.delegate in app.dart's moduleLocalizationsDelegates
list. No send queue. Since chapter 32, the host opens the session scope
before asking for the stored session and renews it at each end of session.
