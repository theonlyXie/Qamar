import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The Qamar moon, drawn rather than photographed.
///
/// This replaces the flat `qamar_orb.png` that used to sit inside [LivingOrb].
/// A picture of a moon always reads as a picture — it has fixed lighting, a
/// baked-in phase and pixels that soften as it scales up. This paints the moon
/// as an actual lit sphere:
///
///  * a radial "lit" gradient whose bright pole sits toward the light source,
///    with limb darkening toward the edge, so the disc reads as a ball,
///  * mare (the dark basalt seas) as soft irregular patches,
///  * craters foreshortened by their distance from the disc centre — a crater
///    near the limb is squashed along the radius, exactly as a sphere does it,
///    each with a bright sunward rim and a shadowed opposite wall,
///  * a true elliptical terminator (the day/night line on a sphere projects to
///    a half-ellipse, never an offset circle), and
///  * earthshine on the night side, so the whole sphere stays visible instead
///    of the moon looking bitten.
///
/// Nothing here animates position or scale — [LivingOrb] owns the breathing,
/// halo, wander and sparks. The only motion is a very slow phase drift, so the
/// terminator creeps the way a real moon's does.
class QamarMoon extends StatefulWidget {
  final double size;

  /// Seconds for one full phase sweep. Deliberately long — this should never
  /// read as an animation, only as something that is quietly alive.
  final Duration phaseDuration;

  /// Fixes the phase instead of drifting it. Useful for tests and goldens.
  final double? staticPhase;

  /// Pins the phase to the day's state (see OrbState.moonPhase) while keeping
  /// the slow drift, narrowed to a whisper either side. Null keeps the
  /// decorative waxing band.
  final double? phase;

  const QamarMoon({
    super.key,
    required this.size,
    this.phaseDuration = const Duration(seconds: 90),
    this.staticPhase,
    this.phase,
  });

  @override
  State<QamarMoon> createState() => _QamarMoonState();
}

class _QamarMoonState extends State<QamarMoon> with SingleTickerProviderStateMixin {
  AnimationController? _phase;

