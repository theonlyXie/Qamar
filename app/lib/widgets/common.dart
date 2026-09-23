import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/strings.dart';
import '../models/problem.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';

/// The touch rule every control here keeps (O11).
///
///  * At least [QLayout.minTap] points each way take the touch, whatever size
///    is drawn: [builder] draws the control, centred in that area. A compact
///    row keeps its look and the finger still gets a whole target.
///  * The drawing answers on the press, not the release ([builder] is told
///    when the finger is down).
///  * A control with nothing to do ([onTap] null) says so: it takes no touch,
///    and a screen reader hears it as not enabled. The drawing shows it too,
///    with [QDisabled]'s faint edge and muted label.
class QTapArea extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(BuildContext context, bool pressed) builder;

  /// What a screen reader says, when the drawing has no words of its own (an
  /// icon). Drawn words are read as they are.
  final String? label;
  final String? hint;
  final bool link;
  final double minWidth;
  final double minHeight;

  const QTapArea({
    super.key,
    required this.onTap,
    required this.builder,
    this.label,
    this.hint,
    this.link = false,
    this.minWidth = QLayout.minTap,
    this.minHeight = QLayout.minTap,
  });

  @override
  State<QTapArea> createState() => _QTapAreaState();
}

class _QTapAreaState extends State<QTapArea> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      container: true,
      button: !widget.link,
      link: widget.link,
      enabled: enabled,
      label: widget.label,
      hint: widget.hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _press(true) : null,
        onTapUp: enabled ? (_) => _press(false) : null,
        onTapCancel: enabled ? () => _press(false) : null,
        onTap: widget.onTap,
        child: _MinTap(minWidth: widget.minWidth, minHeight: widget.minHeight, child: widget.builder(context, enabled && _down)),
      ),
    );
  }
}

/// Lays its child out exactly as its parent asks — so a button asked to fill
/// a row still fills it — and is itself at least [minWidth] × [minHeight],
/// with the child centred in the extra. The extra is part of the control:
/// the GestureDetector around it takes touches across all of it.
class _MinTap extends SingleChildRenderObjectWidget {
  final double minWidth;
  final double minHeight;
  const _MinTap({required this.minWidth, required this.minHeight, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMinTap(minWidth, minHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMinTap renderObject) {
    renderObject
      ..minWidth = minWidth
      ..minHeight = minHeight;
  }
}

class _RenderMinTap extends RenderShiftedBox {
  _RenderMinTap(this._minWidth, this._minHeight) : super(null);

  double _minWidth;
  set minWidth(double v) {
    if (v == _minWidth) return;
    _minWidth = v;
    markNeedsLayout();
  }

  double _minHeight;
  set minHeight(double v) {
    if (v == _minHeight) return;
    _minHeight = v;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(_minWidth, child?.getMinIntrinsicWidth(height) ?? 0);
  @override
  double computeMaxIntrinsicWidth(double height) => math.max(_minWidth, child?.getMaxIntrinsicWidth(height) ?? 0);
  @override
  double computeMinIntrinsicHeight(double width) => math.max(_minHeight, child?.getMinIntrinsicHeight(width) ?? 0);
  @override
  double computeMaxIntrinsicHeight(double width) => math.max(_minHeight, child?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child?.getDryLayout(constraints) ?? Size.zero;
    return constraints.constrain(Size(math.max(c.width, _minWidth), math.max(c.height, _minHeight)));
  }

  @override
  void performLayout() {
    final c = child!;
    c.layout(constraints, parentUsesSize: true);
    size = constraints.constrain(Size(math.max(c.size.width, _minWidth), math.max(c.size.height, _minHeight)));
    (c.parentData! as BoxParentData).offset = Offset((size.width - c.size.width) / 2, (size.height - c.size.height) / 2);
  }
}

/// How a control with nothing to do is drawn, everywhere (O11): no press, a
/// faint edge, a muted label, no fill or glow.
abstract final class QDisabled {
  /// Fainter than an enabled control's hairline.
  static final edge = QColors.borderSoft.withValues(alpha: 0.55);
  static const label = QColors.textDisabled;
  static const fill = QColors.cardDeep;
}

class QPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Gradient gradient;
  const QPrimaryButton({super.key, required this.label, required this.onTap, this.height = 52, this.gradient = QColors.brandGradient});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      builder: (context, pressed) => AnimatedOpacity(
        opacity: pressed ? 0.82 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: enabled
              ? QDecor.gradientButton(gradient: gradient)
              : BoxDecoration(
                  color: QDisabled.fill,
                  border: Border.all(color: QDisabled.edge),
                  borderRadius: BorderRadius.circular(QRadii.control),
                ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: QText.body(size: 17, weight: FontWeight.w600, color: enabled ? QColors.onAccent : QDisabled.label)),
        ),
      ),
    );
  }
}

