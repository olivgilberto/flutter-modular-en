import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The system font scales at which every View is checked (chapter 39):
/// the default, Android's maximum (200%), and close to iOS's largest
/// accessibility size.
const systemTextScales = [1.0, 2.0, 3.0];

/// Puts the test on a small phone, 375 × 667 points (the iPhone SE), with
/// the system font at [scale]. The MaterialApp reads the scale from the
/// platform, as on the device; no View receives the scale from outside.
void useSmallPhone(WidgetTester tester, {required double textScale}) {
  tester.view
    ..physicalSize = const Size(750, 1334)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Scrolls to [finder] and checks that it fits entirely on screen: an
/// action that exists but sits out of reach is the defect a large font
/// causes.
Future<void> expectReachable(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  final screen =
      Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
  final rect = tester.getRect(finder);
  expect(
    screen.contains(rect.topLeft) &&
        screen.contains(rect.bottomRight - const Offset(0.01, 0.01)),
    isTrue,
    reason: '$finder at $rect, outside $screen',
  );
}
