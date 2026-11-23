import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_device/safe_device.dart';

import '../l10n/mobile_tasks_localizations.dart';

/// The root and jailbreak check (chapters 14 and 38): warn, don't expel.
/// Detection can be bypassed by whoever wants to, and blocking the app
/// mostly punishes those who modified the device for other reasons.
/// mobile_tasks has no sensitive feature to turn off, so only the
/// notice remains.
///
/// Emulators and simulators are left out: they are the development
/// environment, and tend to look like rooted devices.
Future<bool> deviceCompromised({
  required AppLogger logger,
  Future<bool> Function() isRealDevice = _isRealDevice,
  Future<bool> Function() isJailBroken = _isJailBroken,
}) async {
  try {
    if (!await isRealDevice()) return false;
    final compromised = await isJailBroken();
    if (compromised) logger.log('device integrity: root or jailbreak');
    return compromised;
  } on PlatformException catch (error, stackTrace) {
    // When in doubt, no notice: a false positive scares for no reason.
    logger.error('device integrity', error, stackTrace);
    return false;
  }
}

/// The notice, at the top of the screen, until the user dismisses it. It
/// blocks nothing: the screen stays whole and tappable below it.
void showDeviceIntegrityNotice(ScaffoldMessengerState messenger) {
  final l10n = MobileTasksLocalizations.of(messenger.context);
  messenger.showMaterialBanner(
    MaterialBanner(
      leading: const Icon(Icons.gpp_maybe_outlined),
      content: Text(l10n.deviceIntegrityWarning),
      actions: [
        TextButton(
          onPressed: messenger.hideCurrentMaterialBanner,
          child: Text(l10n.deviceIntegrityDismiss),
        ),
      ],
    ),
  );
}

Future<bool> _isRealDevice() => SafeDevice.isRealDevice;

Future<bool> _isJailBroken() => SafeDevice.isJailBroken;