/// A compact call to action inside a card: the brand gradient drawn as a
/// 40pt pill, touched across 48 (O11). Where [QPrimaryButton] would be too
/// much, and a text link too little.
class QPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const QPillButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: onTap,
        builder: (context, pressed) => AnimatedOpacity(
          opacity: pressed ? 0.82 : 1,
          duration: const Duration(milliseconds: 90),
          // As wide as its label: a Container with an alignment would fill
          // the row.
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(QRadii.pill))),
            child: Center(widthFactor: 1, child: Text(label, style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.onAccent))),
          ),
        ),
      );
}

/// How a [QSpringIn] arrives.
enum QArrive { fade, rise, grow }

/// An entrance on a spring rather than a curve over a set time: the settle
/// spring (damping 1.0, response 0.35s; QSpring), so it arrives quickly and
/// comes to rest without a bounce. [QArrive.rise] comes up from below its
/// own height (a sheet), [QArrive.grow] from a little smaller and clear (the
/// tree's ring), [QArrive.fade] only fades. With the platform's reduce-motion
/// on, every one of them is a plain 150ms cross-fade: nothing moves.
class QSpringIn extends StatefulWidget {
  final Widget child;
  final QArrive arrive;
  const QSpringIn({super.key, required this.arrive, required this.child});

  /// Where the entrance is at [v] (0 → 1): the offset as a fraction of the
  /// child's height, the scale, the opacity. Clamped: a critically damped
  /// spring does not pass 1, and nothing may.
  static ({double dy, double scale, double opacity}) at(QArrive arrive, double v, {required bool still}) {
    final t = v.clamp(0.0, 1.0);
    if (still) return (dy: 0, scale: 1, opacity: t);
    return switch (arrive) {
      QArrive.rise => (dy: 1 - t, scale: 1, opacity: 1),
      QArrive.grow => (dy: 0, scale: 0.94 + 0.06 * t, opacity: math.min(1, t * 1.6)),
      QArrive.fade => (dy: 0, scale: 1, opacity: t),
    };
  }

  @override
  State<QSpringIn> createState() => _QSpringInState();
}

class _QSpringInState extends State<QSpringIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  bool _started = false, _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    QSpring.drive(_c, 1, still: _still);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final m = QSpringIn.at(widget.arrive, _c.value, still: _still);
          Widget out = child!;
          if (m.dy != 0) out = FractionalTranslation(translation: Offset(0, m.dy), child: out);
          if (m.scale != 1) out = Transform.scale(scale: m.scale, child: out);
          if (m.opacity < 1) out = Opacity(opacity: m.opacity, child: out);
          return out;
        },
      );
}

/// Holds a sheet on screen while it leaves, so it can go the way it came
/// (down, on the settle spring) instead of vanishing on the frame its state
/// closed. [open] is the sheet's state; [child] stays built until its
/// [QSheetScrim] has finished leaving, whatever closed it: the scrim, a
/// drag, its own button or the phone's back. Opened again while leaving, it
/// turns round from where it is.
class QSheetSlot extends StatefulWidget {
  final bool open;
  final Widget child;
  const QSheetSlot({super.key, required this.open, required this.child});

  @override
  State<QSheetSlot> createState() => _QSheetSlotState();
}

class _QSheetSlotState extends State<QSheetSlot> {
  late bool _shown = widget.open;

