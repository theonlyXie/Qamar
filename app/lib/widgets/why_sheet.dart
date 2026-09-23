import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../state/app_state.dart';
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
            // "،" where English has "·": beside Arabic digits a middle dot
            // reads as a zero.
            ? '${state.iso('${p.age}')} سنة، ${p.gender == Gender.female ? 'أنثى' : 'ذكر'}، ${state.iso('${p.height}')} سم، ${state.iso('${p.weight}')} كجم، نشاط ${state.iso('${p.activity}')}'
            : '${p.age} years · ${p.gender == Gender.female ? 'female' : 'male'} · ${p.height} cm · ${p.weight} kg · activity ${p.activity}',
      ),
      (t.whySource, t.whySourceVal),
      (t.whyGuide, t.whyGuideVal),
    ];

    // Plain words first, the working after: four short rows, each a label
    // over its line, and the calculation's version as a footnote at the end,
    // where it can be quoted and need never be read.
    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.closeWhy,
        child: QSheetPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.whyTitle, style: QText.display(size: 22, ar: QText.arabic(t.whyTitle), color: QColors.ink)),
              const SizedBox(height: 8),
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(color: QColors.hairline, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(QText.eyebrowText(r.$1, ar: state.isAr), style: QText.eyebrow(ar: state.isAr)),
                    const SizedBox(height: 4),
                    Text(r.$2, style: QText.body(size: 15, color: QColors.ink)),
                  ]),
                ),
              ],
              Text(
                WhySheet.inOrder(state.iso('calc v2.0 · 2026-08-13')),
                semanticsLabel: '${t.whyVersion}: calc v2.0, 2026-08-13',
                style: QText.body(size: 12, color: QColors.inkTertiary),
              ),
              const SizedBox(height: 16),
              QPrimaryButton(label: t.whyClose, onTap: state.closeWhy),
            ],
          ),
        ),
      ),
    );
  }
}
