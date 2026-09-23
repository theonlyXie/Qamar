import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/streak.dart';
import '../theme/colors.dart';
import 'moon.dart';

/// The Qamar moon — a drawn sphere (see [QamarMoon]) that breathes, glows and
/// (optionally) wanders and throws off orbiting sparks, matching the
/// prototype's qbreath/qhalo/qfloat/qorbit keyframes. One widget covers every
/// place the orb appears: welcome hero, nav orb, chat companion, tree center.
class LivingOrb extends StatefulWidget {
  final double size;
  final bool wander;
  final bool sparks;
  final bool activeRings; // extra pulsing rings, used while "listening"
  final Duration breathDuration;
  final Duration haloDuration;
  final Duration wanderDuration;
  final VoidCallback? onTap;

  /// The day, on the orb. Null is the decorative orb (welcome, subscription):
  /// waxing crescent, steady halo, no ring. With a state the moon brightens
  /// from that resting crescent toward today's target, the halo brightens
  /// with the day's meals and warms only when the day is past the target by
  /// more than an estimate can tell apart ([OrbDay.over]), and the streak
  /// ring closes one day at a time. An [OrbDay.unknown] day (nothing logged,
  /// or no target) is the moon at rest, never a dark one.
  final OrbState? state;

  /// Qamar has something to say (a meal's question is waiting and the hold
  /// would ask it, AppState.orbSpeaking): the halo
  /// breathes wider and brighter on its own slow cycle. A pulse, never a
  /// bounce, and never a sound.
  final bool speaking;

  /// How far the moon drifts and how tall the sparks' orbit is, against the
  /// moon's size: 1 is the full height; the nav orb, resting in its band,
  /// keeps both inside it. The orbit's width is not scaled: the band is as
  /// wide as the screen, and it is the width that carries the sparks clear
  /// of the moon.
  final double reach;

  /// Each orbiting spark, for tests.
  static ValueKey<String> sparkKey(int i) => ValueKey('orb-spark-$i');

  /// The sparks' orbits: across, against the moon's size; turns per drift
  /// cycle, whole numbers so the loop has no seam (1.55 of a turn jumped
  /// back every eleven seconds), the third turning the other way; where on
  /// the ring each starts, so the three are spread round it rather than
  /// bunched at one side; and the spark's size. A ring seen at a tilt:
  /// [sparkAt] flattens it.
  static const sparkOrbits = <({double across, double speed, double phase, double size})>[
    (across: 0.68, speed: 1, phase: 0.0, size: 6),
    (across: 0.7, speed: 2, phase: 0.37, size: 4),
    (across: 0.75, speed: -1, phase: 0.71, size: 3),
  ];

  /// How much the ring is flattened at [reach] 1.
  static const sparkTilt = 0.7;

  /// Where spark [i] is at [t] (the drift's cycle, 0 → 1) around a moon of
  /// [size], and whether it is on the near side of the ring. The near half
  /// (the lower one) passes in front of the moon; the far half goes behind
  /// it, hidden where the moon's disc is. So the sparks are always drawn
  /// over the moon, never simply under it: under it, at the band's reach,
  /// every one of them was inside the disc and none was ever seen.
  static ({Offset at, bool near}) sparkAt(int i, double t, {required double size, required double reach}) {
    final o = sparkOrbits[i];
    final angle = (t * o.speed + o.phase) * 2 * math.pi;
    final rx = size * o.across;
    final ry = rx * sparkTilt * reach;
    final dy = math.sin(angle) * ry;
    return (at: Offset(math.cos(angle) * rx, dy), near: dy >= 0);
  }

  /// The halo, for tests.
  static const haloKey = ValueKey('orb-halo');

  /// The halo's glow at rest: the decorative orb's (welcome, subscription),
  /// and the orb on any day it does not read.
  static const restGlow = 0.32;

  /// The halo's base glow for [day]. Only a day the moon reads (under, at,
  /// over) glows with its meals, from faint to full. An [OrbDay.unknown] day —
  /// nothing logged, or no target on the general-guidance route — is no
  /// reading at all, so it glows exactly as the moon at rest does, never
  /// dimmer: a dimmer orb on an empty morning would say "dark means a bad
  /// day", and on the general-guidance route meals are not counted against
  /// three.
  static double glowBaseFor(OrbState? day) =>
      day == null || day.day == OrbDay.unknown ? restGlow : 0.16 + 0.24 * day.glow;

  const LivingOrb({
    super.key,
    required this.size,
    this.wander = false,
    this.sparks = false,
    this.activeRings = false,
    this.breathDuration = const Duration(milliseconds: 4600),
    this.haloDuration = const Duration(milliseconds: 5200),
    this.wanderDuration = const Duration(milliseconds: 11000),
    this.onTap,
    this.state,
    this.speaking = false,
    this.reach = 1,
  });

