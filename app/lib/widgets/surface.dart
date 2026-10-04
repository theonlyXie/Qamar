import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';

/// The shape a control's surface takes: a rounded rectangle ([rounded], the
/// kit's buttons and fields), a capsule ([capsule], chips and the segmented
/// track) or a circle ([circle], the round buttons and the tab bar's).
enum QSurfaceShape { rounded, capsule, circle }

/// A control's surface, flat (the qamar-design skill): the Nutri AI kit's
/// grey 400 on the ground and on a card, a step lighter while pressed. With
/// a [tint] it is that colour: burgundy for the one thing to do (the primary
/// button, the send button, a chosen chip), a step deeper while pressed.
/// [clear] is for a control over a photo or the camera: the dark at half
/// strength, so the picture still shows round it.
///
/// No blur, no lens, no rim and no shadow: the kit is flat, and a surface
/// says what it is by its colour and its shape.
class QSurface extends StatelessWidget {
  final Widget child;
  final QSurfaceShape shape;

  /// The corner of a [QSurfaceShape.rounded] surface.
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool clear;
  final bool pressed;
  final double? width;
  final double? height;

  /// The fill, when it is not the control grey: [QColors.accent] for the
  /// primary, or a colour of its own.
  final Color? tint;

  const QSurface({
    super.key,
    required this.child,
    this.shape = QSurfaceShape.rounded,
    this.radius = QRadii.control,
    this.padding = EdgeInsets.zero,
    this.clear = false,
    this.pressed = false,
    this.width,
    this.height,
    this.tint,
  });

  /// The surface's fill, for tests.
  static const fillKey = ValueKey('surface-fill');

  ShapeBorder get _border => switch (shape) {
        QSurfaceShape.capsule => const StadiumBorder(),
        QSurfaceShape.circle => const CircleBorder(),
        QSurfaceShape.rounded => RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      };

  /// The fill a surface has in its state.
  static Color fillFor({required bool pressed, required bool clear, Color? tint}) {
    if (tint == QColors.accent) return pressed ? QColors.accentPressed : QColors.accent;
    if (tint != null) return tint;
    if (clear) return pressed ? QColors.overPhotoPressed : QColors.overPhoto;
    return pressed ? QColors.surfaceHigh : QColors.surfaceRaised;
  }

  @override
  Widget build(BuildContext context) {
    Widget body = DecoratedBox(
      key: fillKey,
      decoration: ShapeDecoration(color: fillFor(pressed: pressed, clear: clear, tint: tint), shape: _border),
      child: Padding(padding: padding, child: child),
    );
    if (width != null || height != null) body = SizedBox(width: width, height: height, child: body);
    return body;
  }
}
