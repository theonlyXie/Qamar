import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
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

  /// Its padding, its edge, the title and three lines of the sentence
  /// (14 + 14 + 2 + 24 + 3 × 22): the slot's 120, with nothing to spare.
  static const double maxHeight = 120;

  @override
  Widget build(BuildContext context) {
    if (!state.generalGuidance) return const SizedBox.shrink();
    final isAr = state.isAr;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: QDecor.card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.mint),
              child: const Center(child: QIcon(QIcons.safety, size: 18, color: QColors.onPastel)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isAr ? 'إرشاد عام' : 'General guidance', style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink)),
                  Text(
                    isAr
                        ? 'مفيش هدف سعرات في حالتك، ده شغل الأخصائي. سجّل أكلك وأقولك فيه إيه، واسألني أي سؤال عام.'
                        : 'No calorie target in your case; that’s for a professional. Log meals to see what’s in them, and ask me anything general.',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: QText.body(size: 15, color: QColors.inkSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
