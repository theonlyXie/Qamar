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
  /// waxing crescent, steady halo, no ring. With a state the moon fills
  /// toward today's target, the halo brightens with the day's meals and warms
  /// when intake runs over, and the streak ring closes one day at a time.
  final OrbState? state;

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
  });

  @override
  State<LivingOrb> createState() => _LivingOrbState();
}

class _LivingOrbState extends State<LivingOrb> with TickerProviderStateMixin {
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
        final haloScale = 1.0 + 0.22 * haloT;
        final day = widget.state;
        // A day with nothing in it glows faintly; a full one, fully.
        final glowBase = day == null ? 0.32 : 0.16 + 0.24 * day.glow;
        final haloOpacity = glowBase + 0.40 * haloT;
        final haloColors = day?.over == true
            ? const [Color(0x8CFFB36C), Color(0x1FFF7C4F), Colors.transparent]
            : const [Color(0x8C7B6CFF), Color(0x1F4F7CFF), Colors.transparent];
        final offset = widget.wander ? Offset(_wanderOffset.value.dx * s, _wanderOffset.value.dy * s) : Offset.zero;

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
                if (widget.sparks) ..._buildSparks(s),
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

  List<Widget> _buildSparks(double s) {
    return [
      _OrbitingSpark(controller: _wander, radius: s * 0.62, period: 1.0, size: 6, color: QColors.cyan),
      _OrbitingSpark(controller: _wander, radius: s * 0.48, period: 1.55, size: 4, color: QColors.violetSoft),
      _OrbitingSpark(controller: _wander, radius: s * 0.75, period: 0.7, size: 3, color: QColors.textBrand),
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
  final AnimationController controller;
  final double radius;
  final double period; // relative speed multiplier
  final double size;
  final Color color;

  const _OrbitingSpark({
    required this.controller,
    required this.radius,
    required this.period,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final angle = controller.value * 2 * math.pi * period;
        final dx = math.cos(angle) * radius;
        final dy = math.sin(angle) * radius;
        final twinkle = 0.4 + 0.6 * ((math.sin(angle * 2) + 1) / 2);
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: twinkle,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withOpacity(0.9), blurRadius: size * 1.6)],
              ),
            ),
          ),
        );
      },
    );
  }
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
    if (count >= daysPerTurn) return const Color(0xFFF2C56B);
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
