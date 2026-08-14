import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'living_orb.dart';

/// The tree lives in a fixed 340x340 square; everything below is expressed in
/// that space so the geometry stays readable.
const double _canvas = 340;
const Offset _center = Offset(_canvas / 2, _canvas / 2);
const double _ringRadius = 124;
const double _nodeSize = 74;

/// The moon at the middle of the tree.
const double _orbSize = 76;

/// [LivingOrb] lays itself out in a box of `size * 1.7` with the moon centred
/// inside it, so positioning it means offsetting by half that box — not half
/// the moon. Getting this wrong is what left the moon sitting low and right of
/// the ring it is supposed to anchor.
const double _orbBox = _orbSize * 1.7;
const double _orbLeft = _canvas / 2 - _orbBox / 2;

class _TreeNode {
  final String labelAr, labelEn;
  final IconData icon;

  /// Position on the ring, in degrees, clockwise from straight up.
  final double angle;
  final Color color;
  final AppScreen screen;
  const _TreeNode(this.labelAr, this.labelEn, this.icon, this.angle, this.color, this.screen);

  Offset get center => Offset(
        _center.dx + _ringRadius * math.cos((angle - 90) * math.pi / 180),
        _center.dy + _ringRadius * math.sin((angle - 90) * math.pi / 180),
      );
  Offset get topLeft => center - const Offset(_nodeSize / 2, _nodeSize / 2);
}

const _nodes = [
  _TreeNode('اليوم', 'Today', Icons.wb_twilight, 0, QColors.violet, AppScreen.today),
  _TreeNode('تسجيل', 'Log', Icons.restaurant_menu, 60, QColors.cyan, AppScreen.log),
  _TreeNode('الخطة', 'Plan', Icons.map_outlined, 120, QColors.green, AppScreen.plan),
  _TreeNode('التقدم', 'Progress', Icons.trending_up, 180, QColors.skyBlue, AppScreen.progress),
  _TreeNode('المحفظة', 'Wallet', Icons.account_balance_wallet_outlined, 240, QColors.amber, AppScreen.wallet),
  _TreeNode('حسابي', 'You', Icons.person_outline, 300, QColors.violetSoft, AppScreen.you),
];

/// The radial "living tree" opened by tapping the nav orb — the moon at the
/// centre, six destinations on a ring, and light beaming out to each of them.
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
                      width: _canvas,
                      height: _canvas,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => CustomPaint(painter: _BeamPainter(_c.value)),
                            ),
                          ),
                          const Positioned(
                            left: _canvas / 2 - 58,
                            top: _canvas / 2 - 58,
                            child: SizedBox(
                              width: 116,
                              height: 116,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(colors: [Color(0x807B6CFF), Colors.transparent], stops: [0.0, 0.68]),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: _orbLeft,
                            top: _orbLeft,
                            child: LivingOrb(size: _orbSize, onTap: state.openChat),
                          ),
                          for (final n in _nodes)
                            Positioned(
                              left: n.topLeft.dx,
                              top: n.topLeft.dy,
                              child: _NodeButton(
                                node: n,
                                label: state.isAr ? n.labelAr : n.labelEn,
                                onTap: () => n.screen == AppScreen.wallet ? state.openWallet() : state.go(n.screen),
                              ),
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
    final color = widget.node.color;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(offset: Offset(0, -4 * _c.value), child: child),
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: 0.55))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onTap,
          child: Container(
            width: _nodeSize,
            height: _nodeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xEB141C2E),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.22), blurRadius: 22)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.node.icon, size: 21, color: color),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Branches drawn as light thrown off the moon rather than dotted lines: each
/// one is a tapered wedge that starts narrow and bright at the moon's edge and
/// spreads as it reaches its destination, with a brighter pulse travelling
/// along it.
class _BeamPainter extends CustomPainter {
  final double t;
  _BeamPainter(this.t);

  /// Beams start at the moon's rim, not its centre, so the moon does not sit
  /// in a starburst of lines converging under it.
  static const double _innerGap = 44;
  static const double _startHalfWidth = 2.5;
  static const double _endHalfWidth = 21;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in _nodes) {
      final dir = (n.center - _center) / (n.center - _center).distance;
      final perp = Offset(-dir.dy, dir.dx);
      // Stop short of the node so the beam fades into it instead of colliding.
      final start = _center + dir * _innerGap;
      final end = _center + dir * ((n.center - _center).distance - _nodeSize / 2 - 2);

      final wedge = Path()
        ..moveTo((start + perp * _startHalfWidth).dx, (start + perp * _startHalfWidth).dy)
        ..lineTo((end + perp * _endHalfWidth).dx, (end + perp * _endHalfWidth).dy)
        ..lineTo((end - perp * _endHalfWidth).dx, (end - perp * _endHalfWidth).dy)
        ..lineTo((start - perp * _startHalfWidth).dx, (start - perp * _startHalfWidth).dy)
        ..close();

      canvas.drawPath(
        wedge,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              n.color.withValues(alpha: 0.60),
              n.color.withValues(alpha: 0.26),
              n.color.withValues(alpha: 0.05),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromPoints(start, end))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );

      // A bright filament down the middle of the beam.
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [n.color.withValues(alpha: 0.95), n.color.withValues(alpha: 0.10)],
          ).createShader(Rect.fromPoints(start, end))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );

      // The pulse riding outward along the filament.
      final travel = (t + _nodes.indexOf(n) * 0.14) % 1.0;
      final head = Offset.lerp(start, end, Curves.easeInOut.transform(travel))!;
      canvas.drawCircle(
        head,
        3.4 * (1 - travel * 0.55),
        Paint()
          ..color = n.color.withValues(alpha: 0.75 * (1 - travel))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BeamPainter oldDelegate) => oldDelegate.t != t;
}
