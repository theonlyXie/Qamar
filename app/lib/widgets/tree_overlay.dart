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
const double _ringRadius = 118;

/// Icon-only circles. Labels sit *outside* them — text inside a small circle
/// gets ellipsized the moment a real Arabic font loads and the words are wider
/// than the tofu boxes a fallback font draws.
const double _nodeSize = 58;
const double _labelGap = 6;

/// The moon at the middle of the tree.
const double _orbSize = 76;

/// [LivingOrb] lays itself out in a box of `size * 1.7` with the moon centred
/// inside it, so positioning it means offsetting by half that box — not half
/// the moon.
const double _orbBox = _orbSize * 1.7;
const double _orbLeft = _canvas / 2 - _orbBox / 2;

/// What activating a node does.
enum TreeAction { navigate, log }

class TreeNode {
  final String labelAr, labelEn;
  final IconData icon;

  /// Position on the ring, in degrees, clockwise from straight up.
  final double angle;
  final Color color;
  final AppScreen? screen;
  final TreeAction action;

  const TreeNode(this.labelAr, this.labelEn, this.icon, this.angle, this.color, this.screen,
      {this.action = TreeAction.navigate});

  Offset get center => Offset(
        _center.dx + _ringRadius * math.cos((angle - 90) * math.pi / 180),
        _center.dy + _ringRadius * math.sin((angle - 90) * math.pi / 180),
      );
  Offset get topLeft => center - const Offset(_nodeSize / 2, _nodeSize / 2);

  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kTreeNodes = [
  TreeNode('اليوم', 'Today', Icons.wb_twilight, 0, QColors.violet, AppScreen.today),
  // Logging never opens a page: dwell on this one and its three input methods
  // fan out in place.
  TreeNode('سجّل', 'Log', Icons.restaurant_menu, 60, QColors.cyan, null, action: TreeAction.log),
  TreeNode('الخطة', 'Plan', Icons.map_outlined, 120, QColors.green, AppScreen.plan),
  TreeNode('التقدم', 'Progress', Icons.trending_up, 180, QColors.skyBlue, AppScreen.progress),
  TreeNode('المحفظة', 'Wallet', Icons.account_balance_wallet_outlined, 240, QColors.amber, AppScreen.wallet),
  TreeNode('حسابي', 'You', Icons.person_outline, 300, QColors.violetSoft, AppScreen.you),
];

/// The three ways to log a meal, fanned around the Log node while it is held.
class LogMethod {
  final String labelAr, labelEn;
  final IconData icon;
  final QuickLog kind;
  const LogMethod(this.labelAr, this.labelEn, this.icon, this.kind);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kLogMethods = [
  LogMethod('اتكلم', 'Speak', Icons.mic_none, QuickLog.voice),
  LogMethod('اكتب', 'Type', Icons.keyboard_outlined, QuickLog.text),
  LogMethod('صوّر', 'Photo', Icons.photo_camera_outlined, QuickLog.photo),
];

const double _subRadius = 74;
const double _subSize = 46;

/// Where the tree's nodes currently sit in global coordinates.
///
/// The orb drives selection while the user holds it, and the orb is a sibling
/// of this overlay in the shell's Stack — it cannot reach the nodes through
/// the widget tree, so their positions are published here instead.
class TreeGeometry {
  TreeGeometry._();
  static final TreeGeometry instance = TreeGeometry._();

  /// Top-left of the 340x340 canvas in global coordinates, or null when the
  /// tree is closed.
  Offset? canvasOrigin;

  Offset? nodeCenter(int i) {
    final o = canvasOrigin;
    return o == null ? null : o + kTreeNodes[i].center;
  }

  /// Centre of [method] in canvas-local coordinates, while the Log node is
  /// expanded. The methods fan around the Log node on its outward side so they
  /// never overlap the moon.
  ///
  /// Local rather than global so the icons can be laid out on the very first
  /// frame, before [canvasOrigin] has been measured.
  static Offset localSubCenter(int logIndex, int method) {
    final outward = (kTreeNodes[logIndex].angle - 90) * math.pi / 180;
    const spread = 0.78; // radians between methods
    final a = outward + (method - (kLogMethods.length - 1) / 2) * spread;
    return kTreeNodes[logIndex].center + Offset(math.cos(a), math.sin(a)) * _subRadius;
  }

  /// The same point in global coordinates, for hit-testing against the finger.
  Offset? subCenter(int logIndex, int method) {
    final o = canvasOrigin;
    return o == null ? null : o + localSubCenter(logIndex, method);
  }

  /// Index of the node under [point], or null. Generous radius: this is driven
  /// by a thumb dragging across the screen, not a mouse.
  int? hitTestNode(Offset point) {
    for (var i = 0; i < kTreeNodes.length; i++) {
      final c = nodeCenter(i);
      if (c != null && (point - c).distance <= _nodeSize * 0.85) return i;
    }
    return null;
  }

  int? hitTestSub(int logIndex, Offset point) {
    for (var i = 0; i < kLogMethods.length; i++) {
      final c = subCenter(logIndex, i);
      if (c != null && (point - c).distance <= _subSize * 0.85) return i;
    }
    return null;
  }
}

/// The radial "living tree" — the moon at the centre, six destinations on a
/// ring, and light beaming out to each of them.
class TreeOverlay extends StatefulWidget {
  const TreeOverlay({super.key});
  @override
  State<TreeOverlay> createState() => _TreeOverlayState();
}

class _TreeOverlayState extends State<TreeOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..repeat();
  final GlobalKey _canvasKey = GlobalKey();

