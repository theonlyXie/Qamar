import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/su_economy.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'explain.dart';
import 'hold_coach_mark.dart';
import 'living_orb.dart';

/// The persistent floating orb — the whole navigation. Three gestures, none
/// of them a swipe:
///
///  * **tap** — on Today the action tree blooms; anywhere else it goes home
///    to Today. The orb is the one fixed point, so "tap the orb" always gets
///    home (a screen's own back arrow goes to where the person came from),
///  * **hold** (350 ms) — the conversation opens and the moon is already
///    listening. The one gesture people have to learn; everything else is tap,
///  * **drag** — moves the orb, and dropping it on a value explains it.
class OrbNav extends StatefulWidget {
  const OrbNav({super.key});

  /// The orb's own box — the moon and whatever rides under it — for tests
  /// and for anything placed from the orb's rect.
  static const orbKey = ValueKey('orb');

  /// The moon's drawn size.
  static const double moon = 56;

  /// How far the nav orb's sparks and drift reach, against the orb's own
  /// ([LivingOrb.reach]): enough that the outermost spark, at the top of the
  /// drift, stays inside the band (O9).
  static const double bandReach = 0.6;

  /// How far the start and end stops sit from the screen's edges: the page's
  /// own margin, so the orb lines up with what is above it.
  static const double gutter = 20;

  /// The start edge of the orb at [stop], from the screen's start edge.
  static double stopStart(OrbStop stop, double width) => switch (stop) {
        OrbStop.start => gutter,
        OrbStop.centre => (width - moon) / 2,
        OrbStop.end => width - gutter - moon,
      };

  /// The orb's top at rest: centred in the band at the bottom of [height].
  static double restTop(double height) => height - QLayout.orbBand + (QLayout.orbBand - moon) / 2;

  /// The stop nearest to where a release at [start] (start-relative)
  /// moving at [velocity] would come to rest.
  static OrbStop nearestStop(double start, double velocity, double width) {
    final projected = start + QSpring.project(velocity);
    return OrbStop.values.reduce((a, b) => (stopStart(a, width) - projected).abs() <= (stopStart(b, width) - projected).abs() ? a : b);
  }

  @override
  State<OrbNav> createState() => _OrbNavState();
}

class _OrbNavState extends State<OrbNav> with TickerProviderStateMixin {
  // The orb's place while it springs home, start-relative, in points. Two
  // springs, one per axis: a throw sideways and a drop downwards settle on
  // their own clocks without dragging each other off line.
  late final AnimationController _x = AnimationController.unbounded(vsync: this);
  late final AnimationController _y = AnimationController.unbounded(vsync: this);

