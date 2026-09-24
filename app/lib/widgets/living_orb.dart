import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/streak.dart';
import '../theme/colors.dart';
import 'moon.dart';

/// The Qamar moon — a drawn sphere (see [QamarMoon]) that breathes and
/// glows, as the orb in the middle of the tab bar. It holds still in its
/// circle: no drift and no sparks, so the one thing that moves on the page
/// is the moon's breath (the owner's "less noise").
class LivingOrb extends StatefulWidget {
  final double size;
  final Duration breathDuration;
  final Duration haloDuration;

  /// The day, on the orb. Null is the decorative orb: waxing crescent,
  /// steady halo, no ring. With a state the moon brightens from that resting
  /// crescent toward today's target, the halo brightens with the day's
  /// meals, and the streak's seven arcs light one day at a time. A day past
  /// the target by more than an estimate can tell apart ([OrbDay.over]) is
  /// said by a shape, not a colour: the soft halo gives way to a thin closed
  /// ring drawn close round the moon ([overRingKey]). An [OrbDay.unknown]
  /// day (nothing logged, or no target) is the moon at rest, never a dark
  /// one.
  final OrbState? state;

  /// Qamar has something to say (a meal's question is waiting and the hold
  /// would ask it, AppState.orbSpeaking): the halo breathes wider and
  /// brighter on its own slow cycle. A pulse, never a bounce, and never a
  /// sound.
  final bool speaking;

  /// The halo, for tests.
  static const haloKey = ValueKey('orb-halo');

  /// The ring that circles the moon on a day that ran over, for tests.
  static const overRingKey = ValueKey('orb-over-ring');

  /// The halo's glow at rest: the decorative orb's, and the orb on any day
  /// it does not read.
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
    this.breathDuration = const Duration(milliseconds: 4600),
    this.haloDuration = const Duration(milliseconds: 5200),
    this.state,
    this.speaking = false,
  });

  @override
  State<LivingOrb> createState() => _LivingOrbState();
}

class _LivingOrbState extends State<LivingOrb> with TickerProviderStateMixin {
  /// The halo: moonlight, white fading to nothing.
  static final _haloColors = [QColors.ink.withValues(alpha: 0.30), QColors.ink.withValues(alpha: 0.06), Colors.transparent];

  late final AnimationController _breath = AnimationController(vsync: this, duration: widget.breathDuration);
  late final AnimationController _halo = AnimationController(vsync: this, duration: widget.haloDuration);

  /// Alive, or still: under reduce motion the orb rests in its quiet pose
  /// (no breath, no swelling halo); the state it shows stays, drawn still.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      for (final c in [_breath, _halo]) {
        c.stop();
        c.value = 0;
      }
      return;
    }
    if (!_breath.isAnimating) _breath.repeat(reverse: true);
    if (!_halo.isAnimating) _halo.repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _halo]),
      builder: (context, child) {
        final breathT = _breath.value; // 0..1..0
        final scale = 1.0 + 0.045 * breathT;
        final haloT = _halo.value;
        final haloScale = 1.0 + (widget.speaking ? 0.38 : 0.22) * haloT;
        final day = widget.state;
        final glowBase = LivingOrb.glowBaseFor(day);
        final over = day?.over == true;
        // Over: the glow gives way to a ring, so the halo is quiet.
        final haloOpacity = over ? 0.0 : (glowBase + 0.40 * haloT + (widget.speaking ? 0.2 : 0.0)).clamp(0.0, 1.0);

        return SizedBox(
          width: s * 1.7,
          height: s * 1.7,
          // The footprint may be squeezed by a tight parent (the bar gives
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
                          colors: _haloColors,
                          stops: const [0.0, 0.45, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
                if (over)
                  Container(
                    key: LivingOrb.overRingKey,
                    width: s * 1.18,
                    height: s * 1.18,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.ink.withValues(alpha: 0.8), width: 1.5)),
                  ),
                if (day != null && day.streak.current > 0)
                  CustomPaint(
                    size: Size.square(s * 1.3),
                    painter: StreakRingPainter(streak: day.streak),
                  ),
                Transform.scale(
                  scale: scale,
                  child: SizedBox(
                    width: s,
                    height: s,
                    child: QamarMoon(size: s, phase: day?.moonPhase),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The streak as seven short arcs round the moon, lit one day at a time in
/// burgundy: an arc per day of the current week of the run, from the top,
/// clockwise in both languages; at seven the ring is whole, and the week
/// starts over. Today's arc, while today is still waiting for its meal, is
/// at half strength. Young, three days, a full week: the ring thickens with
/// the run instead of changing colour.
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

  /// The colour of a lit day: burgundy, whatever the count. What the count
  /// says, [weightScale] draws.
  static Color colorFor(int count) => QColors.accentInk;

  /// How thick a lit day is drawn for a run of [count] days: a little
  /// thicker from three days, and again from a full week.
  static double weightScale(int count) => count >= daysPerTurn ? 1.25 : (count >= 3 ? 1.1 : 1.0);

  /// The gap between two days' arcs, in radians.
  static const _gap = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final stroke = math.max(1.6, size.width * 0.03);
    final ring = Rect.fromCircle(center: c, radius: r - stroke * 1.6);
    final lit = (fraction(streak.current) * daysPerTurn).round();
    final scale = weightScale(streak.current);
    const step = 2 * math.pi / daysPerTurn;
    for (var i = 0; i < daysPerTurn; i++) {
      final start = -math.pi / 2 + i * step + _gap / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      if (i < lit) {
        paint
          ..strokeWidth = stroke * scale
          ..color = colorFor(streak.current);
      } else if (i == lit && streak.atRisk) {
        // Today's arc, waiting for its meal.
        paint
          ..strokeWidth = stroke
          ..color = colorFor(streak.current).withValues(alpha: 0.5);
      } else {
        paint
          ..strokeWidth = stroke * 0.8
          ..color = QColors.hairline;
      }
      canvas.drawArc(ring, start, step - _gap, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StreakRingPainter old) =>
      old.streak.current != streak.current || old.streak.todayCounted != streak.todayCounted;
}
