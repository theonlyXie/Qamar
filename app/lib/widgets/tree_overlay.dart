import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/photos.dart';
import 'package:provider/provider.dart';

import '../models/water.dart';
import '../models/activity.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';
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

/// What activating a node does. Log and Water do not open a page: they swap
/// the ring for their own choices, which act in place.
enum TreeAction { navigate, log, water }

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

  Offset get center => _onRing(angle);
  Offset get topLeft => center - const Offset(_nodeSize / 2, _nodeSize / 2);

  String label(bool isAr) => isAr ? labelAr : labelEn;
}

Offset _onRing(double angle) => Offset(
      _center.dx + _ringRadius * math.cos((angle - 90) * math.pi / 180),
      _center.dy + _ringRadius * math.sin((angle - 90) * math.pi / 180),
    );

/// The five destinations — depth one of the blueprint's action tree — evenly
/// on the ring, all lit by the same moon.
///
/// Today is not a node: it is the screen the orb floats over, and tapping the
/// orb from anywhere else returns to it. Su is not a node either: holding the
/// orb summons the conversation. The wallet lives under Me.
const kTreeNodes = [
  TreeNode('سجّل', 'Log', Icons.restaurant_menu, 0, QColors.moonlight, null, action: TreeAction.log),
  TreeNode('الخطة', 'Plan', Icons.map_outlined, 72, QColors.moonlight, AppScreen.plan),
  TreeNode('الماء', 'Water', Icons.water_drop_outlined, 144, QColors.moonlight, null, action: TreeAction.water),
  TreeNode('المراجعة', 'Review', Icons.trending_up, 216, QColors.moonlight, AppScreen.progress),
  TreeNode('أنا', 'Me', Icons.person_outline, 288, QColors.moonlight, AppScreen.you),
];

/// "Modes (Ramadan) appear as a seventh node only when active" — the sixth
/// on the ring, since Su is reached by holding. In season the five make room
/// and the ring is six, evenly spaced; out of season it is [kTreeNodes].
List<TreeNode> treeNodesFor({required bool ramadan}) {
  if (!ramadan) return kTreeNodes;
  final all = [
    ...kTreeNodes,
    const TreeNode('رمضان', 'Ramadan', Icons.nightlight_round, 300, QColors.gold, AppScreen.ramadan),
  ];
  return [
    for (var i = 0; i < all.length; i++)
      TreeNode(all[i].labelAr, all[i].labelEn, all[i].icon, i * 360 / all.length, all[i].color, all[i].screen, action: all[i].action),
  ];
}

/// The three ways to log a meal, fanned around the ring once Log is chosen.
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
  LogMethod('كرّر', 'Repeat', Icons.replay, QuickLog.repeat),
  LogMethod('حركة', 'Activity', Icons.directions_run, QuickLog.activity),
];

/// The kinds of movement people actually name, fanned out once Activity is
/// chosen. How long comes next, as chips.
class ActivityChoice {
  final String labelAr, labelEn;
  final IconData icon;
  final ActivityKind kind;
  const ActivityChoice(this.labelAr, this.labelEn, this.icon, this.kind);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kActivityChoices = [
  ActivityChoice('كورة', 'Football', Icons.sports_soccer, ActivityKind.football),
  ActivityChoice('مشي', 'Walk', Icons.directions_walk, ActivityKind.walk),
  ActivityChoice('جيم', 'Gym', Icons.fitness_center, ActivityKind.gym),
  ActivityChoice('جري', 'Run', Icons.directions_run, ActivityKind.run),
  ActivityChoice('غيره', 'Other', Icons.accessibility_new, ActivityKind.other),
];

/// The three things people drink, fanned around the ring once Water is chosen.
/// One tap each; nothing goes through the assistant.
class WaterChoice {
  final String labelAr, labelEn;
  final IconData icon;
  final WaterUnit unit;
  const WaterChoice(this.labelAr, this.labelEn, this.icon, this.unit);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kWaterChoices = [
  WaterChoice('كوباية', 'Glass', Icons.local_drink_outlined, WaterUnit.glass),
  WaterChoice('زجاجة', 'Bottle', Icons.water_drop, WaterUnit.bottle),
  WaterChoice('شاي', 'Tea', Icons.emoji_food_beverage_outlined, WaterUnit.tea),
];

/// Where fanned-out choices sit. They take over the whole ring rather than
/// clustering around their parent node: 58px circles and their labels
/// crowded into a 72-degree arc stack on top of each other and cannot be hit.
/// Evenly spaced, however many there are.
List<double> subAnglesFor(int count) => [for (var i = 0; i < count; i++) i * 360 / count];

/// Canvas-local centre of the i-th of [of] fanned-out choices.
Offset treeSubCenter(int i, {int of = 3}) => _onRing(subAnglesFor(of)[i]);

/// The radial "living tree" — the moon at the centre, five destinations on a
/// ring, and light beaming out to each of them.
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
    final isAr = state.isAr;

