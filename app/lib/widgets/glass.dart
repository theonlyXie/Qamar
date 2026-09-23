import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The shape a piece of glass takes. Controls are round-ended ([capsule]) or
/// round ([circle]); a panel of glass ([rounded]) takes the corner of what it
/// is, concentric with what holds it.
enum QGlassShape { capsule, circle, rounded }

/// Liquid Glass, in black and white (the mono-glass skill).
///
/// The floating control layer — never content. The orb, the tree's buttons,
/// the conversation's composer, a floating back button, a sheet's handle: the
/// things that float above the page and act on it. Content (a card, a row, a
/// message) sits on the canvas's solid surfaces instead, where its words
/// always have the contrast they were checked for.
///
/// What it is made of, from the back:
///  * the page behind, blurred ([blur]) so the words over it stay legible and
///    the layer reads as a material rather than a hole;
///  * a breath of white ([QColors.glassFill]; [clear] for a thinner one over
///    a busy picture, pressed for a step brighter);
///  * a lens: the upper part a touch brighter than the lower, as light caught
///    in a curved surface is;
///  * a specular edge, bright along the top and fading down the sides
///    ([QColors.glassEdgeTop] → [QColors.glassEdgeBottom]).
///
/// When the phone asks for more contrast (iOS Increase Contrast, the closest
/// Flutter can see to Reduce Transparency) it turns solid: no blur, the raised
/// surface, a strong edge — the same shape, nothing seen through it.
class QGlass extends StatelessWidget {
  final Widget child;
  final QGlassShape shape;

  /// The corner of a [QGlassShape.rounded] panel.
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool clear;
  final bool pressed;
  final double blur;
  final double? width;
  final double? height;

  const QGlass({
    super.key,
    required this.child,
    this.shape = QGlassShape.capsule,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.clear = false,
    this.pressed = false,
    this.blur = 20,
    this.width,
    this.height,
  });

  /// The glass's own layers, for tests: the blur, the fill, the edge.
  static const blurKey = ValueKey('glass-blur');
  static const fillKey = ValueKey('glass-fill');
  static const edgeKey = ValueKey('glass-edge');

  ShapeBorder get _border => switch (shape) {
        QGlassShape.capsule => const StadiumBorder(),
        QGlassShape.circle => const CircleBorder(),
        QGlassShape.rounded => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      };

  /// The fill a piece of glass has in its state.
  static Color fillFor({required bool solid, required bool pressed, required bool clear}) {
    if (solid) return pressed ? QColors.surfaceHigh : QColors.glassSolid;
    if (pressed) return QColors.glassFillPressed;
    return clear ? QColors.glassFillClear : QColors.glassFill;
  }

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.maybeHighContrastOf(context) ?? false;
    final border = _border;
    Widget body = DecoratedBox(
      key: fillKey,
      decoration: ShapeDecoration(color: fillFor(solid: solid, pressed: pressed, clear: clear), shape: border),
      child: CustomPaint(
        key: edgeKey,
        foregroundPainter: _GlassEdge(border, solid: solid),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (width != null || height != null) body = SizedBox(width: width, height: height, child: body);
    if (solid) return body;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: border, textDirection: Directionality.maybeOf(context)),
      child: BackdropFilter(
        key: blurKey,
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      ),
    );
  }
}

/// The lens and the specular edge, drawn over the glass's fill.
class _GlassEdge extends CustomPainter {
  final ShapeBorder border;
  final bool solid;
  const _GlassEdge(this.border, {required this.solid});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = border.getOuterPath(rect);
    if (solid) {
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = QColors.hairlineStrong,
      );
      return;
    }
    // The lens: the top half a touch brighter than the bottom.
    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [QColors.glassLens, QColors.glassLens.withAlpha(0)],
          stops: const [0, 0.55],
        ).createShader(rect),
    );
    canvas.restore();
    // The edge, inset by half its width so all of it is inside the shape.
    final edge = border.getOuterPath(rect.deflate(0.5));
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [QColors.glassEdgeTop, QColors.glassEdgeBottom, QColors.glassEdgeBottom],
          stops: [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge old) => old.border != border || old.solid != solid;
}
