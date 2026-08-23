import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/scan_flow.dart';
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

/// Six destinations, all lit by the same moon. The ring used to be six
/// competing hues; the mangata is one light, so difference is carried by the
/// icon and the label, not by colour.
const kTreeNodes = [
  TreeNode('اليوم', 'Today', Icons.wb_twilight, 0, QColors.moonlight, AppScreen.today),
  // Logging never opens a page: choose this one and its three input methods
  // take over the ring.
  TreeNode('سجّل', 'Log', Icons.restaurant_menu, 60, QColors.moonlight, null, action: TreeAction.log),
  TreeNode('الخطة', 'Plan', Icons.map_outlined, 120, QColors.moonlight, AppScreen.plan),
  TreeNode('التقدم', 'Progress', Icons.trending_up, 180, QColors.moonlight, AppScreen.progress),
  TreeNode('المحفظة', 'Wallet', Icons.account_balance_wallet_outlined, 240, QColors.moonlight, AppScreen.wallet),
  TreeNode('حسابي', 'You', Icons.person_outline, 300, QColors.moonlight, AppScreen.you),
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
  LogMethod('امسح العلبة', 'Scan packet', Icons.qr_code_scanner, QuickLog.scan),
];

/// Where the log methods sit once Log is chosen. They take over the ring
/// rather than fanning off the Log node: crowding them and their labels into a
/// 60-degree arc stacked them on top of each other and made them impossible to
/// hit.
///
/// Spaced evenly rather than listed, because the list has changed length once
/// already and a hard-coded [0, 120, 240] is a range error waiting for the
/// next method to be added.
List<double> get _logAngles =>
    [for (var i = 0; i < kLogMethods.length; i++) 360.0 * i / kLogMethods.length];

