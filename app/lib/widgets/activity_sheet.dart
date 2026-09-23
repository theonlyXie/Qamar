import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/activity.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
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

    return Positioned.fill(
      child: QSheetScrim(
        onDismiss: state.cancelActivity,
        blur: 8,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: const BoxDecoration(
            gradient: QColors.sheet,
            border: Border(top: BorderSide(color: QColors.borderStrong)),
            borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAr ? '$name — قد إيه؟' : '$name — how long?',
                  style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textHigh)),
              const SizedBox(height: 4),
              Text(
                isAr ? 'تقدير على وزنك. بيتسجّل جنب الأكل.' : 'An estimate from your weight. Logged beside the food.',
                style: QText.body(size: 12, height: 18, color: QColors.textMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final m in ActivityCatalog.durations)
                    QOutlineButton(
                      label: isAr
                          ? '${state.iso('$m')} د · ~${state.iso('${ActivityCatalog.kcalFor(kind, m, state.profile.weight)}')}'
                          : '$m min · ~${ActivityCatalog.kcalFor(kind, m, state.profile.weight)}',
                      height: 38,
                      color: QColors.green,
                      onTap: () => state.logActivity(m),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: state.cancelActivity,
                  child: Text(isAr ? 'إلغاء' : 'Cancel', style: QText.body(size: 13, color: QColors.textMuted)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
