import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// The shape a piece of glass takes. Controls are round-ended ([capsule]) or
/// round ([circle]); a panel of glass ([rounded]) takes the corner of what it
/// is, concentric with what holds it.
enum QGlassShape { capsule, circle, rounded }

/// Liquid Glass, the floating layer (the liquid-glass skill).
///
/// The things that float above the page and act on it: the orb, the tree's
/// buttons, the conversation's composer, a floating back button, the Su chip.
/// Cards and sheets are glass too, as panes (QDecor.card, QSheetPanel); this
/// is the control. With a [tint] it is burgundy glass: the primary button,
/// the send button, a chosen chip — the colour of the one thing to do, with
/// the same lens and a brighter rim.
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

  /// How much of what is behind is blurred. None for glass that does not
  /// float over moving content (a button on a card), and none for tinted
  /// glass, which nothing shows through.
  final double blur;
  final double? width;
  final double? height;

  /// Burgundy glass ([QColors.accent]), or null for clear.
  final Color? tint;

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
    this.tint,
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
  static Color fillFor({required bool solid, required bool pressed, required bool clear, Color? tint}) {
    if (tint != null) return pressed && tint == QColors.accent ? QColors.accentPressed : tint;
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
      decoration: ShapeDecoration(color: fillFor(solid: solid, pressed: pressed, clear: clear, tint: tint), shape: border),
      child: CustomPaint(
        key: edgeKey,
        foregroundPainter: _GlassEdge(border, solid: solid, tinted: tint != null),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (width != null || height != null) body = SizedBox(width: width, height: height, child: body);
    if (solid || tint != null || blur <= 0) return body;
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

/// The lens and the specular edge, drawn over the glass's fill. Tinted glass
/// catches more light: its lens and its rim are a step brighter, as a
/// coloured glass lit from above is.
class _GlassEdge extends CustomPainter {
  final ShapeBorder border;
  final bool solid;
  final bool tinted;
  const _GlassEdge(this.border, {required this.solid, this.tinted = false});

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
          colors: [tinted ? QColors.glassFill : QColors.glassLens, QColors.glassLens.withAlpha(0)],
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
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tinted ? QColors.glassRimTinted : QColors.glassEdgeTop, QColors.glassEdgeBottom, QColors.glassEdgeBottom],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge old) => old.border != border || old.solid != solid || old.tinted != tinted;
}
