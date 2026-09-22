import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'hold_coach_mark.dart';

/// The moon's three gestures, each ticked once the person has done it.
///
/// The same card in two places. On Today it is the tutorial: it holds the
/// one contextual slot until the first hold, and can be put away with "Got
/// it". In Me it is the help, and it stays for good, so a gesture
/// forgotten after the tutorial is gone can always be looked up again.
class OrbGestureGuide extends StatelessWidget {
  final AppState state;

  /// On Today, "Got it" puts it away; in Me there is nothing to put away.
  final bool dismissible;
  const OrbGestureGuide({super.key, required this.state, this.dismissible = true});

  /// The card's rows, in the order they are learned: tap, hold, drag. The
  /// hold row is the hold mark's own words (HoldCopy), so the two never
  /// drift apart.
  static List<(OrbGesture, IconData, String, String, String, String)> rows() => [
        (OrbGesture.tap, Icons.touch_app_outlined, 'دوس على القمر', 'Tap the moon', 'تفتح الشجرة: سجّل · الخطة · مياه · المراجعة · حسابي', 'opens the tree: Log · Plan · Water · Review · Me'),
        (OrbGesture.hold, Icons.mic_none, HoldCopy.doAr, HoldCopy.doEn, HoldCopy.whatAr, HoldCopy.whatEn),
        // The explainable numbers carry a dotted line under them (ExplainMark).
        (OrbGesture.explain, Icons.open_with, 'اسحبه على رقم تحته نقط', 'Drag it onto a dotted number', 'يشرحه لك: من فين جه وإيه معناه', 'and it explains itself: where it came from, what it means'),
      ];

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final learned = state.gesturesLearned;
    final photos = state.photoQuota.limit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: QColors.violet.withValues(alpha: 0.08),
        border: Border.all(color: QColors.violet.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(QRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAr ? 'القمر بيفهم تلات حركات' : 'The moon knows three gestures',
                  style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.violetSoft, letterSpacing: 0.3),
                ),
              ),
              if (dismissible)
                // Small words, a full 48-point touch.
                Semantics(
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(QRadii.md),
                    onTap: state.dismissOrbTutorial,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      child: Center(
                        widthFactor: 1,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(isAr ? 'عارف' : 'Got it', style: QText.body(size: 12, color: QColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: dismissible ? 0 : 8),
          for (final (g, icon, doAr, doEn, whatAr, whatEn) in rows()) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    learned.contains(g) ? Icons.check_circle : icon,
                    size: 16,
                    color: learned.contains(g) ? QColors.green : QColors.violetSoft,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${isAr ? doAr : doEn} — ${isAr ? whatAr : whatEn}',
                      style: QText.body(size: 12, height: 18, color: learned.contains(g) ? QColors.textMuted : QColors.textMid),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'الكتابة والصوت ببلاش على طول. الصور ${state.iso('$photos')} في اليوم.'
                : 'Typing and speaking are always free. Photos, $photos a day.',
            style: QText.body(size: 11, height: 16, color: QColors.textFaint),
          ),
        ],
      ),
    );
  }
}