  @override
  void didUpdateWidget(QSheetSlot old) {
    super.didUpdateWidget(old);
    if (widget.open) _shown = true;
  }

  void _gone() {
    if (mounted && !widget.open && _shown) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) {
    // Positioned, like the sheets it holds: a bare box in the shell's Stack
    // would give the Stack a size of its own, and shrink it to nothing.
    if (!_shown) return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    return _SheetExit(closing: !widget.open, onGone: _gone, child: widget.child);
  }
}

class _SheetExit extends InheritedWidget {
  final bool closing;
  final VoidCallback onGone;
  const _SheetExit({required this.closing, required this.onGone, required super.child});

  static _SheetExit? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SheetExit>();

  @override
  bool updateShouldNotify(_SheetExit old) => old.closing != closing;
}

/// A sheet's ground, and the sheet on it. The scrim fades in on the settle
/// spring while the sheet ([child]) rises from below its own height on it;
/// it leaves the same way, down and out. It can be dragged: it follows the
/// finger down, and on release goes where the release was heading — Apple's
/// projection of the velocity, as the orb's snap uses — either away or back
/// up, carrying the finger's speed into the spring. With reduce-motion on,
/// arriving and leaving are a plain fade; a drag still moves it, since the
/// finger is moving it.
///
/// A tap on the scrim, anywhere outside the sheet, is [onDismiss]; a screen
/// reader hears that layer as a button named "Close" (إغلاق), where it used
/// to be an unnamed button the size of the screen. The sheet takes its own
/// touches: it sits above the scrim, so nothing inside it needs to swallow
/// taps. [blur] blurs the page behind, in step with the scrim.
class QSheetScrim extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final double blur;
  const QSheetScrim({super.key, required this.onDismiss, this.blur = 0, required this.child});

  /// The dismiss layer and the sheet itself, for tests.
  static const dismissKey = ValueKey('sheet-dismiss');
  static const panelKey = ValueKey('sheet-panel');

  static String closeLabel(BuildContext context) => Directionality.of(context) == TextDirection.rtl ? 'إغلاق' : 'Close';

  /// Whether a release at [value] (1 at rest, 0 gone), moving at
  /// [velocity] points a second (down positive) on a sheet [height] tall,
  /// sends the sheet away: its projected rest is past half-way down, or it
  /// was thrown down faster than a flick.
  static bool releaseDismisses(double value, double velocity, double height) =>
      velocity > QSpring.flickSpeed || value - QSpring.project(velocity) / height < 0.5;

  @override
  State<QSheetScrim> createState() => _QSheetScrimState();
}

