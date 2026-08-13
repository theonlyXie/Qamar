import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/living_orb.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: SizedBox(
                width: 300,
                height: 300,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    LivingOrb(size: 132, wander: true, wanderDuration: const Duration(milliseconds: 9000), haloDuration: const Duration(milliseconds: 7000)),
                    Positioned(
                      top: 14,
                      left: -4,
                      child: _FloatingPill(
                        label: t.chatDirect,
                        dot: QColors.violet,
                        onTap: state.startOnboarding,
                        emphasis: true,
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: -6,
                      child: _FloatingPill(
                        label: t.scanInbody,
                        dot: null,
                        onTap: state.openScan,
                        emphasis: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.brand, style: QText.display(size: 40, height: 48, color: const Color(0xFFF5F7FF))),
              const SizedBox(height: 8),
              Text(t.promise, style: QText.body(size: 16, height: 24, color: QColors.textMid)),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(t.continueWith, style: QText.body(size: 12, color: QColors.textFaint)),
                  ),
                  const Expanded(child: Divider(color: QColors.borderFaint, height: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _ProviderButton(label: 'Apple', mark: '●', color: QColors.providerApple, onTap: state.startOnboarding)),
                  const SizedBox(width: 10),
                  Expanded(child: _ProviderButton(label: 'Google', mark: 'G', color: QColors.providerGoogle, onTap: state.startOnboarding)),
                  const SizedBox(width: 10),
                  Expanded(child: _ProviderButton(label: 'Facebook', mark: 'f', color: QColors.providerFacebook, onTap: state.startOnboarding)),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 38,
                child: TextButton(
                  onPressed: () {},
                  child: Text(t.haveAccount, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted)),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    t.boundary,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 11, height: 17, color: QColors.textFaint),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FloatingPill extends StatelessWidget {
  final String label;
  final Color? dot;
  final VoidCallback onTap;
  final bool emphasis;
  const _FloatingPill({required this.label, required this.dot, required this.onTap, required this.emphasis});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: emphasis ? const Color(0xD1141C2E) : const Color(0xDB111827),
            border: Border.all(color: emphasis ? QColors.violet.withOpacity(0.5) : QColors.borderSoft),
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [BoxShadow(color: Color(0x8005080F), blurRadius: 30, offset: Offset(0, 12))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
                const SizedBox(width: 9),
              ] else ...[
                Container(width: 12, height: 12, decoration: BoxDecoration(border: Border.all(color: QColors.cyan, width: 2), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 9),
              ],
              Text(label, style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFF1F5FF))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  final String label;
  final String mark;
  final Color color;
  final VoidCallback onTap;
  const _ProviderButton({required this.label, required this.mark, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: QColors.borderSoft),
          backgroundColor: QColors.cardDeep,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(mark, style: QText.number(size: 16, weight: FontWeight.w700, color: color)),
            const SizedBox(width: 8),
            Text(label, style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textHigh)),
          ],
        ),
      ),
    );
  }
}
