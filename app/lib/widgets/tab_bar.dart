import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/su_economy.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'explain.dart';
import 'hold_coach_mark.dart';
import 'living_orb.dart';
import 'surface.dart';

/// One of the tab bar's pages: where it goes, its glyph, its name.
class QTab {
  final AppScreen screen;
  final IconData icon;
  final String Function(AppState state) label;
  const QTab(this.screen, this.icon, this.label);
}

/// The tab bar's pages, either side of the orb: Today and Progress, then
/// Plan and Me ([AppState.tabScreens]). Each is named by the title of the
/// page it opens.
final kTabs = <QTab>[
  QTab(AppScreen.today, QIcons.today, (s) => s.t.today),
  QTab(AppScreen.progress, QIcons.review, (s) => s.t.progress),
  QTab(AppScreen.plan, QIcons.plan, (s) => s.t.plan),
  QTab(AppScreen.you, QIcons.me, (s) => s.t.you),
];

/// The floating tab bar (the qamar-design skill; the Nutri AI kit's): a pill
/// of the control grey holding five circles, the four pages and, in the
/// middle, the orb. The page the person is on is the burgundy circle, its
/// glyph bold; the orb's circle is the night, with the moon in it.
///
/// The orb keeps its three gestures, none of them a swipe:
///
///  * **tap** — the Log sheet rises: every way to log, one tap each;
///  * **hold** (350 ms) — the conversation opens and the moon is already
///    listening. The one gesture people have to learn;
///  * **drag** — the moon leaves the bar under the finger, and dropped on a
///    number (one drawn with the dotted mark) has it explained; let go, it
///    springs back into the bar.
class QTabBar extends StatefulWidget {
  const QTabBar({super.key});

  /// The orb's own box, for tests and for anything placed from the orb.
  static const orbKey = ValueKey('orb');

  /// The pill, for tests.
  static const barKey = ValueKey('tab-bar');

  /// Each tab's circle, for tests.
  static Key tabKey(AppScreen s) => ValueKey('tab-${s.name}');

  /// The circles' size, the gap between them and the pill's inset.
  static const double circle = 54;
  static const double gap = 8;
  static const double inset = (QLayout.tabBar - circle) / 2;

  /// The pill's width: five circles, four gaps and the inset either side.
  static const double width = inset * 2 + circle * 5 + gap * 4;

  /// The moon's drawn size in the orb's circle, and under the finger.
  static const double moon = 38;

  /// Where the orb's circle sits at rest, in a box of [size]: the middle of
  /// the bar. Start-relative, so the same in either direction.
  static double restStart(Size size) => (size.width - circle) / 2;
  static double restTop(Size size) => size.height - QLayout.tabBarGap - QLayout.tabBar + inset;

  @override
  State<QTabBar> createState() => _QTabBarState();
}

class _QTabBarState extends State<QTabBar> with TickerProviderStateMixin {
  // The orb's place while it springs back into the bar, start-relative, in
  // points. Two springs, one per axis, so a sideways throw and a drop settle
  // on their own clocks.
  late final AnimationController _x = AnimationController.unbounded(vsync: this);
  late final AnimationController _y = AnimationController.unbounded(vsync: this);

  // With reduced motion there is no spring: the moon fades back in its circle.
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
  /// so grabbing it never makes it jump. Taken out to explain a number on
  /// the page, it puts the Log sheet away first.
  void _grab(AppState state, Size size, double maxX, double maxY) {
    if (state.logOpen) state.closeLog();
    if (_springing) {
      final x = _x.value, y = _y.value;
      _x.stop();
      _y.stop();
      state.setOrbPosition(x, y, maxX: maxX, maxY: maxY);
    } else if (!state.orbHeld) {
      state.setOrbPosition(QTabBar.restStart(size), QTabBar.restTop(size), maxX: maxX, maxY: maxY);
    }
  }

