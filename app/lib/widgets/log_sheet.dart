import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../models/water.dart';
import '../services/photos.dart';
import '../services/scan_flow.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'surface.dart';

/// One of the three ways to say a meal, the Log sheet's tiles.
class LogMethod {
  final String labelAr, labelEn;
  final IconData icon;
  final QuickLog kind;

  /// The tile's pastel.
  final Color color;
  const LogMethod(this.labelAr, this.labelEn, this.icon, this.kind, this.color);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kLogMethods = [
  LogMethod('اتكلم', 'Speak', QIcons.mic, QuickLog.voice, QColors.lavender),
  LogMethod('اكتب', 'Type', QIcons.keyboard, QuickLog.text, QColors.lime),
  LogMethod('صوّر', 'Photo', QIcons.camera, QuickLog.photo, QColors.mint),
];

/// The kinds of movement people actually name. How long comes next, in its
/// own sheet (ActivitySheet).
class ActivityChoice {
  final String labelAr, labelEn;
  final IconData icon;
  final ActivityKind kind;
  const ActivityChoice(this.labelAr, this.labelEn, this.icon, this.kind);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kActivityChoices = [
  ActivityChoice('كورة', 'Football', QIcons.football, ActivityKind.football),
  ActivityChoice('مشي', 'Walk', QIcons.walk, ActivityKind.walk),
  ActivityChoice('جيم', 'Gym', QIcons.gym, ActivityKind.gym),
  ActivityChoice('جري', 'Run', QIcons.run, ActivityKind.run),
  ActivityChoice('غيره', 'Other', QIcons.other, ActivityKind.other),
];

/// The three things people drink, one tap each; nothing goes through the
/// assistant.
class WaterChoice {
  final String labelAr, labelEn;
  final IconData icon;
  final WaterUnit unit;
  const WaterChoice(this.labelAr, this.labelEn, this.icon, this.unit);
  String label(bool isAr) => isAr ? labelAr : labelEn;
}

const kWaterChoices = [
  WaterChoice('كوباية', 'Glass', QIcons.glass, WaterUnit.glass),
  WaterChoice('زجاجة', 'Bottle', QIcons.bottle, WaterUnit.bottle),
  WaterChoice('شاي', 'Tea', QIcons.tea, WaterUnit.tea),
];

/// The Log sheet: what the orb's tap opens, in place of the tree it used to
/// bloom. Every way to log is on it, one tap each, and nothing is two levels
/// down:
///
///  * the three ways to say a meal — speak, type, photograph — as the kit's
///    pastel tiles;
///  * a packet: its barcode, or its nutrition table when no catalogue knows
///    it (a camera use, like a photo);
///  * "Repeat": the recent meals, one tap to log one again;
///  * water, a glass, a bottle or a tea;
///  * movement, the kind, then how long;
///  * and a way to ask Qamar anything, which is not logging.
///
/// Holding the orb (to talk) is said once, under the last row: the sheet
/// rises under the tab bar, so the moon it names is in view, and answers.
class LogSheet extends StatelessWidget {
  const LogSheet({super.key});

