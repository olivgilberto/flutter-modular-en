# core

The project's ports and the code that depends on no technology.

- **Contains:** interfaces (`abstract interface class`) that more than one
  package uses, the shared error types (`Failure`, `ApiError`,
  `LocalDatabaseError`), and implementations that work only with ports
  (registries, `OutboxSyncWorker`, `DefaultConnectivityService`,
  `SyncOrchestrator`).
- **Never contains:** dependencies (not even Flutter), a module's business
  rules, or technology implementations (those live in the `adapter_*`
  packages).

The `pubspec.yaml` has no `dependencies` section, and the workspace's
`check-deps` fails if one appears.
