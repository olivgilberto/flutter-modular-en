import 'dart:math';

import 'package:flutter/painting.dart';

/// The WCAG 2.2 contrast ratio between two colors, from 1 to 21.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// The AA minimum for regular text.
const aaNormalText = 4.5;