  /// Each part, for tests.
  static Key methodKey(QuickLog k) => ValueKey('log-method-${k.name}');
  static Key waterKey(WaterUnit u) => ValueKey('log-water-${u.name}');
  static Key activityKey(ActivityKind k) => ValueKey('log-activity-${k.name}');
  static const repeatKey = ValueKey('log-repeat');
  static const scanKey = ValueKey('log-scan');
  static const askKey = ValueKey('log-ask');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final problem = state.logProblem;
    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.closeLog,
        blur: 8,
        // Its foot runs on under the tab bar, which floats over it: the last
        // row ends above the bar's band.
        child: QSheetPanel(
          scrolls: true,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, QLayout.tabBand + 16),
          child: problem != null ? QStateCard(problem: problem) : _Choices(state: state),
        ),
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  final AppState state;
  const _Choices({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final photosLeft = state.photoQuota.remaining;
    final repeat = state.repeatChoices;
    final w = state.water;
    final litres = WaterStatus.qty(w.litres), goal = WaterStatus.qty(w.goalMl / 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isAr ? 'سجّل' : 'Log', style: QText.display(size: 24, ar: isAr)),
        const SizedBox(height: 2),
        Text(
          isAr
              ? 'الكتابة والصوت مجاناً بلا حد · باقي ${state.iso('$photosLeft')} صور النهارده'
              : 'Type or speak, unlimited · $photosLeft photos left today',
          style: QText.body(size: 13, color: QColors.inkSecondary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (final (i, m) in kLogMethods.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _MethodTile(
                  key: LogSheet.methodKey(m.kind),
                  method: m,
                  label: m.label(isAr),
                  locked: m.kind == QuickLog.photo && state.photoQuota.exhausted,
                  onTap: () => _run(context, state, m.kind),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _ScanRow(state: state),
        if (repeat.isNotEmpty) ...[
          const SizedBox(height: 20),
          // Named as the night note names it ("under Log → Repeat").
          _GroupTitle(isAr ? 'كرّر' : 'Repeat'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            key: LogSheet.repeatKey,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(children: [
              for (final (i, m) in repeat.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                _RepeatChip(name: m.name, onTap: () => state.repeatMeal(m)),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 20),
        // With nothing drunk yet, the goal alone: a lone Arabic zero is a
        // speck, not a figure.
        _GroupTitle(
          isAr ? 'الماء' : 'Water',
          trailing: w.litres <= 0
              ? (isAr ? 'هدفك ${state.iso(goal)} لتر' : 'Goal $goal L')
              : (isAr ? '${state.iso(litres)} من ${state.iso(goal)} لتر' : '$litres of $goal L'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final (i, c) in kWaterChoices.indexed) ...[
            if (i > 0) const SizedBox(width: 12),
            _RoundChoice(key: LogSheet.waterKey(c.unit), icon: c.icon, label: c.label(isAr), onTap: () => state.quickWater(c.unit)),
          ],
        ]),
        const SizedBox(height: 18),
        _GroupTitle(isAr ? 'حركة' : 'Movement'),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final c in kActivityChoices)
              _RoundChoice(key: LogSheet.activityKey(c.kind), icon: c.icon, label: c.label(isAr), onTap: () => state.chooseActivity(c.kind)),
          ],
        ),
        const SizedBox(height: 20),
        _AskRow(state: state),
      ],
    );
  }

  /// Runs a way to log. Photo opens the camera first; speak and type drop
  /// straight into the conversation. Nothing here pushes a screen, and
  /// nothing asks for Qamar+ — the server counts the photo and says so when
  /// today's are gone.
  static Future<void> _run(BuildContext context, AppState state, QuickLog kind) async {
    HapticFeedback.lightImpact();
    if (kind != QuickLog.photo) {
      state.quickLog(kind);
      return;
    }
    try {
      final shot = await pickCompressedPhoto(ImageSource.camera);
      if (!context.mounted) return;
      if (shot == null) {
        // Backed out of the camera: close up rather than logging nothing.
        state.closeLog();
        return;
      }
      state.quickLog(kind);
      state.logPhotoTaken(shot.path);
    } on Exception catch (e) {
      // No camera, or a refused permission: the sheet says so, with the way
      // on — Settings where the phone allows it, and typing the meal
      // instead — rather than quietly turning into a text box (O10).
      if (!context.mounted) return;
      state.cameraFailedInLog(e);
    }
  }
}

/// A group's name, with what it stands at on the other side.
class _GroupTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const _GroupTitle(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(text, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink))),
        if (trailing != null) Text(trailing!, style: QText.number(size: 13, color: QColors.inkSecondary)),
      ]);
}

