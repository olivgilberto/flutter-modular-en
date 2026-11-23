# auth_module

Authentication for mobile_tasks: sign-in with email and password,
registration, session restored at boot, sign-out that clears every module's
data, and expired sessions.

- **Contains:** the domain (`User`, `EmailAddress`, `Password`, the
  `AuthFailure` family), the application (the `AuthRepository` port and the
  `AuthUseCase`), the driven adapters (chapter 21) and the driving ones
  (chapter 22): the sign-in and registration screens and the
  `authModuleRoutes` list, which the host spreads into its `GoRouter`, and the
  `SessionBloc` (chapter 28), the session state the host observes. Since
  chapter 32, the owner of the data stored on the device, recorded in
  `auth.db`.
- **Never contains:** a dependency on another module or on an `adapter_*`
  package, or technology that `core` abstracts. The token reaches the other
  modules through `core`'s `TokenProvider` port.

Documentation: `docs/modules/auth_module.md`.