  @override
  State<LivingOrb> createState() => _LivingOrbState();
}

class _LivingOrbState extends State<LivingOrb> with TickerProviderStateMixin {
  /// The halo: cool on an ordinary day, warm (never red) on one that ran over.
  static final _coolHalo = [QColors.violet.withValues(alpha: 0.55), QColors.blue.withValues(alpha: 0.12), Colors.transparent];
  static final _warmHalo = [QColors.ember.withValues(alpha: 0.55), QColors.emberDeep.withValues(alpha: 0.12), Colors.transparent];

  late final AnimationController _breath =
      AnimationController(vsync: this, duration: widget.breathDuration)..repeat(reverse: true);
  late final AnimationController _halo =
      AnimationController(vsync: this, duration: widget.haloDuration)..repeat(reverse: true);
  late final AnimationController _wander =
      AnimationController(vsync: this, duration: widget.wanderDuration)..repeat();
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();

  static const _wanderStops = [
    Offset(0, 0),
    Offset(-0.07, -0.11),
    Offset(0.05, -0.18),
    Offset(0.09, -0.07),
    Offset(-0.03, 0.03),
    Offset(-0.08, -0.04),
    Offset(0, 0),
  ];
  static const _wanderWeights = [18.0, 18.0, 18.0, 18.0, 14.0, 14.0];

  late final Animation<Offset> _wanderOffset = TweenSequence<Offset>([
    for (var i = 0; i < _wanderWeights.length; i++)
      TweenSequenceItem(
        weight: _wanderWeights[i],
        tween: Tween(begin: _wanderStops[i], end: _wanderStops[i + 1]).chain(CurveTween(curve: Curves.easeInOut)),
      ),
  ]).animate(_wander);

  @override
  void dispose() {
    _breath.dispose();
    _halo.dispose();
    _wander.dispose();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    Widget core = AnimatedBuilder(
      animation: Listenable.merge([_breath, _halo, _wander]),
      builder: (context, child) {
        final breathT = _breath.value; // 0..1..0
        final scale = 1.0 + 0.045 * breathT;
        final haloT = _halo.value;
        final haloScale = 1.0 + (widget.speaking ? 0.38 : 0.22) * haloT;
        final day = widget.state;
        final glowBase = LivingOrb.glowBaseFor(day);
        final haloOpacity = (glowBase + 0.40 * haloT + (widget.speaking ? 0.2 : 0.0)).clamp(0.0, 1.0);
        final haloColors = day?.over == true ? _warmHalo : _coolHalo;
        final offset = widget.wander ? Offset(_wanderOffset.value.dx * s * widget.reach, _wanderOffset.value.dy * s * widget.reach) : Offset.zero;

        return Transform.translate(
          offset: offset,
          child: SizedBox(
            width: s * 1.7,
            height: s * 1.7,
            // The footprint may be squeezed by a tight parent (the nav gives
            // the orb a box the size of the moon); the painting must not be,
            // or the halo and the streak ring end up hidden under the moon.
            // The geometry keeps its own size and overflows, as the halo
            // always visually did.
            child: OverflowBox(
              minWidth: s * 1.7,
              maxWidth: s * 1.7,
              minHeight: s * 1.7,
              maxHeight: s * 1.7,
              child: Stack(
                alignment: Alignment.center,
                children: [
                Transform.scale(
                  scale: haloScale,
                  child: Opacity(
                    key: LivingOrb.haloKey,
                    opacity: haloOpacity,
                    child: Container(
                      width: s * 1.55,
                      height: s * 1.55,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: haloColors,
                          stops: const [0.0, 0.45, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.activeRings) ..._buildActiveRings(s),
                if (day != null && day.streak.current > 0)
                  CustomPaint(
                    size: Size.square(s * 1.3),
                    painter: StreakRingPainter(streak: day.streak),
                  ),
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: QColors.violet.withOpacity(0.55), blurRadius: s * 0.5),
                      ],
                    ),
                    child: QamarMoon(size: s, phase: day?.moonPhase),
                  ),
                ),
                // Over the moon: the near half of each orbit in front of it,
                // the far half clipped where the disc is, as if behind.
                if (widget.sparks) ..._buildSparks(s, moonRadius: s / 2 * scale),
              ],
              ),
            ),
          ),
        );
      },
    );

    if (widget.onTap != null) {
      core = GestureDetector(onTap: widget.onTap, child: core);
    }
    return core;
  }

  static const _sparkColors = [QColors.cyan, QColors.violetSoft, QColors.textPrimary];

  List<Widget> _buildSparks(double s, {required double moonRadius}) {
    return [
      for (var i = 0; i < LivingOrb.sparkOrbits.length; i++)
        _OrbitingSpark(
          key: LivingOrb.sparkKey(i),
          index: i,
          controller: _wander,
          moonSize: s,
          moonRadius: moonRadius,
          reach: widget.reach,
          color: _sparkColors[i],
        ),
    ];
  }

  List<Widget> _buildActiveRings(double s) {
    return [
      AnimatedBuilder(
        animation: _ring,
        builder: (context, _) {
          final t = _ring.value;
          return Opacity(
            opacity: (1 - t) * 0.7,
            child: Transform.scale(
              scale: 0.86 + 0.64 * t,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.violet, width: 1)),
              ),
            ),
          );
        },
      ),
      AnimatedBuilder(
        animation: _ring,
        builder: (context, _) {
          final t = (_ring.value + 0.5) % 1.0;
          return Opacity(
            opacity: (1 - t) * 0.55,
            child: Transform.scale(
              scale: 0.86 + 0.64 * t,
              child: Container(
                width: s,
                height: s,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.cyan, width: 1)),
              ),
            ),
          );
        },
      ),
    ];
  }
}

