import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/scan_flow.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'explain.dart';
import 'living_orb.dart';
import 'tree_overlay.dart';

/// The persistent floating orb. Three gestures, deliberately distinct:
///
///  * **tap** — opens the tree the sticky way, so it can still be used one
///    finger at a time,
///  * **hold** — opens the tree and keeps the pointer: sweep to a destination,
///    dwell on Log to fan out its input methods, release to activate. This is
///    the fast path, and the reason the orb exists: getting somewhere or
///    logging a meal without being pushed into another page,
///  * **drag** — moves the orb, and dropping it on a value explains it.
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
  final ImagePicker _picker = ImagePicker();

  /// Fires once the finger has rested on the Log node long enough to mean it.
  Timer? _dwell;

  /// Centre of the moon in global coordinates — the point the orb "reads"
  /// with, rather than wherever the finger happens to be.
  Offset? get _moonCentre {
    final box = _moonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  // ---- hold-to-choose ---------------------------------------------------

  void _holdStart(AppState state) {
    _dwell?.cancel();
    HapticFeedback.mediumImpact();
    state.openTreeHold();
  }

  void _holdMove(AppState state, Offset globalPos) {
    if (!state.treeHold) return;
    final geo = TreeGeometry.instance;

    // While the methods are fanned out, they take priority over the ring.
    final logIndex = state.treeLogIndex;
    if (logIndex != null) {
      final sub = geo.hitTestSub(logIndex, globalPos);
      if (sub != null) {
        if (state.treeHoverSub != sub) HapticFeedback.selectionClick();
        state.setTreeHover(logIndex, sub);
        return;
      }
    }

    final node = geo.hitTestNode(globalPos);
    if (node != state.treeHoverNode) {
      if (node != null) HapticFeedback.selectionClick();
      state.setTreeHover(node, null);
      _armDwell(state, node);
    } else if (logIndex != null) {
      state.setTreeHover(logIndex, null);
    }
  }

  /// Resting on the Log node expands it. Any other node cancels the timer, so
  /// sweeping past Log on the way somewhere else does not trigger it.
  void _armDwell(AppState state, int? node) {
    _dwell?.cancel();
    if (node == null) return;
    if (kTreeNodes[node].action != TreeAction.log) return;
    if (state.treeLogExpanded) return;
    _dwell = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !state.treeHold) return;
      HapticFeedback.mediumImpact();
      state.expandTreeLog(node);
    });
  }

  Future<void> _holdEnd(AppState state) async {
    _dwell?.cancel();
    if (!state.treeHold) return;

    final node = state.treeHoverNode;
    final sub = state.treeHoverSub;

    // Released on one of the log methods.
    if (sub != null) {
      final kind = kLogMethods[sub].kind;
      HapticFeedback.mediumImpact();
      state.endTreeHold();
      await _runQuickLog(state, kind);
      return;
    }

    if (node == null) {
      // Released on empty space: leave the menu open so a tap still works.
      state.endTreeHold();
      return;
    }

    final target = kTreeNodes[node];
    if (target.action == TreeAction.log) {
      // Released on Log without dwelling — expand rather than guess a method.
      HapticFeedback.mediumImpact();
      state.treeHold = false;
      state.expandTreeLog(node);
      return;
    }

    HapticFeedback.mediumImpact();
    state.endTreeHold();
    if (target.screen == AppScreen.wallet) {
      state.openWallet();
    } else if (target.screen != null) {
      state.go(target.screen!);
    }
  }

  /// Photo and Scan open the real camera; the other two drop straight into the
  /// conversation. Nothing here pushes a screen. The camera is Qamar+:
  /// typing and speaking never open it.
  ///
  /// Gated on cameraAllowed rather than plusActive — see the same note in
  /// tree_overlay._runMethod. plusActive is false for everyone while billing
  /// is off, so checking it here made the camera unreachable in every build.
  Future<void> _runQuickLog(AppState state, QuickLog kind) async {
    if (kind == QuickLog.scan) {
      state.quickLog(kind);
      await startPacketScan(context, state);
      return;
    }
    if (kind != QuickLog.photo) {
      state.quickLog(kind);
      return;
    }
    if (!state.cameraAllowed) {
      state.refusePhotoLog();
      return;
    }
    try {
      final shot = await _picker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2000);
      if (!mounted) return;
      if (shot == null) return; // backed out of the camera
      state.quickLog(kind);
      state.logPhotoTaken(shot.path);
    } on Exception {
      if (!mounted) return;
      // No camera, or permission refused: still let them log by typing.
      state.quickLog(QuickLog.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,

      // Tap: sticky tree, unchanged.
      onTap: () {
        HapticFeedback.selectionClick();
        state.toggleTree();
      },

      // Hold: open and keep the pointer.
      onLongPressStart: (_) => _holdStart(state),
      onLongPressMoveUpdate: (d) => _holdMove(state, d.globalPosition),
      onLongPressEnd: (_) => _holdEnd(state),
      onLongPressCancel: () {
        _dwell?.cancel();
        if (state.treeHold) state.endTreeHold();
      },

      // Drag: reposition, and drop onto a value to have it explained.
      onPanStart: (_) => _dragDistance = 0,
      onPanUpdate: (d) {
        _dragDistance += d.delta.distance;
        state.setOrbPosition(state.orbX + d.delta.dx, state.orbY + d.delta.dy, maxX: widget.maxX, maxY: widget.maxY);
        final centre = _moonCentre;
        final hit = centre == null ? null : ExplainRegistry.instance.hitTest(centre);
        if (hit != state.explainHoverId && hit != null) HapticFeedback.selectionClick();
        state.setExplainHover(hit);
      },
      onPanEnd: (_) {
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
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: _moonKey,
            width: 56,
            height: 56,
            child: const Center(child: LivingOrb(size: 56, wander: true, sparks: true)),
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
