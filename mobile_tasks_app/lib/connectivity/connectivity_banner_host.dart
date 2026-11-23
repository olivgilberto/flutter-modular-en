import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../l10n/mobile_tasks_localizations.dart';

/// The connection notice below every screen (chapters 12 and 33). The host
/// reads the state from the core's `ConnectivityService` and translates it
/// into the two parameters of `AppConnectivityBanner`; the banner does not
/// know what connectivity is. It is only a notice: the screen stays whole
/// and tappable, and no action depends on it.
///
/// The strings are the host's, in its ARBs (chapter 37). The host places it
/// through the `MaterialApp.router` `builder`, which is already below the translations.
final class ConnectivityBannerHost extends StatelessWidget {
  const ConnectivityBannerHost({
    super.key,
    required this.connectivity,
    required this.child,
  });

  final ConnectivityService connectivity;
  final Widget child;

  @override
  Widget build(BuildContext context) => StreamBuilder<ConnectivityStatus>(
    stream: connectivity.statusChanges,
    initialData: connectivity.status,
    builder: (context, snapshot) {
      final status = snapshot.data ?? ConnectivityStatus.unknown;
      final message = messageFor(MobileTasksLocalizations.of(context), status);
      return Column(
        children: [
          Expanded(
            // When visible, the banner takes the bottom margin of the screen.
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: message != null,
              child: child,
            ),
          ),
          AppConnectivityBanner(
            visible: message != null,
            message: message ?? '',
          ),
        ],
      );
    },
  );

  /// `null` when there is no notice: at the start, before the first check,
  /// and with the backend answering.
  @visibleForTesting
  static String? messageFor(
    MobileTasksLocalizations l10n,
    ConnectivityStatus status,
  ) => switch (status) {
    ConnectivityStatus.unknown || ConnectivityStatus.online => null,
    ConnectivityStatus.offline => l10n.connectivityOffline,
    ConnectivityStatus.noInternet => l10n.connectivityNoInternet,
  };
}
