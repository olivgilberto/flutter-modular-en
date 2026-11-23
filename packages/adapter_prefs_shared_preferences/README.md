# adapter_prefs_shared_preferences

The user's non-sensitive preferences (theme and language), with
shared_preferences.

- **Contains:** `SharedPreferencesAppPreferences` (`AppPreferences` port).
- **Never contains:** tokens, personal data, or business data (they go to
  secure storage or to a module's encrypted database).
