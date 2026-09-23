import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';

/// The third tap of the activity quick-log: how long. Five chips, each with
/// the estimate it would write, so the number is never a surprise on the
/// card.
class ActivitySheet extends StatefulWidget {
  const ActivitySheet({super.key});

  @override
  State<ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<ActivitySheet> {
  /// The activity, held while the sheet leaves (QSheetSlot): by then the
  /// state has let it go.
  ActivityKind? _last;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final kind = state.pendingActivity ?? _last;
    _last = kind;
    if (kind == null) return const SizedBox.shrink();
    final name = ActivityCatalog.label(kind, ar: isAr);

    // One question, answered in one tap: each length is a button that logs
    // it, with the estimate it will write, so nothing on the card surprises.
    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.cancelActivity,
        child: QSheetPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAr ? '$name، قد إيه؟' : '$name, how long?', style: QText.display(size: 22, ar: isAr, color: QColors.ink)),
              const SizedBox(height: 6),
              Text(
                isAr ? 'تقدير على وزنك. بيتسجّل جنب الأكل.' : 'An estimate from your weight, logged beside the food.',
                style: QText.body(size: 15, color: QColors.inkSecondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in ActivityCatalog.durations)
                    QOutlineButton(
                      label: isAr
                          ? '${state.iso('$m')} د، ${state.iso('${ActivityCatalog.kcalFor(kind, m, state.profile.weight)}')} سعر'
                          : '$m min · ${ActivityCatalog.kcalFor(kind, m, state.profile.weight)} kcal',
                      height: 44,
                      onTap: () => state.logActivity(m),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: QTapArea(
                  onTap: state.cancelActivity,
                  builder: (context, pressed) => qPressed(
                    context,
                    pressed: pressed,
                    child: Text(isAr ? 'إلغاء' : 'Cancel', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
