import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/colors.dart';

/// How the moon looks: open eyes, eyes closed in a smile, or asleep.
enum MoonMood { happy, joy, sleepy }

/// Qamar's mascot (the qamar-design skill): the moon as a character, drawn
/// in the Nutri AI kit's cartoon line (a heavy black line, a white body,
/// solid black for shadow), where the kit has its fruit. A full moon with a
/// crescent of shadow down its left side — the phase, lit on the right as
/// the app's moons are; the brand's mark — a face, a crater or two and a
/// blush. The whole character stands on a pastel: on
/// the dark its line and its sneakers would be lost.
///
/// [full] draws the whole character, for a welcome or an empty page: arms,
/// one of them waving, legs in sneakers, sparkles round it, and its shadow
/// on the ground, as the kit's characters stand. Otherwise the face alone,
/// for a card or a row.
///
/// It is a picture, and says nothing to a screen reader.
class MoonMascot extends StatelessWidget {
  final double size;
  final MoonMood mood;
  final bool full;
  const MoonMascot({super.key, required this.size, this.mood = MoonMood.happy, this.full = false});

  /// The height the mascot takes for its [size] (its width).
  static double heightFor(double size, {required bool full}) => full ? size * 1.2 : size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: Size(size, heightFor(size, full: full)),
          painter: MoonMascotPainter(mood: mood, full: full),
        ),
      );
}

/// The mascot's drawing, in a box 100 wide (and 120 tall when [full]).
class MoonMascotPainter extends CustomPainter {
  final MoonMood mood;
  final bool full;
  const MoonMascotPainter({required this.mood, required this.full});

  static const _ink = QColors.onPastel;
  static const _body = QColors.white;
  static const _blush = QColors.coral;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    // Drawn below with its shadow on the right and its face turned left;
    // shown mirrored, so it is lit on the right, as the app's moons are (a
    // waxing moon, seen from Egypt), in both languages.
    canvas.translate(size.width, 0);
    canvas.scale(-k, k);
    final line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = full ? 3 : 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final ink = Paint()..color = _ink;

    const c = Offset(50, 50);
    final r = full ? 36.0 : 44.0;

    if (full) {
      // Its shadow on the ground, then the legs and the sneakers.
      canvas.drawOval(Rect.fromCenter(center: const Offset(50, 113), width: 58, height: 9), ink);
      for (final dx in const [-11.0, 11.0]) {
        canvas.drawLine(Offset(50 + dx, c.dy + r - 4), Offset(50 + dx * 1.15, 103), line);
        final shoe = Rect.fromCenter(center: Offset(50 + dx * 1.15 + (dx < 0 ? -3 : 3), 106), width: 15, height: 8);
        // A sneaker's toe and heel are round: half its height.
        canvas.drawRRect(RRect.fromRectAndRadius(shoe, Radius.circular(shoe.height / 2)), ink);
        canvas.drawLine(shoe.centerLeft + const Offset(4, -1), shoe.centerRight + const Offset(-4, -1), Paint()
          ..color = _body
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round);
      }
      // Arms: one waving above the shoulder (on the right, as shown), the
      // other at rest.
      final wave = Path()
        ..moveTo(c.dx - r + 3, c.dy + 6)
        ..quadraticBezierTo(c.dx - r - 10, c.dy - 2, c.dx - r - 8, c.dy - 18);
      canvas.drawPath(wave, line);
      canvas.drawCircle(Offset(c.dx - r - 8, c.dy - 21), 4.2, Paint()..color = _body);
      canvas.drawCircle(Offset(c.dx - r - 8, c.dy - 21), 4.2, line);
      final rest = Path()
        ..moveTo(c.dx + r - 2, c.dy + 10)
        ..quadraticBezierTo(c.dx + r + 9, c.dy + 14, c.dx + r + 8, c.dy + 25);
      canvas.drawPath(rest, line);
      canvas.drawCircle(Offset(c.dx + r + 8, c.dy + 28), 4.2, Paint()..color = _body);
      canvas.drawCircle(Offset(c.dx + r + 8, c.dy + 28), 4.2, line);
      // Sparkles round it.
      _sparkle(canvas, const Offset(14, 14), 7, line);
      _sparkle(canvas, const Offset(88, 18), 5, line);
      _sparkle(canvas, const Offset(92, 52), 3.5, line);
      canvas.drawCircle(const Offset(8, 36), 1.8, ink);
      canvas.drawCircle(const Offset(80, 6), 1.6, ink);
    }

