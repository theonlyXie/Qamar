import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/problem.dart';
import '../services/photos.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/surface.dart';

/// The InBody report, photographed (the kit's AI Camera): the other way into
/// the consultation.
///
/// One job: take a photo of the report's first page. The kit's white shutter
/// is the one thing to do; beside it, as the kit's grey tiles, a photo
/// already on the phone and typing the numbers instead. The frame's white
/// corners say where the page goes, and once the shot is taken it shows what
/// Qamar is reading. When the camera will not open, the frame gives way to
/// what happened and the way on.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  /// The shutter, for tests.
  static const shutterKey = ValueKey('scan-shutter');

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _busy = false;

  /// Opens the device camera (or the photo library) for the InBody report.
  ///
  /// Anything that stops the picker (no camera on the device, a refused
  /// permission, an unsupported platform) is said on screen rather than
  /// swallowed, and the flow still lets the person carry on by typing, so a
  /// missing camera never dead-ends the consultation.
  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final shot = await pickCompressedPhoto(source);
      if (!mounted) return;
      // A null result means the person backed out of the camera: not an error.
      if (shot == null) return;
      state.setScanPhoto(shot.path);
      state.capture();
    } on Exception catch (e) {
      if (!mounted) return;
      // Said plainly, never as the exception's type, with the way on:
      // typing the numbers, and Settings where the phone allows it (O10).
      state.setScanProblem(state.cameraProblem(
        e,
        instead: ProblemAction(state.isAr ? 'اكتب أرقامك بدل كده' : 'Type your numbers instead', state.startOnboarding),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final problem = state.scanProblem;
    final reading = state.scanReading;
    final idle = !_busy && !reading;

    return ColoredBox(
      color: QColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: QSpace.page),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: problem != null
                    // What happened takes the frame's place: there is no
                    // camera to frame anything with.
                    ? QStateArea(key: const ValueKey('scan-problem'), child: QStateCard(problem: problem))
                    : _Frame(key: const ValueKey('scan-frame'), photo: state.scanPhotoPath, busy: _busy, reading: reading, state: state),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.xl, QSpace.page, QSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (problem == null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SideAction(
                        icon: QIcons.gallery,
                        label: isAr ? 'من الصور' : 'Photos',
                        onTap: idle ? () => _pick(ImageSource.gallery) : null,
                      ),
                      const SizedBox(width: QSpace.xl),
                      _Shutter(
                        label: isAr ? 'صوّر التقرير' : 'Photograph the report',
                        onTap: idle ? () => _pick(ImageSource.camera) : null,
                      ),
                      const SizedBox(width: QSpace.xl),
                      _SideAction(
                        icon: QIcons.keyboard,
                        label: isAr ? 'اكتبها' : 'Type it',
                        onTap: reading ? null : state.startOnboarding,
                      ),
                    ],
                  )
                else
                  // A photo already on the phone needs no camera.
                  Center(
                    child: QOutlineButton(
                      label: isAr ? 'اختار صورة من الموبايل' : 'Choose a photo instead',
                      icon: QIcons.gallery,
                      onTap: idle ? () => _pick(ImageSource.gallery) : null,
                    ),
                  ),
                const SizedBox(height: QSpace.lg),
                Text(t.scanPriv, textAlign: TextAlign.center, style: QText.body(size: 12, color: QColors.inkTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The way back, the screen's name beside it (the kit's "AI Camera"), and
/// the language at the end. At large text the name gives way to the two,
/// never the other way round.
class _Header extends StatelessWidget {
  final AppState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(QSpace.page, 6, QSpace.sm, QSpace.md),
      child: SizedBox(
        height: math.max(QLayout.minTap, MediaQuery.textScalerOf(context).scale(30)),
        child: Row(children: [
          QBackButton(onTap: state.back, isAr: state.isAr),
          const SizedBox(width: QSpace.md),
          Expanded(
            child: Text(
              state.t.scanTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QText.display(size: 20, ar: state.isAr),
            ),
          ),
          QLangToggle(lang: state.lang, onChanged: state.setLang),
        ]),
      ),
    );
  }
}

/// Where the page goes: a card with a viewfinder's four corners, and in it
/// what a photo gives, or the shot being read.
class _Frame extends StatelessWidget {
  final String? photo;
  final bool busy;
  final bool reading;
  final AppState state;
  const _Frame({super.key, required this.photo, required this.busy, required this.reading, required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final isAr = state.isAr;
    final shot = photo != null && !kIsWeb;
    return DecoratedBox(
      decoration: QDecor.card(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(QRadii.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The shot, once taken: what Qamar is reading.
            if (shot) Image.file(File(photo!), fit: BoxFit.cover),
            const Padding(padding: EdgeInsets.all(QSpace.xxl), child: CustomPaint(painter: _Corners())),
            // Before the shot, what a photo gives; once one is being read,
            // only the reading is said.
            if (!shot && !reading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      busy ? const _BreathingDot() : const QIcon(QIcons.scan, size: 32, color: QColors.inkSecondary),
                      const SizedBox(height: QSpace.md),
                      // Before the camera opens, what a photo gives.
                      Text(
                        busy ? (isAr ? 'بفتح الكاميرا…' : 'Opening the camera…') : t.scanInbodySub,
                        textAlign: TextAlign.center,
                        style: QText.body(size: 15, color: QColors.inkSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            // Reading: the shot dims, and one breathing dot says it is being
            // read, in words too.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: reading
                  ? ColoredBox(
                      key: const ValueKey('reading'),
                      color: QColors.scrim,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _BreathingDot(),
                            const SizedBox(height: QSpace.lg),
                            Text(t.reading, style: QText.body(size: 15, color: QColors.ink)),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('still')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A viewfinder's four corners round a page's shape (A4, as a report is
/// printed): where the page goes, drawn in the ink, with the inset corner at
/// each turn, centred in the frame.
class _Corners extends CustomPainter {
  const _Corners();

  /// A4's width over its height.
  static const page = 1 / 1.4142;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 40.0, r = QRadii.card;
    final paint = Paint()
      ..color = QColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    var w = size.width, h = w / page;
    if (h > size.height) {
      h = size.height;
      w = h * page;
    }
    canvas.translate((size.width - w) / 2, (size.height - h) / 2);
    Path corner(Offset a, Offset turn, Offset b) {
      final into = (turn - a) / (turn - a).distance;
      final out = (b - turn) / (b - turn).distance;
      return Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(turn.dx - into.dx * r, turn.dy - into.dy * r)
        ..quadraticBezierTo(turn.dx, turn.dy, turn.dx + out.dx * r, turn.dy + out.dy * r)
        ..lineTo(b.dx, b.dy);
    }

    for (final p in [
      corner(const Offset(0, arm), Offset.zero, const Offset(arm, 0)),
      corner(Offset(w - arm, 0), Offset(w, 0), Offset(w, arm)),
      corner(Offset(w, h - arm), Offset(w, h), Offset(w - arm, h)),
      corner(Offset(arm, h), Offset(0, h), Offset(0, h - arm)),
    ]) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_Corners old) => false;
}

/// The one white control, the kit's shutter: a white disc in a white ring.
/// With nothing to do (the camera is opening, the shot is being read) it
/// says so, grey, and takes no touch.
class _Shutter extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _Shutter({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      key: ScanScreen.shutterKey,
      label: label,
      onTap: onTap,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: enabled ? QColors.ink : QDisabled.fill, width: 3),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? (pressed ? QColors.inkSecondary : QColors.ink) : QDisabled.fill),
          ),
        ),
      ),
    );
  }
}

/// A way beside the shutter, the kit's grey tile: its glyph over its name,
/// one touch for both.
class _SideAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SideAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      onTap: onTap,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: QSurface(
          pressed: pressed,
          width: 92,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              QIcon(icon, size: 22, color: enabled ? QColors.ink : QDisabled.label),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 13, weight: FontWeight.w500, color: enabled ? QColors.ink : QDisabled.label)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Waiting, said by light: one white dot breathing on the conversation's
/// cycle. Under reduce-motion it holds still beside its words.
class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = Curves.easeInOut.transform(_c.value);
              return Transform.scale(
                scale: 0.72 + 0.28 * v,
                child: Opacity(
                  opacity: 0.55 + 0.45 * v,
                  child: const SizedBox(width: 14, height: 14, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: QColors.ink))),
                ),
              );
            },
          ),
        ),
      );
}
