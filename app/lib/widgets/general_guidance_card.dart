import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

/// Today on the general-guidance route, in place of the calorie card.
///
/// A safety answer in the consultation (pregnancy, breastfeeding, a chronic
/// condition under care) rules out a calorie target and a plan — those are
/// for a qualified professional — but not Qamar. So Today names no target
/// and says what is still here: logging a meal to see what is in it, and
/// general questions. [AppState.generalGuidance] says when it applies; it is
/// the "safety" card Today's one contextual slot ranks first.
class GeneralGuidanceCard extends StatelessWidget {
  final AppState state;
  const GeneralGuidanceCard({super.key, required this.state});

  static const double maxHeight = 120;

  @override
  Widget build(BuildContext context) {
    if (!state.generalGuidance) return const SizedBox.shrink();
    final isAr = state.isAr;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: QColors.cyan.withValues(alpha: 0.06),
          border: Border.all(color: QColors.cyan.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(QRadii.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.health_and_safety_outlined, size: 18, color: QColors.cyan),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: isAr ? 'إرشاد عام · ' : 'General guidance · ',
                    style: QText.body(size: 14, height: 21, weight: FontWeight.w600, color: QColors.cyan),
                  ),
                  TextSpan(
                    text: isAr
                        ? 'مفيش هدف سعرات في حالتك — ده للأخصائي. سجّل أكلك وأقولك فيه إيه، واسألني أي سؤال عام.'
                        : 'No calorie target in your case — that’s for a professional. Log meals to see what’s in them, and ask general questions.',
                  ),
                ]),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: QText.body(size: 14, height: 21, color: QColors.textHigh),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