class _QSheetScrimState extends State<QSheetScrim> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  final _panel = GlobalKey();
  bool _started = false, _still = false, _leaving = false, _dragged = false;

  double get _height => (_panel.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 400;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_started) {
      _started = true;
      QSpring.drive(_c, 1, still: _still);
    }
    final exit = _SheetExit.maybeOf(context);
    if (exit == null) return;
    if (exit.closing && !_leaving) {
      _leave(0);
    } else if (!exit.closing && _leaving) {
      // Opened again on its way out: it turns round from where it is.
      _leaving = false;
      QSpring.drive(_c, 1, still: _still);
    }
  }

  void _leave(double velocity) {
    _leaving = true;
    QSpring.drive(_c, 0, still: _still && !_dragged, velocity: velocity).whenCompleteOrCancel(() {
      if (mounted && _leaving && _c.value <= 0.001) _SheetExit.maybeOf(context)?.onGone();
    });
  }

  void _dismiss([double velocity = 0]) {
    if (_leaving) return;
    _leave(velocity);
    widget.onDismiss();
  }

  void _dragStart(DragStartDetails _) {
    if (_leaving) return;
    _c.stop();
    _dragged = true;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_leaving) return;
    _c.value = (_c.value - d.delta.dy / _height).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    if (_leaving) return;
    final h = _height;
    final down = d.velocity.pixelsPerSecond.dy;
    // The spring runs in sheet heights: the finger's speed, handed over.
    final v = -down / h;
    if (QSheetScrim.releaseDismisses(_c.value, down, h)) {
      _dismiss(v);
    } else {
      QSpring.drive(_c, 1, still: false, velocity: v);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      excluding: _leaving,
      child: IgnorePointer(
        ignoring: _leaving,
        child: AnimatedBuilder(
          animation: _c,
          child: GestureDetector(
            excludeFromSemantics: true,
            onVerticalDragStart: _dragStart,
            onVerticalDragUpdate: _dragUpdate,
            onVerticalDragEnd: _dragEnd,
            child: SizedBox(key: QSheetScrim.panelKey, child: KeyedSubtree(key: _panel, child: widget.child)),
          ),
          builder: (context, panel) {
            final v = _c.value.clamp(0.0, 1.0);
            // Under reduce-motion, what the finger did not move only fades.
            final fadeOnly = _still && !_dragged;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.blur > 0)
                  ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: widget.blur * v, sigmaY: widget.blur * v), child: const SizedBox.expand())),
                Semantics(
                  key: QSheetScrim.dismissKey,
                  container: true,
                  button: true,
                  label: QSheetScrim.closeLabel(context),
                  onTap: _dismiss,
                  child: GestureDetector(
                    onTap: _dismiss,
                    excludeFromSemantics: true,
                    child: ColoredBox(color: QColors.scrim.withValues(alpha: QColors.scrim.a * v)),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: fadeOnly
                      ? Opacity(opacity: v, child: panel)
                      : FractionalTranslation(translation: Offset(0, 1 - v), child: panel),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Centred text wrapped to even lines, the way CSS's `text-wrap: balance`
/// does: at the narrowest width that keeps the same number of lines, so a
/// centred sentence never ends on one orphaned word ("…Not a medical" /
/// "service."). One line stays one line.
class QBalancedText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// On the [Text] itself, for a finder that reads it.
  final Key? textKey;
  const QBalancedText(this.text, {super.key, this.textKey, required this.style});

  /// The width [text] balances to inside [maxWidth].
  static double balancedWidth(String text, TextStyle style, double maxWidth, TextDirection direction, TextScaler scaler) {
    int lines(double w) => (TextPainter(text: TextSpan(text: text, style: style), textDirection: direction, textScaler: scaler)..layout(maxWidth: w)).computeLineMetrics().length;
    final n = lines(maxWidth);
    if (n < 2) return maxWidth;
    var lo = maxWidth / (n + 1), hi = maxWidth;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      if (lines(mid) > n) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return math.min(maxWidth, hi.ceilToDouble() + 1);
  }

  @override
  Widget build(BuildContext context) => _Balance(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
        direction: Directionality.of(context),
        scaler: MediaQuery.textScalerOf(context),
        child: Text(text, key: textKey, textAlign: TextAlign.center, style: style),
      );
}

/// Lays its text out at the balanced width, centred in the width it is
/// given. A render object rather than a LayoutBuilder so a parent that asks
/// for intrinsic sizes (a sliver filling the remaining space) can: the lines
/// are the same in number at either width, so the height is the text's.
class _Balance extends SingleChildRenderObjectWidget {
  final String text;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  const _Balance({required this.text, required this.style, required this.direction, required this.scaler, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBalance(text, style, direction, scaler);

  @override
  void updateRenderObject(BuildContext context, _RenderBalance r) {
    r
      ..text = text
      ..style = style
      ..direction = direction
      ..scaler = scaler
      ..markNeedsLayout();
  }
}

class _RenderBalance extends RenderShiftedBox {
  String text;
  TextStyle style;
  TextDirection direction;
  TextScaler scaler;
  _RenderBalance(this.text, this.style, this.direction, this.scaler) : super(null);

  @override
  void performLayout() {
    final c = child!;
    final max = constraints.maxWidth;
    final w = max.isFinite ? QBalancedText.balancedWidth(text, style, max, direction, scaler) : max;
    c.layout(constraints.copyWith(minWidth: 0, maxWidth: w), parentUsesSize: true);
    size = constraints.constrain(Size(max.isFinite ? max : c.size.width, c.size.height));
    (c.parentData! as BoxParentData).offset = Offset((size.width - c.size.width) / 2, (size.height - c.size.height) / 2);
  }
}

/// A [Problem] on a screen (O10): what happened, why when it is known, and
/// the next step as a real button, with another way on under it when there
/// is one. The "what" line is always shown whole.
///
/// Its kind has a glyph, so the same words read as what they are at a
/// glance: nothing here yet, something failed on our side, no connection,
/// the phone has not allowed something, or a daily allowance used up (which
/// is not a failure, and is not drawn as one). Centred, like every empty or
/// error state, and meant to sit in the middle of the free space
/// ([QStateArea]), not stuck to the top of it.
class QStateCard extends StatelessWidget {
  final Problem problem;
  const QStateCard({super.key, required this.problem});

  /// Each kind's glyph and tint.
  static ({IconData icon, Color tint}) look(ProblemKind kind) => switch (kind) {
        ProblemKind.empty => (icon: Icons.nightlight_round, tint: QColors.moonbeam),
        ProblemKind.error => (icon: Icons.error_outline_rounded, tint: QColors.red),
        ProblemKind.offline => (icon: Icons.cloud_off_rounded, tint: QColors.skyBlue),
        ProblemKind.permission => (icon: Icons.lock_outline_rounded, tint: QColors.violetSoft),
        ProblemKind.limit => (icon: Icons.hourglass_bottom_rounded, tint: QColors.amberSoft),
      };

  @override
  Widget build(BuildContext context) {
    final p = problem;
    final l = look(p.kind);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [QColors.cardMid, QColors.cardDeep]),
        border: Border.all(color: QColors.borderSoft),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              key: ValueKey('state-glyph-${p.kind.name}'),
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: l.tint.withValues(alpha: 0.12), border: Border.all(color: l.tint.withValues(alpha: 0.35))),
              child: Icon(l.icon, size: 22, color: l.tint),
            ),
          ),
          const SizedBox(height: 14),
          QBalancedText(p.what, style: QText.body(size: 17, height: 24, weight: FontWeight.w600, color: QColors.textHigh)),
          if (p.why != null && p.why!.isNotEmpty) ...[
            const SizedBox(height: 6),
            QBalancedText(p.why!, style: QText.body(size: 14, height: 21, color: QColors.textMuted)),
          ],
          const SizedBox(height: 18),
          QPrimaryButton(label: p.action.label, onTap: p.action.onTap, height: 48),
          if (p.secondary != null) ...[
            const SizedBox(height: 8),
            QOutlineButton(label: p.secondary!.label, onTap: p.secondary!.onTap, height: 48, color: QColors.textMid),
          ],
          if (p.also != null) ...[
            const SizedBox(height: 8),
            QOutlineButton(label: p.also!.label, onTap: p.also!.onTap, height: 48, color: QColors.textMid),
          ],
        ],
      ),
    );
  }
}