    final photosLeft = state.photoQuota.remaining;
    final repeatChoices = state.repeatChoices;
    final int fanCount = state.treeLogSub == TreeSub.activity
        ? kActivityChoices.length
        : state.treeLogSub == TreeSub.repeat
            ? repeatChoices.length
            : state.treeLogExpanded
                ? kLogMethods.length
                : kWaterChoices.length;
    final hint = state.treeLogSub == TreeSub.activity
        ? (isAr ? 'اختار نوع الحركة، وبعدين قد إيه.' : 'Pick the movement, then how long.')
        : state.treeLogSub == TreeSub.repeat
            ? (repeatChoices.isEmpty
                ? (isAr ? 'سجّل وجبة الأول، وهتظهر هنا عشان تكرّرها بدوسة.' : 'Log a meal first and it will be here to repeat with one tap.')
                : (isAr ? 'دوسة واحدة تسجّل الوجبة تاني بنفس أرقامها.' : 'One tap logs the meal again with the same numbers.'))
        : state.treeLogExpanded
        ? (isAr
            ? 'الكتابة والصوت مجاناً بلا حد · باقي ${state.iso('$photosLeft')} صور النهارده'
            : 'Type or speak, unlimited · $photosLeft photos left today')
        : state.treeWaterExpanded
            ? (isAr ? 'كوباية ٢٥٠ مل · زجاجة ٥٠٠ مل · شاي ٢٠٠ مل' : 'Glass 250 ml · bottle 500 ml · tea 200 ml')
            : t.treeHint;

    final nodes = treeNodesFor(ramadan: state.seasonVisible);
    final beamAngles = state.treeExpanded ? subAnglesFor(fanCount) : [for (final n in nodes) n.angle];

