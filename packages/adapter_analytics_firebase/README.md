# adapter_analytics_firebase

The project's product events, with Google Analytics for Firebase.

- **Contains:** `FirebaseAppAnalytics` (`AppAnalytics` port), which never
  throws: a plugin failure goes to the `AppLogger`.
- **Never contains:** crash reporting (that is the `AppLogger`), personal
  data in names or parameters, or the consent decision (it stays in the host).