/// The free space a state card sits in (O10): it takes the height it is
/// given and puts the card at its optical centre — a little above the middle,
/// where the eye expects the middle to be.
class QStateArea extends StatelessWidget {
  final Widget child;
  const QStateArea({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(alignment: const Alignment(0, -0.18), child: child);
}

/// A [Problem]'s compact form, for where something was asked that another
/// screen shows in full (O10): one line, and its way on as a text button
/// with a 48pt target. Never a second card: it sits in the place of the
/// thing that asked.
class QStateLine extends StatelessWidget {
  final String line;
  final ProblemAction? action;
  final Color accent;
  final IconData icon;
  const QStateLine({super.key, required this.line, this.action, this.accent = QColors.violet, this.icon = Icons.info_outline});

  @override
  Widget build(BuildContext context) {
    final a = action;
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(14, 12, 14, a == null ? 12 : 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
        borderRadius: BorderRadius.circular(QRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 3), child: Icon(icon, size: 14, color: accent)),
            const SizedBox(width: 8),
            Expanded(child: Text(line, style: QText.body(size: 14, height: 21, weight: FontWeight.w600, color: QColors.textHigh))),
          ]),
          if (a != null)
            Padding(
              // The button's own inset lines its words up under the line's.
              padding: const EdgeInsetsDirectional.only(start: 10),
              child: TextButton(
                onPressed: a.onTap,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: accent,
                ),
                child: Text(a.label, style: QText.body(size: 13, weight: FontWeight.w600, color: accent)),
              ),
            ),
        ],
      ),
    );
  }
}

class QOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  /// The outline's drawn height. The touch takes at least [QLayout.minTap]
  /// whatever this is (O11).
  final double height;
  final Color color;
  const QOutlineButton({super.key, required this.label, required this.onTap, this.height = 44, this.color = QColors.textMuted});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      onTap: onTap,
      minWidth: 64,
      builder: (context, pressed) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 64),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: pressed ? QColors.moonlight.withValues(alpha: 0.06) : Colors.transparent,
            border: Border.all(color: enabled ? QColors.borderSoft : QDisabled.edge),
            borderRadius: BorderRadius.circular(QRadii.control),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label,
                textAlign: TextAlign.center,
                style: QText.body(size: 14, weight: FontWeight.w500, color: enabled ? color : QDisabled.label)),
          ),
        ),
      ),
    );
  }
}

class QPillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const QPillChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return QTapArea(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? QColors.violet.withValues(alpha: 0.18)
              : pressed
                  ? QColors.cardMid
                  : QColors.cardDeep,
          border: Border.all(color: selected ? QColors.violet : QColors.borderSoft),
          borderRadius: BorderRadius.circular(QRadii.pill),
        ),
        child: Text(label, style: QText.body(size: 14, weight: FontWeight.w500, color: selected ? QColors.textPrimary : QColors.textMid)),
      ),
    );
  }
}

class SuCoinIcon extends StatelessWidget {
  final double size;
  const SuCoinIcon({super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset('assets/images/su_coin.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final bool high;
  final String label;
  const ConfidenceBadge({super.key, required this.high, required this.label});
  @override
  Widget build(BuildContext context) {
    final color = high ? QColors.green : QColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.pill)),
      child: Text(label, style: QText.body(size: 11, weight: FontWeight.w500, color: color)),
    );
  }
}

/// The one back control (the exit rule): every screen but the welcome
/// screen and Today has it, in the same place — the top start corner — with
/// the same arrow, which mirrors in Arabic. It returns to the screen the
/// person came from. Drawn at 36 points, it takes touches across the full
/// 48.
class QBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isAr;
  const QBackButton({super.key, required this.onTap, required this.isAr});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isAr ? 'رجوع' : 'Back',
      excludeSemantics: true,
      child: Tooltip(
        message: isAr ? 'رجوع' : 'Back',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.borderSoft)),
                  // arrow_back follows the text direction: it points right in Arabic.
                  child: const Icon(Icons.arrow_back, size: 18, color: QColors.textMid),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QRoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  /// The circle's drawn size; the touch takes at least [QLayout.minTap].
  final double size;

  /// What it does, for a screen reader: the icon has no words.
  final String label;
  const QRoundIconButton({super.key, required this.icon, required this.onTap, required this.label, this.size = 34});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      onTap: onTap,
      label: label,
      builder: (context, pressed) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressed ? QColors.cardMid : Colors.transparent,
          border: Border.all(color: enabled ? QColors.borderSoft : QDisabled.edge),
        ),
        child: Icon(icon, size: size * 0.5, color: enabled ? QColors.textMid : QDisabled.label),
      ),
    );
  }
}

/// An iOS-style value wheel: scroll to choose, with a selection tick on every
/// notch. Replaces the old +/- stepper, which needed one tap per unit — 30 of
/// them to move a birth year.
///
/// Values are supplied as a range so the wheel can be as long as it needs to
/// be; [format] renders each one (month names, for instance).
class QWheelField extends StatefulWidget {
  final String unit;
  final int value;
  final int min;
  final int max;

  /// Wrap past the ends — right for months and days, wrong for a birth year.
  final bool loop;
  final String Function(int)? format;
  final ValueChanged<int> onChanged;

  const QWheelField({
    super.key,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.loop = false,
    this.format,
  });

