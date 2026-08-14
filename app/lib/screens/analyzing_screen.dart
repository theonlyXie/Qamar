import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class AnalyzingScreen extends StatelessWidget {
  const AnalyzingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final steps = [
      (label: state.isAr ? 'قراءة المصدر' : 'Reading the source', done: true),
      (label: state.isAr ? 'مطابقة الأكل المصري' : 'Matching Egyptian dishes', done: false),
      (label: state.isAr ? 'تقدير الكمية والقيم' : 'Estimating portion and values', done: false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
            children: [
              Text(t.analyzing, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
              const SizedBox(height: 16),
              Container(
                height: 150,
                alignment: Alignment.center,
                decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.xl),
                child: Text(t.sourcePreview, style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textFaint, letterSpacing: 1.4)),
              ),
              const SizedBox(height: 16),
              for (final s in steps) ...[
                Row(children: [
                  if (s.done)
                    Container(width: 16, height: 16, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.green))
                  else
                    const _PulseRing(),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.label, style: QText.body(size: 14, color: QColors.textMid))),
                ]),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              const _Skeleton(),
              const SizedBox(height: 10),
              const _Skeleton(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          child: QOutlineButton(label: t.cancel, onTap: () => state.go(AppScreen.today), height: 48),
        ),
      ],
    );
  }
}

class _Skeleton extends StatefulWidget {
  const _Skeleton();
  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.5 + 0.5 * _c.value,
        child: Container(height: 70, decoration: BoxDecoration(color: QColors.cardDeep, borderRadius: BorderRadius.circular(QRadii.lg))),
      ),
    );
  }
}

class _PulseRing extends StatefulWidget {
  const _PulseRing();
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: 0.3 + 0.7 * _c.value,
        child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: QColors.borderStep, width: 2))),
      ),
    );
  }
}
