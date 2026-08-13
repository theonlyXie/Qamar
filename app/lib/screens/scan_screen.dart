import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    return Container(
      color: QColors.bgScan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Row(
              children: [
                QRoundIconButton(icon: Icons.close, onTap: state.backToWelcome),
                const SizedBox(width: 12),
                Text(t.scanTitle, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
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
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: QColors.violet.withOpacity(0.55), width: 2),
                        ),
                      ),
                    ),
                  ),
                  Text('InBody report · camera preview', style: QText.number(size: 12, color: QColors.textFaint, letterSpacing: 0.4)),
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
                GestureDetector(
                  onTap: state.capture,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: QColors.brandGradient,
                      border: Border.all(color: const Color(0xFF33415C), width: 3),
                      boxShadow: [BoxShadow(color: QColors.blue.withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 8))],
                    ),
                  ),
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