Offset _logMethodCenter(int i) => Offset(
      _center.dx + _ringRadius * math.cos((_logAngles[i] - 90) * math.pi / 180),
      _center.dy + _ringRadius * math.sin((_logAngles[i] - 90) * math.pi / 180),
    );

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

  /// Centre of a log method in canvas-local coordinates.
  static Offset localSubCenter(int logIndex, int method) => _logMethodCenter(method);

  /// The same point in global coordinates, for hit-testing against the finger.
  Offset? subCenter(int logIndex, int method) {
    final o = canvasOrigin;
    return o == null ? null : o + _logMethodCenter(method);
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
      if (c != null && (point - c).distance <= _nodeSize * 0.95) return i;
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

    final hint = state.treeLogExpanded
        ? (state.isAr
            ? 'الكتابة والصوت مجاناً · الصورة لـ Qamar+'
            : 'Type or speak for free · photo is Qamar+')
        : state.treeHold
            ? (state.isAr ? 'اسحب لاختيار وسيب' : 'Drag to choose, then let go')
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
                                builder: (context, _) => CustomPaint(
                                  painter: _BeamPainter(
                                    _c.value,
                                    state.treeLogExpanded ? _logAngles : [for (final n in kTreeNodes) n.angle],
                                  ),
                                ),
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
                            if (!state.treeLogExpanded)
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
                            // Choosing Log swaps the ring for the three input
                            // methods, so nothing is ever stacked on anything.
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

  /// Runs a log method inline. Photo and Scan open the camera immediately; the
  /// other two drop straight into the conversation. Nothing here pushes a
  /// screen.
  ///
  /// The gate is [AppState.cameraAllowed], not plusActive. Those are not the
  /// same question: plusActive is false for everybody while Paymob is off, so
  /// asking it directly sent every user to a subscription screen that itself
  /// refuses to open — a camera button that did nothing at all. cameraAllowed
  /// is the rule ("camera is Qamar+") including the part where a rule with
  /// nothing to enforce yet lets everyone through.
  Future<void> _runMethod(BuildContext context, AppState state, QuickLog kind) async {
    if (kind == QuickLog.scan) {
      // Barcode first, panel second — see services/scan_flow.dart.
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
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2000);
      if (!context.mounted) return;
      if (shot == null) {
        // Backed out of the camera: close up rather than logging nothing.
        state.endTreeHold();
        state.closeTree();
        return;
      }
      state.quickLog(kind);
      state.logPhotoTaken(shot.path);
    } on Exception {
      // No camera or a refused permission: fall back to the conversation
      // rather than leaving the tap doing nothing at all.
      if (!context.mounted) return;
      state.quickLog(QuickLog.text);
    }
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
            left: local.dx - _nodeSize / 2,
            top: local.dy - _nodeSize / 2,
            child: _SubIcon(
              method: kLogMethods[i],
              label: kLogMethods[i].label(state.isAr),
              hovered: state.treeHoverSub == i,
              locked: (kLogMethods[i].kind == QuickLog.photo ||
                      kLogMethods[i].kind == QuickLog.scan) &&
                  !state.cameraAllowed,
              // Works on a plain tap as well as a hold-and-release.
              onTap: state.treeHold ? null : () => _runMethod(context, state, kLogMethods[i].kind),
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
                    color: hovered ? Color.lerp(const Color(0xEB141C2E), color, 0.18) : const Color(0xEB141C2E),
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
  final bool locked;
  final VoidCallback? onTap;
  const _SubIcon({
    required this.method,
    required this.label,
    required this.hovered,
    this.locked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _nodeSize,
      height: _nodeSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
            color: Colors.transparent,
            shape: CircleBorder(side: BorderSide(color: QColors.moonlight.withValues(alpha: hovered ? 1.0 : 0.5), width: hovered ? 2 : 1)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: _nodeSize,
                height: _nodeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered ? Color.lerp(const Color(0xF0101828), QColors.moonlight, 0.18) : const Color(0xF0101828),
                  boxShadow: [BoxShadow(color: QColors.moonlight.withValues(alpha: hovered ? 0.45 : 0.16), blurRadius: hovered ? 26 : 16)],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(method.icon, size: 23, color: QColors.moonlight),
                    if (locked)
                      const Positioned(
                        right: 8,
                        bottom: 8,
                        child: Icon(Icons.lock, size: 11, color: QColors.gold),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: _nodeSize + _labelGap,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: QText.body(size: 12, weight: FontWeight.w500, color: hovered ? QColors.textPrimary : QColors.textMid),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branches drawn as light thrown off the moon rather than dotted lines.
/// The mangata: the moon's road, thrown out to each destination as one cool
/// white light rather than six competing colours.
class _BeamPainter extends CustomPainter {
  final double t;

  /// Which ring positions to light. In log mode only the three method slots
  /// exist, so only those get a beam.
  final List<double> angles;
  _BeamPainter(this.t, this.angles);

  static const double _innerGap = 44;
  static const double _startHalfWidth = 2.5;
  static const double _endHalfWidth = 21;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < angles.length; i++) {
      final target = Offset(
        _center.dx + _ringRadius * math.cos((angles[i] - 90) * math.pi / 180),
        _center.dy + _ringRadius * math.sin((angles[i] - 90) * math.pi / 180),
      );
      final dir = (target - _center) / (target - _center).distance;
      final perp = Offset(-dir.dy, dir.dx);
      final start = _center + dir * _innerGap;
      final end = _center + dir * ((target - _center).distance - _nodeSize / 2 - 2);

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
              QColors.moonlight.withValues(alpha: 0.34),
              QColors.moonbeam.withValues(alpha: 0.14),
              QColors.moonbeam.withValues(alpha: 0.02),
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
            colors: [QColors.moonlight.withValues(alpha: 0.70), QColors.moonbeam.withValues(alpha: 0.05)],
          ).createShader(Rect.fromPoints(start, end))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
      );

      final travel = (t + i * 0.14) % 1.0;
      final head = Offset.lerp(start, end, Curves.easeInOut.transform(travel))!;
      canvas.drawCircle(
        head,
        3.4 * (1 - travel * 0.55),
        Paint()
          ..color = QColors.moonlight.withValues(alpha: 0.55 * (1 - travel))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BeamPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.angles.length != angles.length;
}
