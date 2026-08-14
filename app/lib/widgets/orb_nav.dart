import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'explain.dart';
import 'living_orb.dart';

/// The persistent floating orb — drag it anywhere, tap to open the radial
/// tree. Present on every in-app screen (Today/Log/Plan/Progress/You/Wallet).
class OrbNav extends StatelessWidget {
  const OrbNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final state = context.watch<AppState>();
          final maxX = constraints.maxWidth - 96;
          final maxY = constraints.maxHeight - 118;
          return Stack(
            children: [
              Positioned(
                left: state.orbX.clamp(4, maxX < 4 ? 4 : maxX).toDouble(),
                top: state.orbY.clamp(46, maxY < 46 ? 46 : maxY).toDouble(),
                child: _DraggableOrb(maxX: maxX < 4 ? 4 : maxX, maxY: maxY < 46 ? 46 : maxY),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DraggableOrb extends StatefulWidget {
  final double maxX;
  final double maxY;
  const _DraggableOrb({required this.maxX, required this.maxY});

  @override
  State<_DraggableOrb> createState() => _DraggableOrbState();
}

class _DraggableOrbState extends State<_DraggableOrb> {
  double _dragDistance = 0;
  final GlobalKey _moonKey = GlobalKey();

  /// Centre of the moon in global coordinates — the point the orb "reads"
  /// with, rather than wherever the finger happens to be.
  Offset? get _moonCentre {
    final box = _moonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _dragDistance = 0,
      onPanUpdate: (d) {
        _dragDistance += d.delta.distance;
        state.setOrbPosition(state.orbX + d.delta.dx, state.orbY + d.delta.dy, maxX: widget.maxX, maxY: widget.maxY);
        final centre = _moonCentre;
        state.setExplainHover(centre == null ? null : ExplainRegistry.instance.hitTest(centre));
      },
      onPanEnd: (_) {
        final hovering = state.explainHoverId;
        // A drop onto a value explains it; a tap with no drag opens the tree.
        if (hovering != null && _dragDistance >= 6) {
          state.openExplain(hovering);
        } else if (_dragDistance < 6) {
          state.setExplainHover(null);
          state.toggleTree();
        } else {
          state.setExplainHover(null);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(key: _moonKey, width: 56, height: 56, child: const Center(child: LivingOrb(size: 56, wander: true, sparks: true))),
          Transform.translate(
            offset: const Offset(0, -4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xD9111827), border: Border.all(color: QColors.borderSoft), borderRadius: BorderRadius.circular(999)),
              child: Text(
                state.isAr ? '${state.iso('${state.suAvailable}')} نقطة Su' : '${state.suAvailable} Su',
                style: QText.number(size: 10, weight: FontWeight.w600, color: QColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