    // The body, and down its right side (its left, as shown) the crescent of
    // shadow: the disc less a disc nudged to the left.
    final disc = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(disc, Paint()..color = _body);
    final lit = Path()..addOval(Rect.fromCircle(center: c + Offset(-r * 0.2, -r * 0.06), radius: r * 0.96));
    canvas.drawPath(Path.combine(PathOperation.difference, disc, lit), ink);

    // Craters on the lit side.
    final craterLine = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = full ? 2.2 : 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c + Offset(-r * 0.52, -r * 0.42), r * 0.12, craterLine);
    canvas.drawCircle(c + Offset(r * 0.18, -r * 0.62), r * 0.08, craterLine);
    if (full) canvas.drawCircle(c + Offset(-r * 0.5, r * 0.62), r * 0.07, craterLine);

    // The blush, under the eyes.
    final blush = Paint()..color = _blush;
    for (final dx in const [-0.5, 0.28]) {
      canvas.drawOval(Rect.fromCenter(center: c + Offset(r * dx, r * 0.24), width: r * 0.26, height: r * 0.15), blush);
    }

    // The eyes.
    final eyeY = c.dy - r * 0.02;
    for (final dx in const [-0.3, 0.1]) {
      final at = Offset(c.dx + r * dx, eyeY);
      switch (mood) {
        case MoonMood.happy:
          canvas.drawOval(Rect.fromCenter(center: at, width: r * 0.17, height: r * 0.23), ink);
          canvas.drawCircle(at + Offset(-r * 0.03, -r * 0.05), r * 0.035, Paint()..color = _body);
        case MoonMood.joy:
          final arc = Path()
            ..moveTo(at.dx - r * 0.09, at.dy + r * 0.03)
            ..quadraticBezierTo(at.dx, at.dy - r * 0.1, at.dx + r * 0.09, at.dy + r * 0.03);
          canvas.drawPath(arc, line);
        case MoonMood.sleepy:
          final arc = Path()
            ..moveTo(at.dx - r * 0.09, at.dy)
            ..quadraticBezierTo(at.dx, at.dy + r * 0.08, at.dx + r * 0.09, at.dy);
          canvas.drawPath(arc, line);
      }
    }

    // The smile.
    final mouth = Path()
      ..moveTo(c.dx - r * 0.2, c.dy + r * 0.2)
      ..quadraticBezierTo(c.dx - r * 0.1, c.dy + r * (mood == MoonMood.sleepy ? 0.28 : 0.36), c.dx + r * 0.02, c.dy + r * 0.2);
    canvas.drawPath(mouth, line);

    // The outline over everything, so the shadow's edge is clean.
    canvas.drawPath(disc, line);
    canvas.restore();
  }

  /// A four-point sparkle in the kit's line, [s] from its middle to a tip:
  /// four points joined by curves drawn in toward the middle.
  static void _sparkle(Canvas canvas, Offset at, double s, Paint line) {
    final p = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final tip = at + Offset(math.cos(a), math.sin(a)) * s;
      final next = at + Offset(math.cos(a + math.pi / 2), math.sin(a + math.pi / 2)) * s;
      final pull = at + Offset(math.cos(a + math.pi / 4), math.sin(a + math.pi / 4)) * (s * 0.16);
      if (i == 0) p.moveTo(tip.dx, tip.dy);
      p.quadraticBezierTo(pull.dx, pull.dy, next.dx, next.dy);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = _body);
    canvas.drawPath(p, Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = line.strokeWidth * 0.8
      ..strokeJoin = StrokeJoin.miter);
  }

  @override
  bool shouldRepaint(MoonMascotPainter old) => old.mood != mood || old.full != full;
}