  /// The finger lets go at [velocity] (points a second, on screen): the orb
  /// springs back into the bar from where the finger left it, carrying the
  /// finger's speed.
  void _release(AppState state, Size size, bool rtl, Offset velocity) {
    final fromX = state.orbStart, fromY = state.orbY;
    final along = rtl ? -velocity.dx : velocity.dx;
    state.releaseOrb();
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.forward(from: 0);
      return;
    }
    _x.value = fromX;
    _y.value = fromY;
    _x.animateWith(SpringSimulation(QSpring.settle, fromX, QTabBar.restStart(size), along));
    _y.animateWith(SpringSimulation(QSpring.settle, fromY, QTabBar.restTop(size), velocity.dy));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final state = context.watch<AppState>();
          final size = constraints.biggest;
          final maxX = math.max(4.0, size.width - QTabBar.circle - 4);
          final maxY = math.max(46.0, size.height - QTabBar.circle - 4);
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
                start = QTabBar.restStart(size);
                top = QTabBar.restTop(size);
              }
              final away = state.orbHeld || _springing;
              return CustomMultiChildLayout(
                delegate: _TabBarLayout(start: start, top: top, rtl: rtl),
                children: [
                  LayoutId(id: _Part.bar, child: _Bar(state: state, orbAway: away)),
                  // A credit's passing receipt (O9), over the orb's circle.
                  if (state.showScore && state.suReceipt != null)
                    LayoutId(id: _Part.receipt, child: SuReceiptChip(receipt: state.suReceipt!)),
                  if (state.holdCoachDue) ...[
                    LayoutId(id: _Part.mark, child: HoldCoachMark(state: state)),
                    LayoutId(id: _Part.caret, child: HoldCoachMark.caret(up: false)),
                  ],
                  LayoutId(
                    id: _Part.orb,
                    child: FadeTransition(
                      opacity: _fade,
                      child: _Orb(
                        key: QTabBar.orbKey,
                        away: away,
                        maxX: maxX,
                        maxY: maxY,
                        onGrab: () => _grab(state, size, maxX, maxY),
                        onRelease: (v) => _release(state, size, rtl, v),
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

enum _Part { bar, orb, receipt, mark, caret }

/// The bar at the bottom centre; the orb at [start] (start-relative, so in
/// Arabic measured from the right) and [top]; the receipt and the hold's
/// mark over the bar's middle, the mark's caret on the orb.
class _TabBarLayout extends MultiChildLayoutDelegate {
  final double start;
  final double top;
  final bool rtl;
  _TabBarLayout({required this.start, required this.top, required this.rtl});

  @override
  void performLayout(Size size) {
    final bar = layoutChild(_Part.bar, BoxConstraints.tight(const Size(QTabBar.width, QLayout.tabBar)));
    final barAt = Offset((size.width - bar.width) / 2, size.height - QLayout.tabBarGap - bar.height);
    positionChild(_Part.bar, barAt);
    final orb = layoutChild(_Part.orb, BoxConstraints.tight(const Size.square(QTabBar.circle)));
    positionChild(_Part.orb, Offset(rtl ? size.width - orb.width - start : start, top));
    final middle = size.width / 2;
    if (hasChild(_Part.receipt)) {
      final r = layoutChild(_Part.receipt, BoxConstraints.loose(size));
      positionChild(_Part.receipt, Offset(middle - r.width / 2, barAt.dy - 8 - r.height));
    }
    if (!hasChild(_Part.mark)) return;
    final mark = layoutChild(_Part.mark, BoxConstraints.loose(size));
    final caret = layoutChild(_Part.caret, BoxConstraints.loose(size));
    final caretTop = barAt.dy - 4 - caret.height;
    positionChild(_Part.caret, Offset(middle - caret.width / 2, caretTop));
    // The caret reaches a point into the bubble, so the two read as one.
    positionChild(_Part.mark, Offset((middle - mark.width / 2).clamp(8.0, math.max(8.0, size.width - mark.width - 8)), caretTop - mark.height + 1));
  }

  @override
  bool shouldRelayout(_TabBarLayout old) => old.start != start || old.top != top || old.rtl != rtl;
}

/// The pill and its four tabs, with the orb's circle, the night, in the
/// middle (empty while the moon is out under a finger).
class _Bar extends StatelessWidget {
  final AppState state;
  final bool orbAway;
  const _Bar({required this.state, required this.orbAway});

  @override
  Widget build(BuildContext context) {
    Widget tab(QTab t) => _TabCircle(
          key: QTabBar.tabKey(t.screen),
          icon: t.icon,
          label: t.label(state),
          selected: state.screen == t.screen,
          onTap: () {
            // The page on show: its tab only puts the Log sheet away.
            if (state.screen == t.screen) {
              if (state.logOpen) state.closeLog();
              return;
            }
            HapticFeedback.selectionClick();
            state.go(t.screen);
          },
        );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        key: QTabBar.barKey,
        decoration: const ShapeDecoration(color: QColors.surfaceRaised, shape: StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.all(QTabBar.inset),
          child: Row(
            children: [
              tab(kTabs[0]),
              const SizedBox(width: QTabBar.gap),
              tab(kTabs[1]),
              const SizedBox(width: QTabBar.gap),
              // The orb's socket: the moon rests in it (the orb is laid over
              // it by the bar's layout, so it can leave under a finger).
              const SizedBox.square(
                dimension: QTabBar.circle,
                child: DecoratedBox(decoration: BoxDecoration(color: QColors.black, shape: BoxShape.circle)),
              ),
              const SizedBox(width: QTabBar.gap),
              tab(kTabs[2]),
              const SizedBox(width: QTabBar.gap),
              tab(kTabs[3]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tab's circle: the circle grey at rest with a linear glyph; burgundy
/// with the bold glyph when it is the page on show. A screen reader hears
/// its page's name, and which one is chosen.
class _TabCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabCircle({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return QTapArea(
      onTap: onTap,
      label: label,
      // Inside the tap's own node, so the chosen state is the tab's.
      builder: (context, pressed) => Semantics(
        selected: selected,
        child: qPressed(
          context,
          pressed: pressed,
          child: AnimatedContainer(
            duration: still ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: QTabBar.circle,
            height: QTabBar.circle,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? (pressed ? QColors.accentPressed : QColors.accent) : (pressed ? QColors.surface : QColors.surfaceHigh),
            ),
            child: Center(
              child: QIcon(selected ? QIcons.onFor(icon) : icon, size: 24, color: QColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orb: the moon in its circle. Tap, hold, drag (see [QTabBar]).
class _Orb extends StatefulWidget {
  final bool away;
  final double maxX;
  final double maxY;
  final VoidCallback onGrab;
  final void Function(Offset velocity) onRelease;
  const _Orb({super.key, required this.away, required this.maxX, required this.maxY, required this.onGrab, required this.onRelease});

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> {
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
    // Letting go puts the orb back in the bar; after explaining a value it
    // goes straight back (the drag was to explain, not to throw it).
    widget.onRelease(explained ? Offset.zero : velocity);
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
    final isAr = state.isAr;
    // One arena, three recognisers. A pan that moves past the touch slop wins
    // over the hold; a finger that rests wins the hold at 350 ms; a lift
    // before either is a tap. The moon has no words of its own: a screen
    // reader hears its name and what its gestures do (O11).
    return Semantics(
      container: true,
      button: true,
      label: state.t.brand,
      hint: isAr ? 'اضغط تسجّل، واستمر ضاغط تتكلم مع قمر' : 'Tap to log; hold to talk to Qamar',
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
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
        // In the bar the moon's light stays inside its circle; out under a
        // finger it is the moon alone, with its halo.
        child: SizedBox.square(
          dimension: QTabBar.circle,
          child: Center(
            child: widget.away
                ? KeyedSubtree(key: _moonKey, child: _moon(state))
                : ClipOval(child: SizedBox.square(dimension: QTabBar.circle, child: Center(child: KeyedSubtree(key: _moonKey, child: _moon(state))))),
          ),
        ),
      ),
    );
  }

  Widget _moon(AppState state) => SizedBox.square(
        dimension: QTabBar.moon,
        child: Center(child: LivingOrb(size: QTabBar.moon, state: state.orbState(), speaking: state.orbSpeaking)),
      );
}

/// The fade at the bottom of a tab page, where content that is still
/// scrolling meets the floating bar (O1): a scroll-edge fade in place of a
/// hard divider, starting [reachAbove] points above the band. It draws and
/// takes no touches.
class TabBarFade extends StatelessWidget {
  const TabBarFade({super.key});

  /// How far above the band the fade begins: the gap [QLayout.pageBottom]
  /// leaves under a page's last line, so a page at rest is never faded.
  static const double reachAbove = QLayout.pageBottom - QLayout.tabBand;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [for (final a in const [0.0, 0.7, 0.9, 0.96]) QColors.canvas.withValues(alpha: a)],
            stops: const [0.0, 0.35, 0.6, 1.0],
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
    // The bar is rebuilt when a page changes; a receipt already shown for
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
        child: QSurface(
          shape: QSurfaceShape.capsule,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SuCoinIcon(size: 14),
            const SizedBox(width: 5),
            Text(
              state.isAr ? state.iso('+${state.formatSu(amount)}') : '+${state.formatSu(amount)}',
              style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.ink),
            ),
          ]),
        ),
      ),
    );
  }
}