  @override
  void initState() {
    super.initState();
    if (widget.staticPhase == null) {
      _phase = AnimationController(vsync: this, duration: widget.phaseDuration)..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _phase?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _phase;
    if (controller == null) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _MoonPainter(phase: widget.staticPhase!),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        // Drift across a narrow band: always waxing, never full, so the
        // crescent stays Qamar's mark — but wide enough that the cratered
        // surface is the thing you actually look at.
        painter: _MoonPainter(
          phase: widget.phase == null
              ? 0.28 + 0.16 * controller.value
              : (widget.phase! - 0.02 + 0.04 * controller.value).clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

/// A surface feature in unit-disc coordinates: (u, v) in [-1, 1], where
/// u² + v² < 1 lands on the disc. [r] is the radius as a fraction of the moon.
class _Crater {
  final double u, v, r, depth;
  const _Crater(this.u, this.v, this.r, this.depth);
}

/// Hand-placed rather than random so the moon is identical on every frame,
/// every device and every rebuild — a reshuffling surface would read as noise.
const _craters = <_Crater>[
  _Crater(-0.34, -0.42, 0.150, 0.85),
  _Crater(0.12, -0.30, 0.093, 0.62),
  _Crater(-0.06, 0.14, 0.128, 0.74),
  _Crater(0.40, 0.24, 0.078, 0.55),
  _Crater(-0.52, 0.22, 0.104, 0.68),
  _Crater(0.26, 0.56, 0.088, 0.58),
  _Crater(-0.20, 0.62, 0.068, 0.48),
  _Crater(0.56, -0.44, 0.062, 0.44),
  _Crater(-0.68, -0.14, 0.055, 0.40),
  _Crater(0.02, -0.66, 0.072, 0.52),
  _Crater(0.34, -0.06, 0.048, 0.36),
  _Crater(-0.42, -0.02, 0.042, 0.32),
];

/// The dark seas. Larger, softer and lower-contrast than craters.
const _maria = <_Crater>[
  _Crater(-0.26, -0.30, 0.40, 0.22),
  _Crater(0.20, 0.34, 0.34, 0.17),
  _Crater(-0.44, 0.34, 0.24, 0.13),
];

class _MoonPainter extends CustomPainter {
  /// 0 = fully lit, 1 = fully dark. Controls how far the terminator ellipse
  /// bulges across the disc.
  final double phase;

  _MoonPainter({required this.phase});

  /// Unit vector toward the sun, in disc space. Upper-right.
  static const _lightU = 0.82, _lightV = -0.57;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final disc = Rect.fromCircle(center: c, radius: r);

    canvas.save();
    canvas.clipPath(Path()..addOval(disc));

    _paintSurface(canvas, c, r);
    // Below ~34px craters collapse into mud; the gradient alone reads better.
    if (size.width >= 34) {
      _paintMaria(canvas, c, r);
      _paintCraters(canvas, c, r, size.width);
    }
    _paintNightSide(canvas, c, r);
    _paintLimbDarkening(canvas, c, r);

    canvas.restore();

    _paintRim(canvas, c, r);
  }

  /// The lit sphere: brightest at the sub-solar point, falling off toward the
  /// limb the way a diffusely lit ball does.
  void _paintSurface(Canvas canvas, Offset c, double r) {
    final sub = Offset(c.dx + _lightU * r * 0.55, c.dy + _lightV * r * 0.55);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFFF4F1FB),
            Color(0xFFDCD9EE),
            Color(0xFFB2B7D6),
            Color(0xFF7D86AF),
            Color(0xFF4E5883),
          ],
          stops: const [0.0, 0.28, 0.55, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: sub, radius: r * 1.42)),
    );
  }

  void _paintMaria(Canvas canvas, Offset c, double r) {
    for (final m in _maria) {
      final p = _project(c, r, m.u, m.v);
      if (p == null) continue;
      canvas.drawOval(
        Rect.fromCenter(center: p.center, width: m.r * r * 2 * p.squash, height: m.r * r * 2),
        Paint()
          ..color = const Color(0xFF39406B).withValues(alpha: m.depth)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.07),
      );
    }
  }

  void _paintCraters(Canvas canvas, Offset c, double r, double px) {
    for (final k in _craters) {
      // Skip detail that would render sub-pixel at small sizes.
      if (k.r * px < 3.2) continue;
      final p = _project(c, r, k.u, k.v);
      if (p == null) continue;

      final w = k.r * r * p.squash, h = k.r * r;
      final rect = Rect.fromCenter(center: p.center, width: w * 2, height: h * 2);

      canvas.save();
      canvas.translate(p.center.dx, p.center.dy);
      canvas.rotate(p.angle);
      canvas.translate(-p.center.dx, -p.center.dy);

      // Floor: a shallow dish, darker away from the sun.
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF333A63).withValues(alpha: 0.88 * k.depth),
              const Color(0xFF262C51).withValues(alpha: 0.52 * k.depth),
            ],
          ).createShader(rect)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.15),
      );

      // Sunward rim catches the light; the far wall falls into shadow.
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, h * 0.24)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.11);

      final lightAngle = math.atan2(_lightV, _lightU) - p.angle;
      canvas.drawArc(rect, lightAngle - 1.15, 2.30,
          false, rim..color = const Color(0xFFFFFDFF).withValues(alpha: 0.78 * k.depth));
      canvas.drawArc(rect, lightAngle + math.pi - 1.15, 2.30,
          false, rim..color = const Color(0xFF1E2340).withValues(alpha: 0.72 * k.depth));

      canvas.restore();
    }
  }

  /// The night side, bounded by a true elliptical terminator, filled with
  /// earthshine rather than black so the sphere stays readable.
  void _paintNightSide(Canvas canvas, Offset c, double r) {
    final path = _terminatorPath(c, r);

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF0A1024).withValues(alpha: 0.88),
            const Color(0xFF141C3C).withValues(alpha: 0.80),
            const Color(0xFF1E2750).withValues(alpha: 0.62),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Soften the terminator itself — on an airless body it is sharp, but a
    // hairline here reads as a cut-out sticker at small sizes.
    canvas.saveLayer(Rect.fromCircle(center: c, radius: r * 1.2), Paint());
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF10182F).withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.028),
    );
    canvas.restore();
  }

  /// Half-ellipse from the north pole to the south pole, closed around the
  /// unlit limb. Semi-axis [r * phaseWidth] horizontally, [r] vertically.
  Path _terminatorPath(Offset c, double r) {
    // How far the terminator bulges past the centre line, signed: positive
    // sweeps the shadow toward the lit limb, thinning the crescent.
    final bulge = r * (phase.clamp(0.0, 1.0) * 1.05 - 0.14);
    final path = Path()..moveTo(c.dx, c.dy - r);

    const steps = 72;
    for (var i = 0; i <= steps; i++) {
      final t = -math.pi / 2 + math.pi * (i / steps);
      path.lineTo(c.dx + bulge * math.cos(t), c.dy + r * math.sin(t));
    }
    for (var i = 0; i <= steps; i++) {
      final t = math.pi / 2 + math.pi * (i / steps);
      path.lineTo(c.dx + r * math.cos(t), c.dy + r * math.sin(t));
    }
    path.close();
    return path;
  }

  /// Global falloff at the edge, sitting over everything so craters near the
  /// limb dim along with the surface.
  void _paintLimbDarkening(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            const Color(0xFF0B1226).withValues(alpha: 0.30),
            const Color(0xFF080D1C).withValues(alpha: 0.60),
          ],
          stops: const [0.0, 0.66, 0.88, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  /// A cool rim light plus a breath of atmosphere just outside the disc, which
  /// is what sells "sphere in space" rather than "circle on a screen".
  void _paintRim(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(
      c,
      r * 0.995,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, r * 0.030)
        ..color = const Color(0xFFCFE3FF).withValues(alpha: 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.055),
    );
    canvas.drawCircle(
      c,
      r * 1.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.05)
        ..color = const Color(0xFF7B6CFF).withValues(alpha: 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.09),
    );
  }

  /// Maps unit-disc coordinates onto the sphere, returning where the feature
  /// lands, how much it is squashed by foreshortening, and the radial angle it
  /// should be squashed along. Returns null for points off the disc.
  _Projected? _project(Offset c, double r, double u, double v) {
    final d = math.sqrt(u * u + v * v);
    if (d >= 0.985) return null;
    return _Projected(
      center: Offset(c.dx + u * r, c.dy + v * r),
      squash: math.sqrt(1 - d * d),
      angle: math.atan2(v, u),
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.phase != phase;
}

class _Projected {
  final Offset center;
  final double squash;
  final double angle;
  const _Projected({required this.center, required this.squash, required this.angle});
}
