import 'package:flutter/material.dart';
import 'colors.dart';

/// The corners (the liquid-glass skill). Controls are round-ended; everything
/// that holds content takes one of three corners, by what it is, and a shape
/// inside another keeps the outer corner less the space between them, so the
/// two stay concentric (radii_test.dart).
class QRadii {
  QRadii._();

  /// Anything a finger presses: buttons, chips, the composer, toggles. Drawn
  /// as a capsule (StadiumBorder) whatever its height.
  static const pill = 999.0;

  /// A small shape inside another: a thumbnail, a bar, a wash.
  static const inset = 12.0;

  /// A field, a notice, a bubble: something inside a card or on the page.
  static const control = 18.0;

  /// A card: anything that holds content on the canvas.
  static const card = 24.0;

  /// The top corners of a sheet rising from the bottom.
  static const sheet = 32.0;

  /// The corner of a shape [inset] points inside one with corner [outer]:
  /// concentric, never smaller than the inset corner.
  static double inside(double outer, double inset) => (outer - inset).clamp(inset, outer).toDouble();
}

/// The spacing steps, on a 4-point grid.
class QSpace {
  QSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// The page's side margin.
  static const page = 20.0;
}

ThemeData buildQamarTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: QColors.canvas,
    canvasColor: QColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: QColors.accent,
      onPrimary: QColors.onAccent,
      secondary: QColors.accentInk,
      onSecondary: QColors.onInk,
      surface: QColors.surface,
      onSurface: QColors.ink,
      error: QColors.ink,
      onError: QColors.onInk,
      outline: QColors.hairlineStrong,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: QColors.ink,
      displayColor: QColors.ink,
    ),
    // The switch, Apple's way: on is a burgundy track under a white thumb,
    // off a raised grey track with a white one.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? QColors.inkDisabled : QColors.ink),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? QColors.accent : QColors.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : QColors.hairlineStrong),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: QColors.accentInk,
      selectionColor: QColors.accentWash,
      selectionHandleColor: QColors.accentInk,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: QColors.accentInk, linearTrackColor: QColors.hairline, circularTrackColor: QColors.hairline),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: QColors.hairline,
  );
}

/// Shared card and pill decorations so screens don't hand-roll BoxDecoration.
class QDecor {
  QDecor._();

  /// A card is a pane of Liquid Glass (the liquid-glass skill): white over
  /// the page's light, brighter at the top, with a rim that catches the
  /// light along its top edge ([QGlassRim]). No blur: a card is content, it
  /// scrolls, and blur there would cost frames; what shows through it is the
  /// page's burgundy light, which is smooth anyway. No shadow: on black a
  /// shadow has nothing to darken.
  ///
  /// [color] asks for a raised pane (surfaceRaised or surfaceHigh: pressed,
  /// or a shape inside another), a step brighter; the surface, or nothing,
  /// is the plain pane. [border] as hairlineStrong gives the stronger rim of
  /// something that must read as a boundary.
  static BoxDecoration card({
    Color? color,
    Color border = QColors.hairline,
    double radius = QRadii.card,
  }) =>
      BoxDecoration(
        color: _raised(color) ? QColors.glassRaised : null,
        gradient: _raised(color) ? null : _pane,
        border: border == QColors.hairlineStrong ? QGlassRim.strong : QGlassRim.soft,
        borderRadius: BorderRadius.circular(radius),
      );

  static bool _raised(Color? color) => color == QColors.surfaceRaised || color == QColors.surfaceHigh;

  static const _pane = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [QColors.glassPanelTop, QColors.glassPanel],
    stops: [0, 0.6],
  );

  /// The page's light, painted once behind every screen: a burgundy glow
  /// from just above the top of the screen, gone to black by about the
  /// middle. It stays where it is while the page scrolls, so the glass
  /// panels move over it.
  static const ambient = BoxDecoration(
    color: QColors.canvas,
    gradient: RadialGradient(
      center: Alignment(0, -1.25),
      radius: 1.35,
      colors: [QColors.ambient, QColors.canvas],
      stops: [0, 1],
    ),
  );

  /// A capsule drawn by its edge: a tag, a quiet chip. [fill] shows while it
  /// is pressed or selected.
  static BoxDecoration capsule({Color edge = QColors.hairlineStrong, Color fill = Colors.transparent}) => BoxDecoration(
        color: fill,
        border: Border.all(color: edge),
        borderRadius: const BorderRadius.all(Radius.circular(QRadii.pill)),
      );

  /// The chosen segment of a segmented control (the language toggle, the
  /// wallet's tabs): a raised pane of neutral glass. A mode is not an action,
  /// so it is not burgundy.
  ///
  /// Its edge is a plain Border, as [segmentRest]'s is, so the segment can
  /// animate between the two.
  static const segmentThumb = BoxDecoration(
    color: QColors.glassFillPressed,
    border: Border.fromBorderSide(BorderSide(color: QColors.hairlineStrong)),
    borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)),
  );

  /// A segment not chosen: nothing drawn, the same shape.
  static const segmentRest = BoxDecoration(
    color: Colors.transparent,
    border: Border.fromBorderSide(BorderSide(color: Colors.transparent)),
    borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)),
  );
}

/// The rim of a pane of glass: the edge bright where light meets the top of
/// it, fading to the hairline by the middle and staying there down the sides
/// and along the bottom. A [BoxBorder], so any BoxDecoration can wear it.
///
/// Its two instances are constants, so a decoration that animates from one
/// to the same one is identical and nothing needs interpolating.
class QGlassRim extends BoxBorder {
  /// The colour along the top edge, and down the rest of it.
  final Color light, edge;
  const QGlassRim._({required this.light, required this.edge});

  /// A card's rim.
  static const soft = QGlassRim._(light: QColors.glassRim, edge: QColors.hairline);

  /// The rim of something that must read as a boundary: a chosen or focused
  /// pane, a sheet.
  static const strong = QGlassRim._(light: QColors.glassEdgeTop, edge: QColors.hairlineStrong);

  static const double _width = 1;

  @override
  BorderSide get top => BorderSide(color: light, width: _width);

  @override
  BorderSide get bottom => BorderSide(color: edge, width: _width);

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(_width);

  @override
  ShapeBorder scale(double t) => this;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection, BoxShape shape = BoxShape.rectangle, BorderRadius? borderRadius}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [light, edge, edge],
        stops: const [0, 0.45, 1],
      ).createShader(rect);
    if (shape == BoxShape.circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2 - _width / 2, paint);
      return;
    }
    canvas.drawRRect((borderRadius ?? BorderRadius.zero).toRRect(rect).deflate(_width / 2), paint);
  }

  @override
  bool operator ==(Object other) => other is QGlassRim && other.light == light && other.edge == edge;

  @override
  int get hashCode => Object.hash(light, edge);
}

extension QTextStyleShortcuts on BuildContext {
  bool get isArabicDir => Directionality.of(this) == TextDirection.rtl;
}
