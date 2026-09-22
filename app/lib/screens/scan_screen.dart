import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/photos.dart';
import '../models/problem.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _busy = false;

  /// Opens the device camera (or the photo library) for the InBody report.
  ///
  /// Anything that stops the picker — no camera on the device, a refused
  /// permission, an unsupported platform — is reported on screen rather than
  /// swallowed, and the flow still lets the user continue by typing, so a
  /// missing camera never dead-ends onboarding.
  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final shot = await pickCompressedPhoto(source);
      if (!mounted) return;
      // A null result means the user backed out of the camera — not an error.
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
    final photo = state.scanPhotoPath;

    return Container(
      color: QColors.bgScan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              children: [
                QBackButton(onTap: state.back, isAr: isAr),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.scanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                ),
                QLangToggle(lang: state.lang, onChanged: state.setLang),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: const Color(0xFF0D131F)),
                  ),
                  // Once a shot is taken, show it in the frame so the user can
                  // see what Qamar is reading.
                  if (photo != null && !kIsWeb)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.file(File(photo), fit: BoxFit.cover),
                      ),
                    ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: QColors.violet.withValues(alpha: 0.55), width: 2),
                        ),
                      ),
                    ),
                  ),
                  if (photo == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_busy ? Icons.hourglass_empty : Icons.photo_camera_outlined,
                              size: 34, color: QColors.textFaint),
                          const SizedBox(height: 10),
                          Text(
                            _busy
                                ? (isAr ? 'بفتح الكاميرا…' : 'Opening the camera…')
                                : (isAr ? 'اضغط الزرار عشان تفتح الكاميرا وتصوّر تقرير InBody' : 'Tap the button to open the camera and photograph your InBody report'),
                            textAlign: TextAlign.center,
                            style: QText.body(size: 13, height: 20, color: QColors.textFaint),
                          ),
                        ],
                      ),
                    ),
                  if (state.scanProblem != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: QStateCard(problem: state.scanProblem!),
                    ),
                  if (state.scanReading)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        color: const Color(0xD1050810),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _PulseDots(),
                            const SizedBox(height: 14),
                            Text(t.reading, style: QText.body(size: 14, color: QColors.textMid)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            child: Column(
              children: [
                Text(t.scanHint, style: QText.body(size: 13, color: QColors.textMuted)),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CircleAction(
                      icon: Icons.photo_library_outlined,
                      tooltip: isAr ? 'من الاستوديو' : 'From library',
                      onTap: _busy ? null : () => _pick(ImageSource.gallery),
                    ),
                    const SizedBox(width: 26),
                    GestureDetector(
                      onTap: _busy ? null : () => _pick(ImageSource.camera),
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: QColors.brandGradient,
                          border: Border.all(color: const Color(0xFF33415C), width: 3),
                          boxShadow: [
                            BoxShadow(color: QColors.blue.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Icon(
                          _busy ? Icons.more_horiz : Icons.photo_camera,
                          color: Colors.white.withValues(alpha: 0.92),
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 26),
                    _CircleAction(
                      icon: Icons.keyboard_outlined,
                      tooltip: isAr ? 'اكتب بدل التصوير' : 'Type instead',
                      onTap: state.startOnboarding,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: state.startOnboarding,
                  child: Text(t.typeInstead, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted)),
                ),
                Text(t.scanPriv, textAlign: TextAlign.center, style: QText.body(size: 11, height: 16, color: QColors.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _CircleAction({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: QColors.cardDeep,
              border: Border.all(color: QColors.borderSoft),
            ),
            child: Icon(icon, size: 20, color: onTap == null ? QColors.textFaint : QColors.textMid),
          ),
        ),
      ),
    );
  }
}

class _PulseDots extends StatefulWidget {
  const _PulseDots();
  @override
  State<_PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<_PulseDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value + i * 0.2) % 1.0;
            final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: opacity.clamp(0.3, 1.0),
                child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.violet)),
              ),
            );
          }),
        );
      },
    );
  }
}
