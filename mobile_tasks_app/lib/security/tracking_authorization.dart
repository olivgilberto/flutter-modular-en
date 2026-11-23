import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App Tracking Transparency (chapters 14 and 38). The project's Firebase
/// Analytics can read iOS's advertising identifier, so the host asks for
/// permission, once, before any tracking. Without permission, the
/// identifier comes zeroed and nothing else changes: no feature depends on
/// the answer.
///
/// The request only appears with the app active: Apple ignores a call made
/// before that, with no error. That is why it is not boot step 2, which
/// runs before `runApp`, but the first thing after the first screen
/// appears and the app becomes active.
Future<void> requestTrackingAuthorization({
  required AppLogger logger,
  bool Function() isIOS = _isIOS,
  Future<TrackingStatus> Function() status = _status,
  Future<TrackingStatus> Function() request = _request,
}) async {
  if (!isIOS()) return;
  try {
    if (await status() != TrackingStatus.notDetermined) return;
    final answer = await request();
    logger.log('tracking authorization: ${answer.name}');
  } on PlatformException catch (error, stackTrace) {
    logger.error('tracking authorization', error, stackTrace);
  }
}

/// Completes when the app is active (`resumed`): right away, if it already
/// is; otherwise, the first time it becomes so.
Future<void> appActive(WidgetsBinding binding) {
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    return Future.value();
  }
  final active = Completer<void>();
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    binding: binding,
    onStateChange: (state) {
      if (state == AppLifecycleState.resumed && !active.isCompleted) {
        listener.dispose();
        active.complete();
      }
    },
  );
  return active.future;
}

bool _isIOS() => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

Future<TrackingStatus> _status() =>
    AppTrackingTransparency.trackingAuthorizationStatus;

Future<TrackingStatus> _request() =>
    AppTrackingTransparency.requestTrackingAuthorization();
