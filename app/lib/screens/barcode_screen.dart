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
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/colors.dart';
import '../theme/text_styles.dart';

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key, required this.isAr});

  final bool isAr;

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
  static bool _plausible(String digits) =>
      digits.length == 8 || digits.length == 12 || digits.length == 13 || digits.length == 14;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      if (!_plausible(digits)) continue;

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
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _TypeCodeDialog(isAr: _isAr),
    );
    if (!mounted || code == null) return;
    Navigator.of(context).pop(code);
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
      backgroundColor: QColors.bgScan,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            // The reader ignores everything outside the drawn window, so what
            // the person aims at is what gets read.
            scanWindow: window,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraProblem(
              isAr: _isAr,
              detail: error.errorDetails?.message,
              onType: _typeItInstead,
            ),
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
            left: 0,
            right: 0,
            top: window.bottom + 24,
            child: Column(
              children: [
                Text(
                  _isAr ? 'حط الباركود جوه الإطار' : 'Line the barcode up inside the frame',
                  textAlign: TextAlign.center,
                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  _isAr
                      ? 'هيتقرا لوحده أول ما يبان واضح.'
                      : 'It reads on its own as soon as it is sharp.',
                  textAlign: TextAlign.center,
                  style: QText.body(size: 13, color: QColors.textMuted),
                ),
                if (_problem != null) ...[
                  const SizedBox(height: 10),
                  Text(_problem!,
                      textAlign: TextAlign.center,
                      style: QText.body(size: 13, color: QColors.amber)),
                ],
              ],
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundAction(
                    icon: Icons.close,
                    label: _isAr ? 'إلغاء' : 'Cancel',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  _RoundAction(
                    icon: _torch ? Icons.flashlight_on : Icons.flashlight_off,
                    label: _isAr ? 'الكشاف' : 'Torch',
                    onTap: () async {
                      try {
                        await _controller.toggleTorch();
                        if (mounted) setState(() => _torch = !_torch);
                      } on Exception {
                        // Plenty of front cameras and emulators have no torch.
                        // Saying so beats a button that silently does nothing.
                        if (mounted) {
                          setState(() => _problem =
                              _isAr ? 'الجهاز ده مفيهوش كشاف.' : 'This device has no torch.');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: TextButton(
                onPressed: _typeItInstead,
                child: Text(
                  _isAr ? 'الباركود مش راضي يتقرا؟ اكتب الأرقام' : 'Will not read? Type the digits',
                  style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.violetSoft),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dims the frame except for the scan window, and marks its corners.
class _WindowPainter extends CustomPainter {
  const _WindowPainter({required this.window});

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(14));

    // Dim everything, then punch the window out of it, so the bright area is
    // exactly the area the reader is looking at rather than near it.
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xB3000000));
    canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    final edge = Paint()
      ..color = QColors.violetSoft
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
        ..color = QColors.violetSoft.withOpacity(0.35)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0x66000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: QColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Shown when the camera itself will not start — permission refused, no camera,
/// or another app holding it. The typed fallback is offered here too, because
/// this is precisely the moment somebody is stuck holding a packet.
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.isAr, required this.detail, required this.onType});

  final bool isAr;
  final String? detail;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: QColors.textMuted, size: 40),
            const SizedBox(height: 14),
            Text(
              isAr ? 'مقدرتش أفتح الكاميرا.' : 'I could not open the camera.',
              textAlign: TextAlign.center,
              style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              isAr
                  ? 'اسمحلي بالكاميرا من إعدادات التليفون، أو اكتب أرقام الباركود.'
                  : 'Allow camera access in your phone settings, or type the barcode digits.',
              textAlign: TextAlign.center,
              style: QText.body(size: 13, color: QColors.textMuted),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: QText.body(size: 11, color: QColors.textFaint)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onType,
              child: Text(isAr ? 'اكتب الأرقام' : 'Type the digits'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCodeDialog extends StatefulWidget {
  const _TypeCodeDialog({required this.isAr});

  final bool isAr;

  @override
  State<_TypeCodeDialog> createState() => _TypeCodeDialogState();
}

class _TypeCodeDialogState extends State<_TypeCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final digits = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (!_BarcodeScreenState._plausible(digits)) {
      setState(() => _error = widget.isAr
          ? 'الباركود بيبقى ٨ أو ١٢ أو ١٣ رقم.'
          : 'A barcode is 8, 12 or 13 digits.');
      return;
    }
    Navigator.of(context).pop(digits);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return AlertDialog(
      backgroundColor: QColors.cardDeep,
      title: Text(isAr ? 'اكتب الباركود' : 'Type the barcode',
          style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textPrimary)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        // Latin digits regardless of app language: the numbers are printed
        // under the bars in Latin digits on every packet in the world.
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
        style: QText.number(size: 18, color: QColors.textPrimary),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          hintText: '6221033000011',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(isAr ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isAr ? 'دور عليه' : 'Look it up'),
        ),
      ],
    );
  }
}