class _OrbitingSpark extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final double moonSize;
  final double moonRadius;
  final double reach;
  final Color color;

  const _OrbitingSpark({
    super.key,
    required this.index,
    required this.controller,
    required this.moonSize,
    required this.moonRadius,
    required this.reach,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final size = LivingOrb.sparkOrbits[index].size;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final p = LivingOrb.sparkAt(index, controller.value, size: moonSize, reach: reach);
        final o = LivingOrb.sparkOrbits[index];
        final angle = (controller.value * o.speed + o.phase) * 2 * math.pi;
        final twinkle = 0.4 + 0.6 * ((math.sin(angle * 2) + 1) / 2);
        Widget spark = Transform.translate(
          offset: p.at,
          child: Opacity(
            opacity: twinkle,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: size * 1.6)],
              ),
            ),
          ),
        );
        // On the far side the moon is in front of it.
        if (!p.near) spark = ClipPath(clipper: BehindMoonClipper(moonRadius), child: spark);
        return spark;
      },
    );
  }
}

/// Everything but the moon's disc, around the box's centre (the moon's):
/// what is visible of a spark behind the moon.
///
/// The outer square is the moon's, three radii out, well past the widest
/// orbit (0.75 of the moon's size across, 1.5 radii). It used to be built
/// from the spark's own 3 to 6 point box, ±13 to ±27 points, inside which
/// the even-odd rule was right and outside which it flipped: beside the
/// moon on the far side a spark was cut away, and the smallest one was
/// inverted, drawn over the disc and hidden beside it.
class BehindMoonClipper extends CustomClipper<Path> {
  final double radius;
  const BehindMoonClipper(this.radius);

  @override
  Path getClip(Size size) {
    final c = size.center(Offset.zero);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromCircle(center: c, radius: radius * 3))
      ..addOval(Rect.fromCircle(center: c, radius: radius));
  }

  @override
  bool shouldReclip(BehindMoonClipper old) => old.radius != radius;
}

/// The streak as a ring: one arc segment per day of the current week of the
/// run, closing at seven and starting over. Violet while young, cyan from
/// three, gold from a full week. A gap in the arc at the top is today, still
/// open, when today has not been counted yet.
class StreakRingPainter extends CustomPainter {
  final Streak streak;
  const StreakRingPainter({required this.streak});

  static const daysPerTurn = 7;

  /// Filled fraction of the ring for [count] days.
  static double fraction(int count) {
    if (count <= 0) return 0;
    final inTurn = count % daysPerTurn;
    return inTurn == 0 ? 1 : inTurn / daysPerTurn;
  }

  static Color colorFor(int count) {
    if (count >= daysPerTurn) return QColors.gold;
    if (count >= 3) return QColors.cyan;
    return QColors.violet;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = math.max(1.5, size.width * 0.035);
    final rect = Rect.fromCircle(center: c, radius: r - stroke);
    final color = colorFor(streak.current);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.14);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    const gap = 0.12; // radians left open between segments
    const segment = math.pi * 2 / daysPerTurn;
    final lit = (fraction(streak.current) * daysPerTurn).round();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (var i = 0; i < lit; i++) {
      final start = -math.pi / 2 + i * segment + gap / 2;
      canvas.drawArc(rect, start, segment - gap, false, paint);
    }
    if (streak.atRisk) {
      // Today's segment, waiting for its meal.
      final start = -math.pi / 2 + lit * segment + gap / 2;
      canvas.drawArc(rect, start, segment - gap, false, paint..color = color.withValues(alpha: 0.35));
    }
  }

  @override
  bool shouldRepaint(covariant StreakRingPainter old) =>
      old.streak.current != streak.current || old.streak.todayCounted != streak.todayCounted;
}
