import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../models/ramadan.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

/// The seventh node, in season: the month's day, the fasting switch, iftar
/// and dawn from the sun, the night's water windows, the month's logging
/// against the 500-point bonus, and after Eid the report of what changed.
/// Free for everyone; nothing on this screen is Qamar+.
class RamadanScreen extends StatelessWidget {
  const RamadanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final season = state.season;
    final now = state.clockNow();
    final phase = state.seasonPhase;
    final day = season.dayOf(now);
    final until = season.daysUntil(now);
    final h = state.hydrationWindows;
    final nowMin = now.hour * 60 + now.minute;
    final open = h.current(nowMin);

    final String subtitle;
    if (phase == SeasonPhase.before && until != null) {
      subtitle = isAr ? 'أول يوم صيام بعد ${state.iso('$until')} ${until == 1 ? 'يوم' : 'أيام'}.' : 'The first fast is $until ${until == 1 ? 'day' : 'days'} away.';
    } else if (day != null) {
      subtitle = isAr ? 'اليوم ${state.iso('$day')} من ${state.iso('${season.days}')}' : 'Day $day of ${season.days}';
    } else {
      subtitle = isAr ? 'كل سنة وإنت طيب.' : 'Eid Mubarak.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Row(children: [
          const QamarMoon(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.digits(season.name(isAr)), style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
              Text(subtitle, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // The switch.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'صايم' : 'Fasting', style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                Text(
                  isAr
                      ? 'الخطة تبقى إفطار وسحور، والأسئلة على مواعيدهم، والمياه على نوافذ الليل.'
                      : 'The plan becomes iftar and suhoor, the questions move to their hours, and water to the night’s windows.',
                  style: QText.body(size: 12, height: 18, color: QColors.textMuted),
                ),
              ]),
            ),
            Switch.adaptive(
              value: state.profile.fasting == FastingMode.ramadan,
              activeThumbColor: QColors.gold,
              onChanged: (v) => state.setFasting(v),
            ),
          ]),
        ),
        const SizedBox(height: 14),

        // The sun's two times, and the water between them.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: _TimeCell(label: isAr ? 'الإفطار' : 'Iftar', time: state.iso(SunTimes.clock(h.iftarMin)), sub: isAr ? 'المغرب، القاهرة' : 'Sunset, Cairo')),
              Expanded(child: _TimeCell(label: isAr ? 'آخر السحور' : 'Suhoor ends', time: state.iso(SunTimes.clock(h.fajrMin)), sub: isAr ? 'الفجر، القاهرة' : 'Dawn, Cairo')),
            ]),
            const SizedBox(height: 14),
            Text(isAr ? 'المياه: ${state.iso('8')} كوبايات بين الإفطار والفجر' : 'Water: 8 glasses between iftar and dawn',
                style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textHigh)),
            const SizedBox(height: 6),
            for (final w in h.windows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(open == w ? Icons.water_drop : Icons.water_drop_outlined, size: 14, color: open == w ? QColors.cyan : QColors.textFaint),
                  const SizedBox(width: 8),
                  Expanded(child: Text(w.label(isAr), style: QText.body(size: 13, color: open == w ? QColors.textHigh : QColors.textMid))),
                  Text(
                    '${state.iso(SunTimes.clock(w.fromMin % (24 * 60)))}–${state.iso(SunTimes.clock(w.toMin % (24 * 60)))}',
                    textDirection: TextDirection.ltr,
                    style: QText.number(size: 12, color: QColors.textMuted),
                  ),
                  const SizedBox(width: 10),
                  Text(isAr ? '${state.iso('${w.glasses}')} كوبايات' : '${w.glasses} glasses', style: QText.number(size: 12, color: QColors.cyan)),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        // The month's log and its bonus.
        if (phase != SeasonPhase.before)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: QColors.gold.withValues(alpha: 0.08), border: Border.all(color: QColors.gold.withValues(alpha: 0.32)), borderRadius: BorderRadius.circular(QRadii.xl)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                isAr
                    ? 'سجّلت ${state.iso('${state.seasonDaysLogged}')} يوم من ${state.iso('${season.days}')}'
                    : 'Logged ${state.seasonDaysLogged} of ${season.days} days',
                style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFF2E4C6)),
              ),
              const SizedBox(height: 4),
              Text(
                isAr ? 'وجبة واحدة كل يوم من الشهر — ${state.iso('500')} نقطة Su لما يكمّل.' : 'One meal logged every day of the month — 500 Su when it is complete.',
                style: QText.body(size: 12, height: 18, color: const Color(0xFFB9A57C)),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (state.seasonDaysLogged / season.days).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: QColors.borderFaint,
                  valueColor: const AlwaysStoppedAnimation(QColors.gold),
                ),
              ),
            ]),
          ),

        // After Eid: what changed.
        if (phase == SeasonPhase.after) ...[
          const SizedBox(height: 14),
          _EidCard(state: state),
        ],
      ],
    );
  }
}

class _TimeCell extends StatelessWidget {
  final String label;
  final String time;
  final String sub;
  const _TimeCell({required this.label, required this.time, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: QText.body(size: 12, color: QColors.textMuted)),
      Text(time, textDirection: TextDirection.ltr, style: QText.number(size: 26, weight: FontWeight.w600, color: QColors.textPrimary)),
      Text(sub, style: QText.body(size: 11, color: QColors.textFaint)),
    ]);
  }
}

/// The month read back: days logged, the average against the target, the
/// scale, the longest run. Shareable as text. Then the blueprint's question,
/// at the standard price: keep the plan going?
class _EidCard extends StatelessWidget {
  final AppState state;
  const _EidCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final report = state.eidReport();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), border: QColors.borderStrong, radius: QRadii.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isAr ? 'تقرير العيد: إيه اللي اتغيّر في الشهر' : 'Eid report: what changed this month',
            style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
        const SizedBox(height: 8),
        for (final l in report.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(isAr ? l.ar : l.en, style: QText.body(size: 14, height: 21, color: QColors.textMid)),
          ),
        const SizedBox(height: 10),
        Row(children: [
          QOutlineButton(label: isAr ? 'شارك' : 'Share', height: 36, onTap: state.shareEidReport),
          const SizedBox(width: 10),
          if (!state.plusActive)
            Expanded(
              child: QOutlineButton(
                label: isAr ? 'كمّل الخطة؟ ${state.iso('500')} ج.م/شهر' : 'Keep the plan going? EGP 500/mo',
                height: 36,
                color: QColors.gold,
                onTap: () => state.go(AppScreen.subscription),
              ),
            ),
        ]),
      ]),
    );
  }
}
