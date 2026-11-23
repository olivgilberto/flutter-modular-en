# adapter_sync_workmanager

Syncing the queues with the app closed, with workmanager.

- **Contains:** `WorkmanagerSyncScheduler` (`SyncScheduler` port) and
  `runWorkmanagerSyncTask`, which the host's background entry point calls so
  it does not import workmanager.
- **Never contains:** what to sync (that is the core's `OutboxSyncWorker`) or
  the platform configuration (Info.plist and AppDelegate stay in the host).
