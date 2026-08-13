import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'living_orb.dart';

class _TreeNode {
  final String labelAr, labelEn;
  final Offset center; // in the 340x340 coordinate space
  final Offset buttonTopLeft;
  final Color color;
  final AppScreen screen;
  const _TreeNode(this.labelAr, this.labelEn, this.center, this.buttonTopLeft, this.color, this.screen);
}

const _nodes = [
  _TreeNode('اليوم', 'Today', Offset(170, 52), Offset(128, 10), QColors.violet, AppScreen.today),
  _TreeNode('تسجيل', 'Log', Offset(58, 134), Offset(16, 92), QColors.cyan, AppScreen.log),
  _TreeNode('الخطة', 'Plan', Offset(282, 134), Offset(240, 92), QColors.green, AppScreen.plan),
  _TreeNode('التقدم', 'Progress', Offset(101, 266), Offset(59, 224), QColors.skyBlue, AppScreen.progress),
  _TreeNode('حسابي', 'You', Offset(239, 266), Offset(197, 224), QColors.violetSoft, AppScreen.you),
];

/// The radial "living tree" opened by tapping the nav orb — moon at center,
/// five screens on a ring, dashed branches with a traveling pulse.
class TreeOverlay extends StatefulWidget {
  const TreeOverlay({super.key});
  @override
  State<TreeOverlay> createState() => _TreeOverlayState();
}

class _TreeOverlayState extends State<TreeOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    return Positioned.fill(
      child: GestureDetector(
        onTap: state.closeTree,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              color: const Color(0xDC070C19),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {}, // absorb taps inside the ring so it doesn't close itself
                    child: SizedBox(
                      width: 340,
                      height: 340,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => CustomPaint(painter: _BranchPainter(_c.value)),
                            ),
                          ),
                          const Positioned(
                            left: 105,
                            top: 105,
                            child: SizedBox(
                              width: 130,
                              height: 130,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(colors: [Color(0x807B6CFF), Colors.transparent], stops: [0.0, 0.68]),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 126,
                            top: 126,
                            child: LivingOrb(size: 88, onTap: state.openChat, breathDuration: const Duration(milliseconds: 4600)),
                          ),
                          for (final n in _nodes)
                            Positioned(
                              left: n.buttonTopLeft.dx,
                              top: n.buttonTopLeft.dy,
                              child: _NodeButton(node: n, label: state.isAr ? n.labelAr : n.labelEn, onTap: () => state.go(n.screen)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(t.treeHint, textAlign: TextAlign.center, style: QText.body(size: 12, color: QColors.textFaint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NodeButton extends StatefulWidget {
  final _TreeNode node;
  final String label;
  final VoidCallback onTap;
  const _NodeButton({required this.node, required this.label, required this.onTap});
  @override
  State<_NodeButton> createState() => _NodeButtonState();
}

class _NodeButtonState extends State<_NodeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5600))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(offset: Offset(0, -4 * _c.value), child: child),
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: widget.node.color.withOpacity(0.55))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xEB141C2E), boxShadow: [BoxShadow(color: widget.node.color.withOpacity(0.22), blurRadius: 22)]),
            child: Text(widget.label, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _BranchPainter extends CustomPainter {
  final double t;
  _BranchPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(170, 170);
    for (final n in _nodes) {
      final paint = Paint()
        ..color = n.color.withOpacity(0.8)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      _drawDashedLine(canvas, center, n.center, paint, t);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double phase) {
    const dashLen = 7.0, gapLen = 9.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var dist = -(phase * (dashLen + gapLen));
    while (dist < total) {
      final start = (dist).clamp(0, total);
      final end = (dist + dashLen).clamp(0, total);
      if (end > start) {
        canvas.drawLine(a + dir * start.toDouble(), a + dir * end.toDouble(), paint);
      }
      dist += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _BranchPainter oldDelegate) => oldDelegate.t != t;
}