  @override
  State<QWheelField> createState() => _QWheelFieldState();
}

class _QWheelFieldState extends State<QWheelField> {
  late FixedExtentScrollController _ctrl;

  /// True while we are moving the wheel ourselves. Without this the sequence
  /// scroll -> onChanged -> parent notifies -> didUpdateWidget -> jumpToItem
  /// -> onSelectedItemChanged -> onChanged loops forever, and a wheel stuck in
  /// that loop starves the gesture arena: every button on the screen stops
  /// responding, including the one that submits the step.
  bool _syncing = false;

  int get _count => widget.max - widget.min + 1;
  int get _index => (widget.value - widget.min).clamp(0, _count - 1);

  @override
  void initState() {
    super.initState();
    _ctrl = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void didUpdateWidget(covariant QWheelField old) {
    super.didUpdateWidget(old);
    if (!_ctrl.hasClients) return;

    // Only correct the wheel when it genuinely disagrees with the value —
    // e.g. the day was clamped because the month changed under it. Never while
    // the user is still moving it, and never during this build.
    final needsSync = _ctrl.selectedItem != _index;
    final rangeChanged = widget.min != old.min || widget.max != old.max;
    if (!needsSync && !rangeChanged) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      if (_ctrl.position.isScrollingNotifier.value) return; // still flinging
      if (_ctrl.selectedItem == _index) return;
      _syncing = true;
      _ctrl.jumpToItem(_index);
      // Cleared a frame later: jumpToItem's notification arrives after this.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      for (var v = widget.min; v <= widget.max; v++)
        Center(
          child: Text(
            widget.format?.call(v) ?? '$v',
            maxLines: 1,
            style: QText.number(size: 20, weight: FontWeight.w600),
          ),
        ),
    ];

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // One radius across the answer stack: the wheels and Continue (O7).
        decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.control),
        child: Column(
          children: [
            Text(widget.unit, style: QText.body(size: 12, color: QColors.textMuted)),
            const SizedBox(height: 2),
            SizedBox(
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The selection band, so it is obvious what the wheel is on.
                  IgnorePointer(
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: QColors.violet.withValues(alpha: 0.12),
                        border: Border.symmetric(
                          horizontal: BorderSide(color: QColors.violet.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    controller: _ctrl,
                    itemExtent: 32,
                    diameterRatio: 1.5,
                    perspective: 0.004,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) {
                      if (_syncing) return;
                      final next = widget.min + (i % _count);
                      if (next == widget.value) return;
                      HapticFeedback.selectionClick();
                      widget.onChanged(next);
                    },
                    childDelegate: widget.loop
                        ? ListWheelChildLoopingListDelegate(children: children)
                        : ListWheelChildListDelegate(children: children),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact AR/EN switch.
///
/// The only language control used to be a row at the bottom of the You screen,
/// which is unreachable until onboarding is finished — so someone who does not
/// read Arabic had to complete an Arabic conversation before they could switch
/// out of it. This goes wherever that matters: the welcome screen, the
/// onboarding header, the scan header.
class QLangToggle extends StatelessWidget {
  final AppLang lang;
  final ValueChanged<AppLang> onChanged;

  /// Slightly larger, for screens with room for it.
  final bool large;

  const QLangToggle({super.key, required this.lang, required this.onChanged, this.large = false});

  @override
  Widget build(BuildContext context) {
    final h = large ? 34.0 : 28.0;
    // Drawn [h] tall; each side takes a whole touch (O11), so the switch
    // sits in a band [QLayout.minTap] tall and the pill is drawn behind.
    return SizedBox(
      height: QLayout.minTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: h,
                decoration: BoxDecoration(
                  color: QColors.cardDeep.withValues(alpha: 0.9),
                  border: Border.all(color: QColors.borderSoft),
                  borderRadius: BorderRadius.circular(QRadii.pill),
                ),
              ),
            ),
          ),
          // Fixed left-to-right so the two options never swap places when the
          // direction flips — a control that moves as you use it is disorienting.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Segment(label: 'ع', spoken: 'العربية', selected: lang == AppLang.ar, height: h - 6, large: large, onTap: () => onChanged(AppLang.ar)),
                  _Segment(label: 'EN', spoken: 'English', selected: lang == AppLang.en, height: h - 6, large: large, onTap: () => onChanged(AppLang.en)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final String spoken;
  final bool selected;
  final bool large;
  final double height;
  final VoidCallback onTap;
  const _Segment({required this.label, required this.spoken, required this.selected, required this.large, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return QTapArea(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      label: spoken,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: height,
        constraints: const BoxConstraints(minWidth: QLayout.minTap),
        padding: EdgeInsets.symmetric(horizontal: large ? 14 : 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? QColors.brandGradient : null,
          borderRadius: BorderRadius.circular(QRadii.pill),
        ),
        child: ExcludeSemantics(
          child: Text(
            label,
            style: QText.body(
              size: large ? 13 : 12,
              weight: FontWeight.w600,
              color: selected ? QColors.onAccent : QColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a message list pinned to the newest message.
///
/// Both of the app's conversations are drawn from the bottom up
/// (`ListView(reverse: true)`, newest first: O7, O10), so the newest message
/// is always at offset 0, however tall the content above it grows. Pinning
/// is one step: back to 0 when something new arrives, unless the person has
/// scrolled up to read back. The top-down list needed a second pass for
/// content that finished laying out late; this one does not.
class ChatScroller {
  final ScrollController controller = ScrollController();
  int _signature = -1;

  /// Distance from the newest message within which we still consider the
  /// user "at the bottom" and safe to auto-scroll.
  static const _stickyWindow = 160.0;

  /// Call from build with a value that changes whenever the content does.
  void sync(int signature) {
    if (signature == _signature) return;
    _signature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }

  void _go() {
    if (!controller.hasClients) return;
    final pos = controller.position;
    // Never yank the view away from someone reading earlier messages.
    if (pos.pixels > _stickyWindow || pos.pixels == 0) return;
    controller.animateTo(0, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  void dispose() => controller.dispose();
}

/// Holds the height its child last had while the child is empty (O7): a
/// dock whose inputs go away between one question and the next keeps its
/// place, so the conversation above it does not drop and come back. When the
/// next inputs arrive it grows or shrinks to them once, smoothly.
class QKeepHeight extends StatefulWidget {
  /// Null while there is nothing to show; the last height is held.
  final Widget? child;
  const QKeepHeight({super.key, required this.child});

  @override
  State<QKeepHeight> createState() => _QKeepHeightState();
}

class _QKeepHeightState extends State<QKeepHeight> {
  double _held = 0;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSize(
      duration: still ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: child == null
          ? SizedBox(height: _held)
          : _ReportHeight(onHeight: (h) => _held = h, child: child),
    );
  }
}

class _ReportHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;
  const _ReportHeight({required this.onHeight, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderReportHeight renderObject) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);
  ValueChanged<double> onHeight;

  @override
  void performLayout() {
    super.performLayout();
    onHeight(size.height);
  }
}

/// A text link to one of the public pages on dr-qamar.com.
///
/// The stores require reachable privacy and support pages, and a subscription
/// has to link to the terms it is sold under — so these must actually open,
/// not sit there as decoration.
class QLegalLink extends StatelessWidget {
  final String label;
  final String url;
  final double size;
  const QLegalLink({super.key, required this.label, required this.url, this.size = 11});

  @override
  Widget build(BuildContext context) {
    // Small words, a whole touch (O11): the link takes [QLayout.minTap] each
    // way however short its label.
    return QTapArea(
      link: true,
      onTap: () async {
        final uri = Uri.parse(url);
        // externalApplication: legal pages belong in the browser, where the
        // user can see the address they are being shown.
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          await launchUrl(uri);
        }
      },
      builder: (context, pressed) => Text(
        label,
        style: QText.body(
          size: size,
          weight: FontWeight.w500,
          color: pressed ? QColors.textMid : QColors.textMuted,
        ).copyWith(decoration: TextDecoration.underline, decorationColor: QColors.textMuted),
      ),
    );
  }
}