/// A way to say a meal: a pastel tile, its glyph in a circle at the top and
/// its name at the foot, as the kit's macro cards are drawn.
class _MethodTile extends StatelessWidget {
  final LogMethod method;
  final String label;
  final bool locked;
  final VoidCallback onTap;
  const _MethodTile({super.key, required this.method, required this.label, required this.locked, required this.onTap});

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: onTap,
        label: label,
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: Container(
            height: 96,
            padding: const EdgeInsets.all(12),
            decoration: QDecor.pastel(method.color, radius: QRadii.inset),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.pastelTrack),
                      child: Center(child: QIcon(method.icon, size: 20, color: QColors.onPastel)),
                    ),
                    const Spacer(),
                    if (locked) const QIcon(QIcons.locked, size: 16, color: QColors.onPastel),
                  ]),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.onPastel)),
                ],
              ),
            ),
          ),
        ),
      );
}

/// A recent meal, as a chip: one tap logs it again with the same numbers.
class _RepeatChip extends StatelessWidget {
  final String name;
  final VoidCallback onTap;
  const _RepeatChip({required this.name, required this.onTap});

  /// A meal name short enough for a chip.
  static String short(String name) {
    final one = name.split(' + ').first.trim();
    return one.length <= 22 ? one : '${one.substring(0, 21)}…';
  }

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: QSurface(
            shape: QSurfaceShape.capsule,
            pressed: pressed,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 16, 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const QIcon(QIcons.repeat, size: 18, color: QColors.ink),
              const SizedBox(width: 8),
              Text(short(name), style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.ink)),
            ]),
          ),
        ),
      );
}

/// One tap's choice drawn as the kit's round button, its name under it; the
/// circle and the name are one control.
class _RoundChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundChoice({super.key, required this.icon, required this.label, required this.onTap});

  static const double size = 52;

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        label: label,
        builder: (context, pressed) => SizedBox(
          width: 60,
          child: ExcludeSemantics(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              qPressed(
                context,
                pressed: pressed,
                child: QSurface(
                  shape: QSurfaceShape.circle,
                  pressed: pressed,
                  width: size,
                  height: size,
                  child: Center(child: QIcon(icon, size: 22, color: QColors.ink)),
                ),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, textAlign: TextAlign.center, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.inkSecondary)),
            ]),
          ),
        ),
      );
}

/// A packet: the camera reads its barcode, and when no catalogue knows it,
/// the nutrition table on the back is photographed and read (scan_flow.dart).
/// A camera use, so it spends one of the day's photos, and shows the photo
/// tile's lock when they are gone; the server's answer then offers one more.
class _ScanRow extends StatelessWidget {
  final AppState state;
  const _ScanRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final locked = state.photoQuota.exhausted;
    return QTapArea(
      key: LogSheet.scanKey,
      onTap: () {
        HapticFeedback.lightImpact();
        startPacketScan(context, state);
      },
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: QSurface(
          pressed: pressed,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
          child: Row(children: [
            const QIcon(QIcons.barcode, size: 22, color: QColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'امسح علبة' : 'Scan a packet', style: QText.body(size: 16, weight: FontWeight.w500, color: QColors.ink)),
                Text(
                  isAr ? 'الباركود، أو جدول القيم الغذائية' : 'The barcode, or the nutrition table',
                  style: QText.body(size: 13, color: QColors.inkSecondary),
                ),
              ]),
            ),
            QIcon(locked ? QIcons.locked : QIcons.forward, size: 20, color: QColors.inkSecondary),
          ]),
        ),
      ),
    );
  }
}

/// Asking, not logging: the conversation, ready for typing. Under it, once,
/// the orb's hold.
class _AskRow extends StatelessWidget {
  final AppState state;
  const _AskRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return QTapArea(
      key: LogSheet.askKey,
      onTap: () {
        state.closeLog();
        state.openChat();
      },
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: QSurface(
          pressed: pressed,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
          child: Row(children: [
            const QIcon(QIcons.ask, size: 22, color: QColors.ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'اسأل قمر أي حاجة' : 'Ask Qamar anything', style: QText.body(size: 16, weight: FontWeight.w500, color: QColors.ink)),
                Text(
                  isAr ? 'أو استمر ضاغط على القمر وكلّمه' : 'or hold the moon to talk',
                  style: QText.body(size: 13, color: QColors.inkSecondary),
                ),
              ]),
            ),
            const QIcon(QIcons.forward, size: 20, color: QColors.inkSecondary),
          ]),
        ),
      ),
    );
  }
}
