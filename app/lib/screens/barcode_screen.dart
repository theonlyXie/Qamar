/// Point the camera at the code on a packet.
///
/// This is a full-screen camera with one job, and it is deliberately fussy
/// about alignment. A barcode read from the wrong packet is not a near miss —
/// it is confidently wrong nutrition attached to a food nobody ate, and the
/// person has no way to tell. So the reader is restricted to the window drawn
/// on screen rather than accepting anything anywhere in frame, and the window
/// is drawn where it actually is rather than approximately.
///
/// Returns the digits through Navigator.pop, or null if the user backed out.
/// Nothing here talks to the gateway; the caller does that, so this screen
/// stays a camera and not a second place where scanning logic lives.
///
/// Drawn the qamar-design way: the controls over the camera are the clear
/// surfaces ([QSurface.clear]), the words are the inks, and the frame is
/// white brackets; no colour means anything here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/surface.dart';

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key, required this.isAr});

  final bool isAr;

  /// Its controls, for tests.
  static const closeKey = ValueKey('barcode-close');
  static const torchKey = ValueKey('barcode-torch');
  static const typeKey = ValueKey('barcode-type');

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  /// The formats actually printed on food packaging. Restricting the list is
  /// not tidiness — every extra symbology is another way to misread a smudged
  /// label as a valid code of some other kind.
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );

  /// Set the moment a code is accepted. Detection keeps firing for a frame or
  /// two after that, and popping twice tears the navigator.
  bool _done = false;
  bool _torch = false;
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isAr => widget.isAr;

  /// EAN-13, EAN-8, UPC-A and UPC-E, by length after stripping non-digits.
  ///
  /// The check digit is not verified here. The scanner's own decoder already
  /// validates it — that is what makes a barcode a barcode rather than a
  /// picture of stripes — and re-implementing the modulo would only add a
  /// second place to get it wrong.
  static bool plausible(String digits) =>
      digits.length == 8 || digits.length == 12 || digits.length == 13 || digits.length == 14;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (!plausible(digits)) continue;

      _done = true;
      HapticFeedback.mediumImpact();
      unawaited(_controller.stop());
      Navigator.of(context).pop(digits);
      return;
    }
  }

  Future<void> _typeItInstead() async {
    // Barcodes get scuffed, torn and printed badly, and a person holding a
    // packet they cannot scan should not be stuck. The digits are printed
    // under the bars for exactly this reason.
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: QColors.scrim,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet))),
      builder: (_) => _TypeCodeSheet(isAr: _isAr),
    );
    if (!mounted || code == null) return;
    Navigator.of(context).pop(code);
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torch = !_torch);
    } on Exception {
      // Plenty of front cameras and emulators have no torch. Saying so beats
      // a button that silently does nothing.
      if (mounted) setState(() => _problem = _isAr ? 'الجهاز ده مفيهوش كشاف.' : 'This device has no torch.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // A barcode is much wider than it is tall, so the window is too. A square
    // reticle invites people to centre the packet rather than the code.
    final w = size.width * 0.78;
    final h = w * 0.42;
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: w,
      height: h,
    );

    return Scaffold(
      backgroundColor: QColors.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            // The reader ignores everything outside the drawn window, so what
            // the person aims at is what gets read.
            scanWindow: window,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              debugPrint('barcode camera: $error');
              return _CameraProblem(isAr: _isAr, onType: _typeItInstead);
            },
          ),

          // Everything outside the window is dimmed, which is the whole of the
          // alignment instruction: the bright rectangle is where the code goes.
          IgnorePointer(
            child: CustomPaint(
              painter: _WindowPainter(window: window),
              size: Size.infinite,
            ),
          ),

          Positioned(
            left: QSpace.page,
            right: QSpace.page,
            top: window.bottom + QSpace.xl,
            child: Column(
              children: [
                Text(
                  _isAr ? 'حط الباركود جوه الإطار' : 'Line the barcode up inside the frame',
                  textAlign: TextAlign.center,
                  style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink),
                ),
                const SizedBox(height: QSpace.xs),
                Text(
                  _isAr ? 'هيتقرا لوحده أول ما يبان واضح.' : 'It reads on its own as soon as it is sharp.',
                  textAlign: TextAlign.center,
                  style: QText.body(size: 15, color: QColors.inkSecondary),
                ),
                if (_problem != null) ...[
                  const SizedBox(height: QSpace.md),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const QIcon(QIcons.warning, size: 18, color: QColors.ink),
                    const SizedBox(width: QSpace.sm),
                    Flexible(child: Text(_problem!, style: QText.body(size: 15, color: QColors.ink))),
                  ]),
                ],
              ],
            ),
          ),

          // Pinned to the top: a bare child of an expanded Stack is given the
          // whole screen, and a Row that tall centres its controls in it.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: QSpace.md, vertical: QSpace.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CameraControl(
                      key: BarcodeScreen.closeKey,
                      icon: QIcons.close,
                      label: _isAr ? 'اقفل' : 'Close',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _CameraControl(
                      key: BarcodeScreen.torchKey,
                      icon: _torch ? QIcons.torchOn : QIcons.torch,
                      label: _isAr ? 'الكشاف' : 'Torch',
                      selected: _torch,
                      onTap: _toggleTorch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: QSpace.xl,
            child: SafeArea(
              top: false,
              child: Center(
                child: QTapArea(
                  key: BarcodeScreen.typeKey,
                  onTap: _typeItInstead,
                  builder: (context, pressed) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: QSpace.lg),
                    child: Text(
                      _isAr ? 'الباركود مش راضي يتقرا؟ اكتب الأرقام' : 'Will not read? Type the digits',
                      style: QText.body(size: 15, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A round control over the camera: the clear surface, so the picture still
/// shows round it, with its glyph bold while it is on.
class _CameraControl extends StatelessWidget {
  const _CameraControl({super.key, required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: QTapArea(
          onTap: onTap,
          label: label,
          builder: (context, pressed) => qPressed(
            context,
            pressed: pressed,
            child: QSurface(
              shape: QSurfaceShape.circle,
              clear: true,
              pressed: pressed,
              width: 44,
              height: 44,
              child: Center(child: QIcon(icon, size: 22, color: QColors.ink)),
            ),
          ),
        ),
      );
}

/// Dims the frame except for the scan window, and marks its corners.
class _WindowPainter extends CustomPainter {
  const _WindowPainter({required this.window});

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(QRadii.inset));

    // Dim everything, then punch the window out of it, so the bright area is
    // exactly the area the reader is looking at rather than near it.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = QColors.overPhotoPressed);
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    final edge = Paint()
      ..color = QColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Corner brackets rather than a full outline: a closed rectangle reads as
    // a frame to fill, brackets read as an area to line something up in.
    const arm = 22.0;
    final r = window;
    for (final (Offset from, Offset to) in [
      (r.topLeft.translate(0, arm), r.topLeft),
      (r.topLeft, r.topLeft.translate(arm, 0)),
      (r.topRight.translate(-arm, 0), r.topRight),
      (r.topRight, r.topRight.translate(0, arm)),
      (r.bottomLeft.translate(0, -arm), r.bottomLeft),
      (r.bottomLeft, r.bottomLeft.translate(arm, 0)),
      (r.bottomRight.translate(-arm, 0), r.bottomRight),
      (r.bottomRight, r.bottomRight.translate(0, -arm)),
    ]) {
      canvas.drawLine(from, to, edge);
    }

    // A guide line down the middle. Barcodes are read across, and this is the
    // line the stripes should cross.
    canvas.drawLine(
      Offset(r.left + 12, r.center.dy),
      Offset(r.right - 12, r.center.dy),
      Paint()
        ..color = QColors.ink.withValues(alpha: 0.35)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

/// Shown when the camera itself will not start — permission refused, no camera,
/// or another app holding it. The typed fallback is offered here too, because
/// this is precisely the moment somebody is stuck holding a packet. What the
/// plugin said goes to the debug log, never onto the screen.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.isAr, required this.onType});

  final bool isAr;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: QColors.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: QSpace.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: QIcon(QIcons.camera, size: 40, color: QColors.inkSecondary)),
              const SizedBox(height: QSpace.lg),
              Text(
                isAr ? 'مقدرتش أفتح الكاميرا.' : 'I could not open the camera.',
                textAlign: TextAlign.center,
                style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink),
              ),
              const SizedBox(height: QSpace.sm),
              Text(
                isAr
                    ? 'اسمحلي بالكاميرا من إعدادات التليفون، أو اكتب أرقام الباركود.'
                    : 'Allow camera access in your phone settings, or type the barcode digits.',
                textAlign: TextAlign.center,
                style: QText.body(size: 15, color: QColors.inkSecondary),
              ),
              const SizedBox(height: QSpace.xl),
              QPrimaryButton(label: isAr ? 'اكتب الأرقام' : 'Type the digits', icon: QIcons.keyboard, onTap: onType),
            ],
          ),
        ),
      ),
    );
  }
}