  @override
  void dispose() {
    _c.dispose();
    TreeGeometry.instance.canvasOrigin = null;
    super.dispose();
  }

  void _publishGeometry() {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    TreeGeometry.instance.canvasOrigin = box.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishGeometry());

    final hint = state.treeHold
        ? (state.isAr ? 'اسحب لاختيار · استمر على «سجّل» لطرق التسجيل' : 'Drag to choose · hold Log for input methods')
        : t.treeHint;

    return Positioned.fill(
      // In hold mode the orb owns the pointer, so this must not intercept it.
      child: IgnorePointer(
        ignoring: state.treeHold,
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
                      onTap: () {}, // absorb taps inside the ring
                      child: SizedBox(
                        key: _canvasKey,
                        width: _canvas,
                        height: _canvas,
                        child: Stack(
                          clipBehavior: Clip.none,
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
                            for (var i = 0; i < kTreeNodes.length; i++)
                              Positioned(
                                left: kTreeNodes[i].topLeft.dx,
                                top: kTreeNodes[i].topLeft.dy,
                                child: _NodeButton(
                                  node: kTreeNodes[i],
                                  label: kTreeNodes[i].label(state.isAr),
                                  hovered: state.treeHoverNode == i,
                                  onTap: state.treeHold ? null : () => _activate(state, i),
                                ),
                              ),
                            // Log methods, fanned out while Log is held.
                            if (state.treeLogExpanded) ..._buildSubIcons(state),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Text(hint, textAlign: TextAlign.center, style: QText.body(size: 12, color: QColors.textFaint)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _activate(AppState state, int i) {
    final node = kTreeNodes[i];
    if (node.action == TreeAction.log) {
      state.expandTreeLog(i);
      return;
    }
    if (node.screen == AppScreen.wallet) {
      state.openWallet();
    } else if (node.screen != null) {
      state.go(node.screen!);
    }
  }

  List<Widget> _buildSubIcons(AppState state) {
    final logIndex = state.treeLogIndex;
    if (logIndex == null) return const [];
    return [
      for (var i = 0; i < kLogMethods.length; i++)
        Builder(builder: (context) {
          final local = TreeGeometry.localSubCenter(logIndex, i);
          return Positioned(
            left: local.dx - _subSize / 2,
            top: local.dy - _subSize / 2,
            child: _SubIcon(
              method: kLogMethods[i],
              label: kLogMethods[i].label(state.isAr),
              hovered: state.treeHoverSub == i,
              onTap: state.treeHold ? null : () => state.quickLog(kLogMethods[i].kind),
            ),
          );
        }),
    ];
  }
}

class _NodeButton extends StatefulWidget {
  final TreeNode node;
  final String label;
  final bool hovered;
  final VoidCallback? onTap;
  const _NodeButton({required this.node, required this.label, required this.hovered, this.onTap});
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
    final hovered = widget.hovered;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(offset: Offset(0, -4 * _c.value), child: child),
      // The circle is a fixed size; the label is allowed to overflow past it
      // rather than being squeezed inside and clipped.
      child: SizedBox(
        width: _nodeSize,
        height: _nodeSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Material(
              color: Colors.transparent,
              shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: hovered ? 1.0 : 0.55), width: hovered ? 2 : 1)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: _nodeSize,
                  height: _nodeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hovered ? Color.lerp(const Color(0xEB141C2E), color, 0.22) : const Color(0xEB141C2E),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: hovered ? 0.55 : 0.22), blurRadius: hovered ? 30 : 22)],
                  ),
                  child: Icon(widget.node.icon, size: hovered ? 25 : 23, color: color),
                ),
              ),
            ),
            Positioned(
              top: _nodeSize + _labelGap,
              child: Text(
                widget.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.center,
                style: QText.body(
                  size: 12,
                  weight: FontWeight.w500,
                  color: hovered ? QColors.textPrimary : QColors.textMid,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubIcon extends StatelessWidget {
  final LogMethod method;
  final String label;
  final bool hovered;
  final VoidCallback? onTap;
  const _SubIcon({required this.method, required this.label, required this.hovered, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _subSize,
      height: _subSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
            color: Colors.transparent,
            shape: CircleBorder(side: BorderSide(color: QColors.cyan.withValues(alpha: hovered ? 1.0 : 0.5), width: hovered ? 2 : 1)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: _subSize,
                height: _subSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered ? Color.lerp(const Color(0xF0101828), QColors.cyan, 0.25) : const Color(0xF0101828),
                  boxShadow: [BoxShadow(color: QColors.cyan.withValues(alpha: hovered ? 0.5 : 0.18), blurRadius: hovered ? 24 : 14)],
                ),
                child: Icon(method.icon, size: 20, color: QColors.cyan),
              ),
            ),
          ),
          Positioned(
            top: _subSize + 4,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: QText.body(size: 10.5, weight: FontWeight.w500, color: hovered ? QColors.textPrimary : QColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branches drawn as light thrown off the moon rather than dotted lines.
class _BeamPainter extends CustomPainter {
  final double t;
  _BeamPainter(this.t);

  static const double _innerGap = 44;
  static const double _startHalfWidth = 2.5;
  static const double _endHalfWidth = 21;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < kTreeNodes.length; i++) {
      final n = kTreeNodes[i];
      final dir = (n.center - _center) / (n.center - _center).distance;
      final perp = Offset(-dir.dy, dir.dx);
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

      final travel = (t + i * 0.14) % 1.0;
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
