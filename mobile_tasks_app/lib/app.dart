import 'package:auth_module/auth_module.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:notes_module/notes_module.dart';
import 'package:tasks_module/tasks_module.dart';

import 'connectivity/connectivity_banner_host.dart';
import 'l10n/mobile_tasks_localizations.dart';
import 'settings/app_languages.dart';
import 'settings/app_settings.dart';

/// The app: the design_system's theme, the language and theme the user
/// chose, the host's router and, below every screen, the connection
/// notice (chapter 33). The translations (chapter 37): the host joins each
/// module's delegate to its own and to Flutter's; each module translates
/// its own screens, and the host only decides the languages and which one is in effect.
final class MobileTasksApp extends StatelessWidget {
  const MobileTasksApp({
    super.key,
    required this.settings,
    required this.router,
    required this.connectivity,
    this.messengerKey,
  });

  final AppSettings settings;
  final GoRouter router;
  final ConnectivityService connectivity;

  /// Where the host shows notices outside any screen, such as the one for a
  /// rooted or jailbroken device (chapter 38).
  final GlobalKey<ScaffoldMessengerState>? messengerKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp.router(
        scaffoldMessengerKey: messengerKey,
        onGenerateTitle: (context) =>
            MobileTasksLocalizations.of(context).appTitle,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: settings.themeMode,
        // Never null: null would make Flutter use the system language.
        locale: settings.locale ?? AppLanguages.template,
        supportedLocales: AppLanguages.supported,
        localizationsDelegates: appLocalizationsDelegates,
        routerConfig: router,
        builder: (context, child) => ConnectivityBannerHost(
          connectivity: connectivity,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// The app's delegates: the host's, one per module with strings, and
/// Flutter's, which translate the Material and Cupertino widgets. A new
/// module with screens adds one line to the list below, and nothing else in
/// the host changes because of the strings (chapter 28, step 6).
const appLocalizationsDelegates = <LocalizationsDelegate<Object?>>[
  MobileTasksLocalizations.delegate,
  ...moduleLocalizationsDelegates,
  ...GlobalMaterialLocalizations.delegates,
];

/// The modules' delegates. The language test checks that each one
/// translates every language in [AppLanguages].
const moduleLocalizationsDelegates = <LocalizationsDelegate<Object?>>[
  AuthModuleLocalizations.delegate,
  TasksModuleLocalizations.delegate,
  NotesModuleLocalizations.delegate,
];
