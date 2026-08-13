import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// The Qamar moon — an image that breathes, glows and (optionally) wanders
/// and throws off orbiting sparks, matching the prototype's qbreath/qhalo/
/// qfloat/qorbit keyframes. One widget covers every place the orb appears:
/// welcome hero, nav orb, chat companion, tree center.
class LivingOrb extends StatefulWidget {
  final double size;
  final bool wander;
  final bool sparks;
  final bool activeRings; // extra pulsing rings, used while "listening"
  final Duration breathDuration;
  final Duration haloDuration;
  final Duration wanderDuration;
  final VoidCallback? onTap;
  final String assetPath;

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
    this.assetPath = 'assets/images/qamar_orb_sm.png',
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
        final haloOpacity = 0.32 + 0.40 * haloT;
        final offset = widget.wander ? Offset(_wanderOffset.value.dx * s, _wanderOffset.value.dy * s) : Offset.zero;

        return Transform.translate(
          offset: offset,
          child: SizedBox(
            width: s * 1.7,
            height: s * 1.7,
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
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x8C7B6CFF), Color(0x1F4F7CFF), Colors.transparent],
                          stops: [0.0, 0.45, 0.7],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.sparks) ..._buildSparks(s),
                if (widget.activeRings) ..._buildActiveRings(s),
                Transform.scale(
                  scale: scale,
                  child: Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(image: AssetImage(widget.assetPath), fit: BoxFit.cover),
                      boxShadow: [
                        BoxShadow(color: QColors.violet.withOpacity(0.55), blurRadius: s * 0.5),
                      ],
                    ),
                  ),
                ),
              ],
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
