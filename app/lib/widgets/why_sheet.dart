import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

class WhySheet extends StatelessWidget {
  const WhySheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final p = state.profile;

    final rows = <(String, String)>[
      (t.whyFormula, t.whyFormulaVal),
      (
        t.whyAssume,
        state.isAr
            ? '${state.iso('${p.age}')} سنة · ${p.gender == Gender.female ? 'أنثى' : 'ذكر'} · ${state.iso('${p.height}')} سم · ${state.iso('${p.weight}')} كجم · معامل نشاط ${state.iso('${p.activity}')}'
            : '${p.age} yrs · ${p.gender == Gender.female ? 'female' : 'male'} · ${p.height} cm · ${p.weight} kg · activity factor ${p.activity}',
      ),
      (t.whySource, t.whySourceVal),
      (t.whyGuide, t.whyGuideVal),
      (t.whyVersion, state.iso('calc v2.0 · 2026-08-13')),
    ];

    return Positioned.fill(
      child: GestureDetector(
        onTap: state.closeWhy,
        child: Container(
          color: QColors.scrim,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 34),
              decoration: const BoxDecoration(
                color: QColors.cardSlate,
                border: Border(top: BorderSide(color: QColors.borderStrong)),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: QColors.borderStrong, borderRadius: BorderRadius.circular(999)))),
                  const SizedBox(height: 12),
                  Text(t.whyTitle, style: QText.display(size: 26, height: 32, color: QColors.textPrimary)),
                  for (final r in rows) ...[
                    const SizedBox(height: 11),
                    const Divider(color: QColors.borderFaint, height: 1),
                    const SizedBox(height: 11),
                    Text(r.$1, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
                    const SizedBox(height: 4),
                    Text(r.$2, style: QText.body(size: 14, height: 22, color: QColors.textHigh)),
                  ],
                  const SizedBox(height: 14),
                  QPrimaryButton(label: t.whyClose, onTap: state.closeWhy, height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
