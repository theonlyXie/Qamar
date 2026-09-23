import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

class WhySheet extends StatelessWidget {
  const WhySheet({super.key});

  /// A code set left to right in either language, in its own order. The
  /// version line "calc v2.0 · 2026-08-13", in Arabic digits, drew as
  /// "calc v١٣-٠٨-٢٠٢٦ · ٢.٠": the bidi algorithm treats Arabic-Indic
  /// digits with the dots and hyphens between them as one right-to-left
  /// run, even inside iso()'s left-to-right isolate, so the version and
  /// the date swapped and the date read backwards. A left-to-right mark
  /// either side of every separator holds each run of digits in its place.
  static String inOrder(String code) => code.replaceAllMapped(RegExp('[^\u0660-\u06690-9\u2066\u2069]+'), (m) => '\u200E${m[0]}\u200E');

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
      (t.whyVersion, WhySheet.inOrder(state.iso('calc v2.0 · 2026-08-13'))),
    ];

    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.closeWhy,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 34),
          decoration: const BoxDecoration(
            color: QColors.surface,
            border: Border(top: BorderSide(color: QColors.hairlineStrong)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: QColors.hairlineStrong, borderRadius: BorderRadius.circular(QRadii.pill)))),
              const SizedBox(height: 12),
              Text(t.whyTitle, style: QText.display(size: 22, ar: QText.arabic(t.whyTitle), color: QColors.ink)),
              for (final r in rows) ...[
                const SizedBox(height: 11),
                const Divider(color: QColors.hairline, height: 1),
                const SizedBox(height: 11),
                Text(r.$1, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.inkTertiary)),
                const SizedBox(height: 4),
                Text(r.$2, style: QText.body(size: 15, height: 22, color: QColors.ink)),
              ],
              const SizedBox(height: 14),
              QPrimaryButton(label: t.whyClose, onTap: state.closeWhy, height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
