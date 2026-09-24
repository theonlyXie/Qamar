// WCAG 2.x contrast between two colours, for tests that hold text to AA:
// 4.5:1 for body text, 3:1 for large text. Opaque colours; a translucent
// foreground should be composited over its ground first ([over]).

import 'dart:math' as math;

import 'package:flutter/painting.dart';

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrastRatio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] composited over the opaque [bg].
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);