/// The digits under the bars, typed: one field and one button, the way the
/// welcome asks for an invitation code.
class _TypeCodeSheet extends StatefulWidget {
  const _TypeCodeSheet({required this.isAr});

  final bool isAr;

  @override
  State<_TypeCodeSheet> createState() => _TypeCodeSheetState();
}

class _TypeCodeSheetState extends State<_TypeCodeSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (!_BarcodeScreenState.plausible(digits)) {
      setState(() => _error = widget.isAr ? 'الباركود بيبقى ٨ أو ١٢ أو ١٣ رقم.' : 'A barcode is 8, 12 or 13 digits.');
      return;
    }
    Navigator.of(context).pop(digits);
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    return Padding(
      // Above the keyboard, which the field opens with.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: QSheetSurface(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.md, QSpace.page, QSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: QSheetGrabber()),
                const SizedBox(height: QSpace.sm),
                Row(children: [
                  QRoundIconButton(icon: QIcons.close, onTap: () => Navigator.of(context).pop(), label: ar ? 'اقفل' : 'Close'),
                  const SizedBox(width: QSpace.xs),
                  Expanded(child: Text(ar ? 'اكتب الباركود' : 'Type the barcode', style: QText.display(size: 24, ar: ar))),
                ]),
                const SizedBox(height: QSpace.lg),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  // Latin digits whatever the app's language: they are printed
                  // under the bars in Latin digits on every packet in the world.
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  style: QText.number(size: 17),
                  decoration: InputDecoration(
                    hintText: '6221033000011',
                    hintTextDirection: TextDirection.ltr,
                    hintStyle: QText.number(size: 17, color: QColors.inkTertiary),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: QSpace.md),
                  QStateLine(line: _error!, icon: QIcons.warning),
                ],
                const SizedBox(height: QSpace.lg),
                QPrimaryButton(label: ar ? 'دوّر عليه' : 'Look it up', onTap: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
