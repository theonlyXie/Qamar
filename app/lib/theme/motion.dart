import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// Animation timings ported from the prototype's @keyframes (qbreath, qhalo,
/// qfloat, qorbit…). Kept centralized so the orb's "alive" feel stays
/// consistent everywhere it appears (welcome hero, nav orb, chat, tree).
class QMotion {
  QMotion._();

  static const breath = Duration(milliseconds: 4600);
  static const breathChat = Duration(milliseconds: 5500);
  static const breathTree = Duration(milliseconds: 4600);
  static const halo = Duration(milliseconds: 5200);
  static const haloWelcome = Duration(milliseconds: 7000);
  static const float = Duration(milliseconds: 11000);
  static const floatWelcomeOrb = Duration(milliseconds: 9000);
  static const floatChatPill = Duration(milliseconds: 11000);
  static const floatScanPill = Duration(milliseconds: 13000);
  static const orbit = Duration(milliseconds: 7000);
  static const orbit2 = Duration(milliseconds: 5400);
  static const orbit3 = Duration(milliseconds: 9500);
  static const ring = Duration(milliseconds: 2400);
  static const trail = Duration(milliseconds: 3600);
  static const branch = Duration(milliseconds: 3400);
  static const sway = Duration(milliseconds: 3600);
  static const nodeBob = Duration(milliseconds: 5400);
  static const pulse = Duration(milliseconds: 1000);
  static const twinkle = Duration(milliseconds: 2400);

  static const fadeIn = Duration(milliseconds: 240);
  static const riseIn = Duration(milliseconds: 340);
  static const growIn = Duration(milliseconds: 280);

  static const typingDelay = Duration(milliseconds: 600);
  static const qamarSayDelay = Duration(milliseconds: 550);
  static const answerDelay = Duration(milliseconds: 260);
  static const targetDelay = Duration(milliseconds: 900);
  static const chatThinkDelay = Duration(milliseconds: 1100);
  static const listenDelay = Duration(milliseconds: 1500);
  static const scanReadDelay = Duration(milliseconds: 1700);
  static const analyzeDelay = Duration(milliseconds: 1900);
}

/// Springs for anything a finger moves (the orb, first): they start from
/// where the thing is on screen, carry the finger's speed, and can be
/// grabbed again mid-flight, which a fixed-length curve cannot.
///
/// Described the way Apple's fluid interfaces are, by two numbers: the
/// damping ratio (1 settles with no overshoot; under 1 overshoots) and the
/// response, roughly how long it takes to get there. Critically damped by
/// default; a little bounce only when the finger threw it ([flick]).
abstract final class QSpring {
  /// Most motion: no overshoot.
  static final settle = of(damping: 1.0, response: 0.35);

  /// After a flick: the throw carries a small overshoot, as a thrown thing
  /// would.
  static final flick = of(damping: 0.8, response: 0.35);

  /// How fast a release has to be (points a second) to count as a flick.
  static const flickSpeed = 700.0;

  /// A spring from a damping ratio and a response in seconds (mass 1).
  static SpringDescription of({required double damping, required double response}) {
    final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
    final c = 4 * math.pi * damping / response;
    return SpringDescription(mass: 1, stiffness: stiffness, damping: c);
  }

  /// Drives [c] (an unbounded controller) to [to] on [settle] from where it
  /// is, carrying [velocity] (units a second) — or, with reduce-motion on,
  /// over a plain 150ms, which the caller draws as a fade.
  static TickerFuture drive(AnimationController c, double to, {required bool still, double velocity = 0}) =>
      still ? c.animateTo(to, duration: const Duration(milliseconds: 150)) : c.animateWith(SpringSimulation(settle, c.value, to, velocity));

  /// Where a release at [velocity] (points a second) would come to rest if
  /// it simply slowed down, as a scrolled list does: Apple's projection, with
  /// the deceleration of a normal scroll. Snapping to the target nearest this
  /// point, rather than nearest the release, is what makes a flick throw.
  static double project(double velocity, {double decelerationRate = 0.998}) =>
      (velocity / 1000) * decelerationRate / (1 - decelerationRate);
}