  // With reduced motion there is no spring: the orb fades in at its stop.
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);

  bool get _springing => _x.isAnimating || _y.isAnimating;

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _fade.dispose();
    super.dispose();
  }

  /// A finger takes the orb: from where it is on screen, even mid-spring,
  /// so grabbing it never makes it jump.
  void _grab(AppState state, Size size, double maxX, double maxY) {
    if (_springing) {
      final x = _x.value, y = _y.value;
      _x.stop();
      _y.stop();
      state.setOrbPosition(x, y, maxX: maxX, maxY: maxY);
    } else if (!state.orbHeld) {
      state.setOrbPosition(OrbNav.stopStart(state.orbStop, size.width), OrbNav.restTop(size.height), maxX: maxX, maxY: maxY);
    }
  }

  /// The finger lets go at [velocity] (points a second, on screen). The orb
  /// rests at the stop nearest where the throw would carry it, or, after
  /// explaining a value, back at the stop it came from; the spring starts
  /// where the finger left it and at the finger's speed.
  void _release(AppState state, Size size, bool rtl, Offset velocity, {required bool returnHome}) {
    final fromX = state.orbStart, fromY = state.orbY;
    final along = rtl ? -velocity.dx : velocity.dx;
    final stop = returnHome ? state.orbStop : OrbNav.nearestStop(fromX, along, size.width);
    state.settleOrb(stop);
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.forward(from: 0);
      return;
    }
    final spring = velocity.distance > QSpring.flickSpeed && !returnHome ? QSpring.flick : QSpring.settle;
    _x.value = fromX;
    _y.value = fromY;
    _x.animateWith(SpringSimulation(spring, fromX, OrbNav.stopStart(stop, size.width), along));
    _y.animateWith(SpringSimulation(spring, fromY, OrbNav.restTop(size.height), velocity.dy));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final state = context.watch<AppState>();
          final size = constraints.biggest;
          final maxX = math.max(4.0, size.width - OrbNav.moon - 4);
          final maxY = math.max(46.0, size.height - OrbNav.moon - 4);
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return AnimatedBuilder(
            animation: Listenable.merge([_x, _y, _fade]),
            builder: (context, _) {
              final double start, top;
              if (state.orbHeld) {
                start = state.orbStart.clamp(4.0, maxX);
                top = state.orbY.clamp(46.0, maxY);
              } else if (_springing) {
                start = _x.value;
                top = _y.value;
              } else {
                start = OrbNav.stopStart(state.orbStop, size.width);
                top = OrbNav.restTop(size.height);
              }
              // The hold's one-time mark rides with the orb: above it, or below
              // it while the orb is held in the top half of the screen.
              final markBelow = top < size.height / 2;
              return CustomMultiChildLayout(
                delegate: _OrbLayout(start: start, top: top, rtl: rtl, markBelow: markBelow),
                children: [
                  // A credit's passing receipt (O9), beside the orb in its band.
                  // Its own child, so the orb's box is the moon alone.
                  if (state.showScore && state.suReceipt != null)
                    LayoutId(id: _OrbPart.receipt, child: SuReceiptChip(receipt: state.suReceipt!)),
                  if (state.holdCoachDue) ...[
                    LayoutId(id: _OrbPart.mark, child: HoldCoachMark(state: state)),
                    LayoutId(id: _OrbPart.caret, child: HoldCoachMark.caret(up: markBelow)),
                  ],
                  LayoutId(
                    id: _OrbPart.orb,
                    child: FadeTransition(
                      opacity: _fade,
                      child: _DraggableOrb(
                        key: OrbNav.orbKey,
                        maxX: maxX,
                        maxY: maxY,
                        onGrab: () => _grab(state, size, maxX, maxY),
                        onRelease: (v, returnHome) => _release(state, size, rtl, v, returnHome: returnHome),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

enum _OrbPart { orb, receipt, mark, caret }

/// The orb at the position given (the one place it is placed), the receipt
/// beside it, and, while it is due, the hold's mark placed from the orb's own
/// rect: centred on the moon, kept 8 points inside the screen, its caret on
/// the moon.
///
/// The position is start-relative: [start] is the gap from the start edge to
/// the orb's start side, so in Arabic it is measured from the right and the
/// whole layout mirrors (O1).
class _OrbLayout extends MultiChildLayoutDelegate {
  final double start;
  final double top;
  final bool rtl;
  final bool markBelow;
  _OrbLayout({required this.start, required this.top, required this.rtl, required this.markBelow});

  @override
  void performLayout(Size size) {
    final orb = layoutChild(_OrbPart.orb, const BoxConstraints());
    final orbAt = Offset(rtl ? size.width - orb.width - start : start, top);
    positionChild(_OrbPart.orb, orbAt);
    if (hasChild(_OrbPart.receipt)) {
      // Beside the moon, on its level, on the side facing the middle of the
      // screen — in the band, not over the page (O9). At the centre stop, on
      // the end side.
      final r = layoutChild(_OrbPart.receipt, BoxConstraints.loose(size));
      final moonX = orbAt.dx + orb.width / 2;
      final towardRight = (moonX - size.width / 2).abs() < 1 ? !rtl : moonX < size.width / 2;
      final left = towardRight ? orbAt.dx + orb.width + 6 : orbAt.dx - r.width - 6;
      positionChild(_OrbPart.receipt, Offset(left.clamp(4.0, size.width - r.width - 4), orbAt.dy + (orb.height - r.height) / 2));
    }
    if (!hasChild(_OrbPart.mark)) return;
    final mark = layoutChild(_OrbPart.mark, BoxConstraints.loose(size));
    final caret = layoutChild(_OrbPart.caret, BoxConstraints.loose(size));
    // The orb's box is the moon.
    final moonX = orbAt.dx + orb.width / 2;
    final maxLeft = size.width - mark.width - 8;
    final left = (moonX - mark.width / 2).clamp(8.0, maxLeft < 8 ? 8.0 : maxLeft);
    final caretTop = markBelow ? orbAt.dy + orb.height + 4 : orbAt.dy - 4 - caret.height;
    // The caret reaches a point into the bubble, so the two read as one.
    final markTop = markBelow ? caretTop + caret.height - 1 : caretTop - mark.height + 1;
    positionChild(_OrbPart.mark, Offset(left, markTop));
    positionChild(_OrbPart.caret, Offset(moonX - caret.width / 2, caretTop));
  }

  @override
  bool shouldRelayout(_OrbLayout old) =>
      old.start != start || old.top != top || old.rtl != rtl || old.markBelow != markBelow;
}

class _DraggableOrb extends StatefulWidget {
  final double maxX;
  final double maxY;
  final VoidCallback onGrab;
  final void Function(Offset velocity, bool returnHome) onRelease;
  const _DraggableOrb({super.key, required this.maxX, required this.maxY, required this.onGrab, required this.onRelease});

  @override
  State<_DraggableOrb> createState() => _DraggableOrbState();
}

class _DraggableOrbState extends State<_DraggableOrb> {
  double _dragDistance = 0;
  final GlobalKey _moonKey = GlobalKey();

  /// Blueprint: hold recognises at 350 ms. Flutter's default is 500, which is
  /// long enough to feel like the app did not hear you.
  static const _holdAfter = Duration(milliseconds: 350);

  /// Centre of the moon in global coordinates — the point the orb "reads"
  /// with, rather than wherever the finger happens to be.
  Offset? get _moonCentre {
    final box = _moonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _dragUpdate(AppState state, DragUpdateDetails d) {
    _dragDistance += d.delta.distance;
    // The finger moves in screen space; the orb is kept from the start edge,
    // which in Arabic is the right, so a move to the right brings it closer.
    // Anywhere on the screen while held: explain reads the moon's centre
    // mid-drag (O1).
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final along = rtl ? -d.delta.dx : d.delta.dx;
    state.setOrbPosition(state.orbStart + along, state.orbY + d.delta.dy, maxX: widget.maxX, maxY: widget.maxY);
    final centre = _moonCentre;
    final hit = centre == null ? null : ExplainRegistry.instance.hitTest(centre);
    if (hit != state.explainHoverId && hit != null) HapticFeedback.selectionClick();
    state.setExplainHover(hit);
  }

  void _dragEnd(AppState state, Offset velocity) {
    final hovering = state.explainHoverId;
    final explained = hovering != null && _dragDistance >= 6;
    state.setExplainHover(null);
    // Letting go puts the orb back in its band: after explaining a value, at
    // the stop it came from (the drag was to explain, not to move it);
    // otherwise at the stop the throw carries it to.
    widget.onRelease(explained ? Offset.zero : velocity, explained);
    if (explained) {
      final ex = ExplainRegistry.instance.explanationFor(hovering);
      if (ex != null) {
        HapticFeedback.mediumImpact();
        state.openExplain(ex);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // One arena, three recognisers. A pan that moves past the touch slop wins
    // over the hold; a finger that rests wins the hold at 350 ms; a lift
    // before either is a tap. Same rules as before, one duration changed.
    // The moon has no words of its own: a screen reader hears its name and
    // what its two gestures do from here (O11).
    final t = state.t;
    final tapDoes = state.screen == AppScreen.today
        ? (state.isAr ? 'اضغط تفتح الشجرة' : 'Tap to open the tree')
        : (state.isAr ? 'اضغط ترجع لـ${t.today}' : 'Tap to go back to ${t.today}');
    return Semantics(
      container: true,
      button: true,
      label: t.brand,
      hint: state.isAr ? '$tapDoes، واستمر ضاغط تتكلم مع قمر' : '$tapDoes; hold to talk to Qamar',
      child: RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
          () => TapGestureRecognizer(),
          (r) => r.onTap = () {
            HapticFeedback.selectionClick();
            state.orbTap();
          },
        ),
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: _holdAfter),
          (r) => r.onLongPressStart = (_) {
            // Haptic on the threshold, on the same frame the orb warms.
            HapticFeedback.mediumImpact();
            state.holdOrb();
          },
        ),
        PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
          () => PanGestureRecognizer(),
          (r) {
            r.onStart = (_) {
              _dragDistance = 0;
              widget.onGrab();
            };
            r.onUpdate = (d) => _dragUpdate(state, d);
            r.onEnd = (d) => _dragEnd(state, d.velocity.pixelsPerSecond);
            r.onCancel = () => _dragEnd(state, Offset.zero);
          },
        ),
      },
      // The moon alone. It used to carry the balance in a 10pt pill under it
      // ("٠ نقطة Su"); the balance lives in Today's header chip now, and the
      // orb shows only a passing receipt when something is earned.
      child: SizedBox(
        key: _moonKey,
        width: 56,
        height: 56,
        // Its sparks and drift kept inside the band (O9).
        child: Center(child: LivingOrb(size: 56, wander: true, sparks: true, reach: OrbNav.bandReach, state: state.orbState(), speaking: state.orbSpeaking)),
      ),
    ),
    );
  }
}

/// The fade at the bottom of an orb screen, where content that is still
/// scrolling meets the orb's band (O1): a scroll-edge fade in place of a hard
/// divider, starting [reachAbove] points above the band. It draws and takes
/// no touches.
class OrbBandFade extends StatelessWidget {
  const OrbBandFade({super.key});

  /// How far above the band the fade begins: the gap [QLayout.pageBottom]
  /// leaves under a page's last line, so a page at rest is never faded.
  static const double reachAbove = QLayout.pageBottom - QLayout.orbBand;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // From clear, where the page's last line comes to rest, to near
            // solid across the band itself, so the orb always sits on a calm
            // ground and what scrolls under it reads as behind.
            colors: [for (final a in const [0.0, 0.72, 0.92, 0.97]) QColors.bgBottom.withValues(alpha: a)],
            stops: const [0.0, 0.3, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A credit, said without words: a coin and the signed amount ("+١٠٠"),
/// for about two seconds, then gone (O9). No bounce, no sound, no haptic —
/// it is a receipt, not a reward. It never shows a balance or a zero, and it
/// takes no touches: whatever is under it stays tappable.
class SuReceiptChip extends StatefulWidget {
  final SuReceipt receipt;
  const SuReceiptChip({super.key, required this.receipt});

  /// How the receipt moves over its two seconds, [t] from 0 to 1 (O9): it
  /// rises the last few points into place as it fades in — an ease-out, so it
  /// arrives and stops, never overshoots — holds, and fades out with an
  /// ease-in. [rise] is how far below its place it is drawn. With reduced
  /// motion it does not move: it appears and, at the end, goes.
  static ({double opacity, double rise}) motionAt(double t, {required bool still}) {
    if (still) return (opacity: 1.0, rise: 0.0);
    const inEnd = 0.12, outStart = 0.85, travel = 5.0;
    if (t < inEnd) {
      final e = Curves.easeOutCubic.transform(t / inEnd);
      return (opacity: e, rise: travel * (1 - e));
    }
    if (t > outStart) {
      final e = Curves.easeInCubic.transform((t - outStart) / (1 - outStart));
      return (opacity: 1 - e, rise: 0.0);
    }
    return (opacity: 1.0, rise: 0.0);
  }

  @override
  State<SuReceiptChip> createState() => _SuReceiptChipState();
}

class _SuReceiptChipState extends State<SuReceiptChip> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: SuReceipt.showFor);

  @override
  void initState() {
    super.initState();
    // The orb is rebuilt when a screen changes; a receipt already shown for
    // its two seconds is not shown again, and one half-way through carries on.
    final elapsed = context.read<AppState>().clockNow().difference(widget.receipt.at);
    final done = elapsed.inMicroseconds / SuReceipt.showFor.inMicroseconds;
    if (done >= 1) {
      _c.value = 1;
    } else {
      _c.forward(from: done.clamp(0.0, 1.0));
    }
  }

  @override
  void didUpdateWidget(covariant SuReceiptChip old) {
    super.didUpdateWidget(old);
    // Another credit while one is showing starts the two seconds again.
    if (old.receipt.seq != widget.receipt.seq) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final still = MediaQuery.disableAnimationsOf(context);
    final amount = widget.receipt.amount;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = _c.value;
          if (_c.isCompleted) return const SizedBox.shrink();
          final m = SuReceiptChip.motionAt(v, still: still);
          return Transform.translate(offset: Offset(0, m.rise), child: Opacity(opacity: m.opacity, child: child));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: QColors.glass,
            border: Border.all(color: QColors.gold.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SuCoinIcon(size: 14),
            const SizedBox(width: 5),
            Text(
              state.isAr ? state.iso('+${state.formatSu(amount)}') : '+${state.formatSu(amount)}',
              style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.gold),
            ),
          ]),
        ),
      ),
    );
  }
}
