import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'explain.dart';
import 'hold_coach_mark.dart';
import 'living_orb.dart';

/// The persistent floating orb — the whole navigation. Three gestures, none
/// of them a swipe:
///
///  * **tap** — on Today the action tree blooms; anywhere else it is Back.
///    The orb is the one fixed point, so "tap the orb" always gets home,
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

enum _OrbPart { orb, mark, caret }

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
    if (!hasChild(_OrbPart.mark)) return;
    final mark = layoutChild(_OrbPart.mark, BoxConstraints.loose(size));
    final caret = layoutChild(_OrbPart.caret, BoxConstraints.loose(size));
    // The moon is centred in the orb's column, the Su pill under it.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: _moonKey,
            width: 56,
            height: 56,
            child: Center(child: LivingOrb(size: 56, wander: true, sparks: true, state: state.orbState(), speaking: state.waitingNudge != null)),
          ),
          Transform.translate(
            offset: const Offset(0, -4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xD9111827),
                border: Border.all(color: QColors.borderSoft),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                state.isAr ? '${state.iso(state.formatSu(state.suAvailable))} نقطة Su' : '${state.formatSu(state.suAvailable)} Su',
                style: QText.number(size: 10, weight: FontWeight.w600, color: QColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
