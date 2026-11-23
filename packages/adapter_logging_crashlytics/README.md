# adapter_logging_crashlytics

The project's crash reporting, with Firebase Crashlytics.

- **Contains:** `CrashlyticsAppLogger` (`AppLogger` port). While Firebase is
  not initialized, it writes to the console; there is no separate console
  adapter.
- **Never contains:** product events (those go to `AppAnalytics`), Firebase
  initialization, or the global error handlers (they stay in the host).
