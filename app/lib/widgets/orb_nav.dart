import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/su_economy.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
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
class OrbNav extends StatelessWidget {
  const OrbNav({super.key});

  /// The orb's own box — the moon and whatever rides under it — for tests
  /// and for anything placed from the orb's rect.
  static const orbKey = ValueKey('orb');

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final state = context.watch<AppState>();
          final maxX = constraints.maxWidth - 96;
          final maxY = constraints.maxHeight - 118;
          final start = state.orbStart.clamp(4, maxX < 4 ? 4 : maxX).toDouble();
          final top = state.orbY.clamp(46, maxY < 46 ? 46 : maxY).toDouble();
          // The hold's one-time mark rides with the orb: above it, or below
          // it while the orb rests in the top half of the screen.
          final markBelow = top < constraints.maxHeight / 2;
          return CustomMultiChildLayout(
            delegate: _OrbLayout(
              start: start,
              top: top,
              rtl: Directionality.of(context) == TextDirection.rtl,
              markBelow: markBelow,
            ),
            children: [
              // A credit's passing receipt (O9). Its own child, so the orb's
              // box is the moon alone and never changes size.
              if (state.showScore && state.suReceipt != null)
                LayoutId(id: _OrbPart.receipt, child: SuReceiptChip(receipt: state.suReceipt!)),
              if (state.holdCoachDue) ...[
                LayoutId(id: _OrbPart.mark, child: HoldCoachMark(state: state)),
                LayoutId(id: _OrbPart.caret, child: HoldCoachMark.caret(up: markBelow)),
              ],
              LayoutId(
                id: _OrbPart.orb,
                child: _DraggableOrb(key: OrbNav.orbKey, maxX: maxX < 4 ? 4 : maxX, maxY: maxY < 46 ? 46 : maxY),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _OrbPart { orb, receipt, mark, caret }

/// The orb at the position state holds (the one place it is placed), and,
/// while it is due, the hold's mark placed from the orb's own rect: centred
/// on the moon, kept 8 points inside the screen, its caret on the moon.
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
      // Centred on the moon, under it, where the old balance pill sat; above
      // it while the hold's mark takes the space below.
      final r = layoutChild(_OrbPart.receipt, BoxConstraints.loose(size));
      final left = (orbAt.dx + orb.width / 2 - r.width / 2).clamp(4.0, size.width - r.width - 4);
      final receiptTop = markBelow && hasChild(_OrbPart.mark) ? orbAt.dy - r.height - 2 : orbAt.dy + orb.height + 2;
      positionChild(_OrbPart.receipt, Offset(left, receiptTop));
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
  const _DraggableOrb({super.key, required this.maxX, required this.maxY});

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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final along = rtl ? -d.delta.dx : d.delta.dx;
    state.setOrbPosition(state.orbStart + along, state.orbY + d.delta.dy, maxX: widget.maxX, maxY: widget.maxY);
    final centre = _moonCentre;
    final hit = centre == null ? null : ExplainRegistry.instance.hitTest(centre);
    if (hit != state.explainHoverId && hit != null) HapticFeedback.selectionClick();
    state.setExplainHover(hit);
  }

  void _dragEnd(AppState state) {
    final hovering = state.explainHoverId;
    if (hovering != null && _dragDistance >= 6) {
      final ex = ExplainRegistry.instance.explanationFor(hovering);
      state.setExplainHover(null);
      if (ex != null) {
        HapticFeedback.mediumImpact();
        state.openExplain(ex);
      }
    } else {
      state.setExplainHover(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    // One arena, three recognisers. A pan that moves past the touch slop wins
    // over the hold; a finger that rests wins the hold at 350 ms; a lift
    // before either is a tap. Same rules as before, one duration changed.
    return RawGestureDetector(
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
            r.onStart = (_) => _dragDistance = 0;
            r.onUpdate = (d) => _dragUpdate(state, d);
            r.onEnd = (_) => _dragEnd(state);
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
        child: Center(child: LivingOrb(size: 56, wander: true, sparks: true, state: state.orbState(), speaking: state.orbSpeaking)),
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
          // A short fade in and out; with reduced motion it simply appears
          // and goes.
          final opacity = still ? 1.0 : (v < 0.08 ? v / 0.08 : v > 0.85 ? (1 - v) / 0.15 : 1.0);
          return Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xE6111827),
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