    // Photo was chosen and the camera would not open: the problem takes the
    // ring's place. A tap outside still closes.
    final problem = state.treeProblem;
    if (problem != null) {
      return Positioned.fill(
        child: GestureDetector(
          onTap: state.closeTree,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: const Color(0xDC070C19),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GestureDetector(onTap: () {}, child: QStateCard(problem: problem)),
              ),
            ),
          ),
        ),
      );
    }

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
                    onTap: () {}, // absorb taps inside the ring
                    child: SizedBox(
                      width: _canvas,
                      height: _canvas,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: _c,
                              builder: (context, _) => CustomPaint(painter: _BeamPainter(_c.value, beamAngles)),
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
                          // The moon in the middle is the same one as the
                          // floating orb; tapping it here is the tap-friendly
                          // route to the conversation for anyone who cannot hold.
                          Positioned(
                            left: _orbLeft,
                            top: _orbLeft,
                            child: LivingOrb(size: _orbSize, onTap: state.openChat, state: state.orbState()),
                          ),
                          if (!state.treeExpanded)
                            for (var i = 0; i < nodes.length; i++)
                              Positioned(
                                left: nodes[i].topLeft.dx,
                                top: nodes[i].topLeft.dy,
                                child: _RingButton(
                                  icon: nodes[i].icon,
                                  label: nodes[i].label(isAr),
                                  color: nodes[i].color,
                                  bob: true,
                                  onTap: () => _activate(state, nodes[i], i),
                                ),
                              ),
                          if (state.treeLogExpanded && state.treeLogSub == null)
                            for (var i = 0; i < kLogMethods.length; i++)
                              _placeSub(
                                i,
                                kLogMethods.length,
                                _RingButton(
                                  icon: kLogMethods[i].icon,
                                  label: kLogMethods[i].label(isAr),
                                  color: QColors.moonlight,
                                  locked: kLogMethods[i].kind == QuickLog.photo && state.photoQuota.exhausted,
                                  onTap: () => _runMethod(context, state, kLogMethods[i].kind),
                                ),
                              ),
                          if (state.treeLogSub == TreeSub.activity)
                            for (var i = 0; i < kActivityChoices.length; i++)
                              _placeSub(
                                i,
                                kActivityChoices.length,
                                _RingButton(
                                  icon: kActivityChoices[i].icon,
                                  label: kActivityChoices[i].label(isAr),
                                  color: QColors.green,
                                  onTap: () => state.chooseActivity(kActivityChoices[i].kind),
                                ),
                              ),
                          if (state.treeLogSub == TreeSub.repeat)
                            for (var i = 0; i < repeatChoices.length; i++)
                              _placeSub(
                                i,
                                repeatChoices.length,
                                _RingButton(
                                  icon: Icons.restaurant,
                                  label: _short(repeatChoices[i].name),
                                  color: QColors.moonlight,
                                  onTap: () => state.repeatMeal(repeatChoices[i]),
                                ),
                              ),
                          if (state.treeWaterExpanded)
                            for (var i = 0; i < kWaterChoices.length; i++)
                              _placeSub(
                                i,
                                kWaterChoices.length,
                                _RingButton(
                                  icon: kWaterChoices[i].icon,
                                  label: kWaterChoices[i].label(isAr),
                                  color: QColors.cyan,
                                  onTap: () => state.quickWater(kWaterChoices[i].unit),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Opened by Today's "Log a meal" button, the tree names
                  // where it lives, until the moon has been tapped once.
                  if (state.treeOpenedFromButton && !state.gesturesLearned.contains(OrbGesture.tap)) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Text(
                        isAr ? 'المرة الجاية، دوس على القمر وهتلاقي ده.' : 'Next time, tap the moon to find this.',
                        textAlign: TextAlign.center,
                        style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMid),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
    );
  }

  Widget _placeSub(int i, int of, Widget child) {
    final c = treeSubCenter(i, of: of);
    return Positioned(left: c.dx - _nodeSize / 2, top: c.dy - _nodeSize / 2, child: child);
  }

  /// A meal name short enough to sit under a ring circle.
  static String _short(String name) {
    final one = name.split(' + ').first.trim();
    return one.length <= 14 ? one : '${one.substring(0, 13)}…';
  }

  void _activate(AppState state, TreeNode node, int i) {
    switch (node.action) {
      case TreeAction.log:
        state.expandTreeLog(i);
      case TreeAction.water:
        state.expandTreeWater(i);
      case TreeAction.navigate:
        if (node.screen != null) state.go(node.screen!);
    }
  }

  /// Runs a log method inline. Photo opens the camera immediately; the other
  /// two drop straight into the conversation. Nothing here pushes a screen,
  /// and nothing here asks for Qamar+ — the server counts the photo and says
  /// so when today's are gone.
  Future<void> _runMethod(BuildContext context, AppState state, QuickLog kind) async {
    if (kind == QuickLog.repeat) {
      state.expandTreeSub(TreeSub.repeat);
      return;
    }
    if (kind == QuickLog.activity) {
      state.expandTreeSub(TreeSub.activity);
      return;
    }
    if (kind != QuickLog.photo) {
      state.quickLog(kind);
      return;
    }
    try {
      final shot = await pickCompressedPhoto(ImageSource.camera);
      if (!context.mounted) return;
      if (shot == null) {
        // Backed out of the camera: close up rather than logging nothing.
        state.closeTree();
        return;
      }
      state.quickLog(kind);
      state.logPhotoTaken(shot.path);
    } on Exception catch (e) {
      // No camera, or a refused permission: the tree says so, with the way
      // on — Settings where the phone allows it, and typing the meal
      // instead — rather than quietly turning into a text box (O10).
      if (!context.mounted) return;
      state.cameraFailedInTree(e);
    }
  }
}

/// One circle on the ring: a destination, a log method or a water unit. The
/// circle is a fixed size; the label is allowed to overflow past it rather
/// than being squeezed inside and clipped.
class _RingButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool locked;
  final bool bob;
  final VoidCallback onTap;
  const _RingButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.locked = false,
    this.bob = false,
  });
  @override
  State<_RingButton> createState() => _RingButtonState();
}

class _RingButtonState extends State<_RingButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 5600))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final button = SizedBox(
      width: _nodeSize,
      height: _nodeSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(widget.icon, size: 23, color: color),
                    if (widget.locked)
                      const Positioned(right: 8, bottom: 8, child: Icon(Icons.lock, size: 11, color: QColors.gold)),
                  ],
                ),
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
              style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMid),
            ),
          ),
        ],
      ),
    );
    if (!widget.bob) return button;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(offset: Offset(0, -4 * _c.value), child: child),
      child: button,
    );
  }
}

/// Branches drawn as light thrown off the moon rather than dotted lines.
/// The mangata: the moon's road, thrown out to each destination as one cool
/// white light rather than five competing colours.
class _BeamPainter extends CustomPainter {
  final double t;

  /// Which ring positions to light. When a node is fanned out only its three
  /// choices exist, so only those get a beam.
  final List<double> angles;
  _BeamPainter(this.t, this.angles);

  static const double _innerGap = 44;
  static const double _startHalfWidth = 2.5;
  static const double _endHalfWidth = 21;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < angles.length; i++) {
      final target = _onRing(angles[i]);
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
