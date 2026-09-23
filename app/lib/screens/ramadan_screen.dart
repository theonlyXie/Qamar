import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/words.dart';
import '../models/billing.dart';
import '../models/profile.dart';
import '../models/ramadan.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/hero_number.dart';

/// Glasses counted as each language counts them: كوباية واحدة، كوبايتين،
/// ٣ كوبايات، ١١ كوباية.
const _glass = Counted(en: 'glass', enPlural: 'glasses', arOne: 'كوباية واحدة', arTwo: 'كوبايتين', arFew: 'كوبايات', arMany: 'كوباية');

/// The seventh node, in season: the next time that matters (iftar by day,
/// the end of suhoor by night), the fasting switch, the night's water, the
/// month's logging, and after Eid the report of what changed. Free for
/// everyone; nothing on this screen is Qamar+.
class RamadanScreen extends StatelessWidget {
  const RamadanScreen({super.key});

  /// The next time, and the fasting row, for tests.
  static const nextKey = ValueKey('ramadan-next');
  static const fastingKey = ValueKey('ramadan-fasting');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final season = state.season;
    final now = state.clockNow();
    final phase = state.seasonPhase;
    final day = season.dayOf(now);
    final until = season.daysUntil(now);

    final String subtitle;
    if (phase == SeasonPhase.before && until != null) {
      subtitle = isAr
          ? 'أول يوم صيام بعد ${Counted.day.of(until, ar: true, iso: state.iso)}.'
          : 'The first fast is ${Counted.day.of(until, ar: false, iso: state.iso)} away.';
    } else if (day != null) {
      subtitle = isAr ? 'اليوم ${state.iso('$day')} من ${state.iso('${season.days}')}' : 'Day $day of ${season.days}';
    } else {
      subtitle = isAr ? 'كل سنة وإنت طيب.' : 'Eid Mubarak.';
    }

    // After Eid there is nothing to fast or drink by, and a switch there
    // would do nothing: the month read back is the screen.
    final eid = phase == SeasonPhase.after;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        Row(children: [
          // The way back (the exit rule), where every screen keeps it.
          QBackButton(onTap: state.back, isAr: isAr),
          const SizedBox(width: 8),
          Expanded(child: Text(state.digits(season.name(isAr)), style: QText.display(size: 34, ar: isAr))),
        ]),
        const SizedBox(height: 4),
        Text(subtitle, style: QText.body(size: 15, color: QColors.inkSecondary)),
        const SizedBox(height: 20),
        if (eid)
          _EidCard(state: state)
        else ...[
          _NextTime(state: state),
          const SizedBox(height: 14),
          _FastingRow(state: state),
          // The switch flipped but today's plan could not follow it (O10):
          // said here, under the switch, with the Plan card's way on.
          if (state.fastingNotYet case final n?) ...[
            const SizedBox(height: 8),
            QStateLine(line: n.line, action: n.action, icon: QIcons.moon),
          ],
          const SizedBox(height: 14),
          _WaterCard(state: state),
          if (phase != SeasonPhase.before) ...[
            const SizedBox(height: 14),
            _MonthCard(state: state),
          ],
        ],
      ],
    );
  }
}

/// The screen's one figure: the next of the day's two times, from the sun
/// over Cairo. By day it is iftar; from sunset to dawn, the end of suhoor.
/// The other is said under it.
class _NextTime extends StatelessWidget {
  final AppState state;
  const _NextTime({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final h = state.hydrationWindows;
    final now = state.clockNow();
    final byDay = h.fastingAt(now.hour * 60 + now.minute);
    final iftar = SunTimes.clock(h.iftarMin);
    final dawn = SunTimes.clock(h.fajrMin);
    final label = byDay ? (isAr ? 'الإفطار' : 'Iftar') : (isAr ? 'آخر السحور' : 'Suhoor ends');
    final time = state.digits(byDay ? iftar : dawn);
    final where = byDay ? (isAr ? 'المغرب في القاهرة' : 'Sunset in Cairo') : (isAr ? 'الفجر في القاهرة' : 'Dawn in Cairo');
    // Arabic joins the two with its own comma and "and": a "·" there reads
    // as a zero.
    final other = byDay
        ? (isAr ? 'وآخر السحور ${state.iso(dawn)}' : 'Suhoor ends $dawn')
        : (isAr ? 'والإفطار ${state.iso(iftar)}' : 'Iftar $iftar');
    return Container(
      key: RamadanScreen.nextKey,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(QText.eyebrowText(label, ar: isAr), style: QText.eyebrow(ar: isAr)),
          const SizedBox(height: 12),
          // A clock reads hours first in both languages.
          HeroNumber(time, semanticsLabel: '$label $time'),
          const SizedBox(height: 12),
          Text(isAr ? '$where، $other' : '$where · $other', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary)),
        ],
      ),
    );
  }
}

/// The one question the season asks, as a setting: fasting or not. The
/// whole row is the control.
class _FastingRow extends StatelessWidget {
  final AppState state;
  const _FastingRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final on = state.profile.fasting == FastingMode.ramadan;
    return Container(
      key: RamadanScreen.fastingKey,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 8),
      decoration: QDecor.card(),
      child: MergeSemantics(
        child: QTapArea(
          onTap: () {
            HapticFeedback.selectionClick();
            state.setFasting(!on);
          },
          builder: (context, pressed) => Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(isAr ? 'صايم' : 'Fasting', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink)),
                Text(
                  isAr ? 'الوجبات تبقى إفطار وسحور، والمية بالليل.' : 'Meals become iftar and suhoor; water moves to the night.',
                  style: QText.body(size: 13, color: QColors.inkTertiary),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(value: on, onChanged: (v) => state.setFasting(v)),
          ]),
        ),
      ),
    );
  }
}

/// The night's water: eight glasses between iftar and dawn, in the three
/// windows they fit in, the open one marked by its filled drop and a word.
class _WaterCard extends StatelessWidget {
  final AppState state;
  const _WaterCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final h = state.hydrationWindows;
    final now = state.clockNow();
    final open = h.current(now.hour * 60 + now.minute);
    final windows = h.windows;
    final total = windows.fold(0, (sum, w) => sum + w.glasses);
    String glasses(int n) => _glass.of(n, ar: isAr, iso: state.iso);
    String clock(int minutes) => state.iso(SunTimes.clock(minutes % (24 * 60)));
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(QText.eyebrowText(isAr ? 'المية بالليل' : 'Water tonight', ar: isAr), style: QText.eyebrow(ar: isAr)),
          const SizedBox(height: 8),
          Text(
            isAr ? '${glasses(total)} بين الإفطار والفجر' : '${glasses(total)} between iftar and dawn',
            style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink),
          ),
          const SizedBox(height: 4),
          for (final (i, w) in windows.indexed) ...[
            if (i > 0) const Divider(color: QColors.hairline, height: 1, thickness: 1, indent: 32),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Icon(open == w ? QIcons.waterFull : QIcons.water, size: 20, color: open == w ? QColors.ink : QColors.inkTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    open == w ? (isAr ? '${w.label(true)} — دلوقتي' : '${w.label(false)} · now') : w.label(isAr),
                    style: QText.body(size: 15, weight: open == w ? FontWeight.w600 : FontWeight.w400, color: open == w ? QColors.ink : QColors.inkSecondary),
                  ),
                ),
                Text('${clock(w.fromMin)}–${clock(w.toMin)}', textDirection: TextDirection.ltr, style: QText.number(size: 13, color: QColors.inkTertiary)),
                const SizedBox(width: 12),
                Text(glasses(w.glasses), style: QText.number(size: 15, weight: FontWeight.w500, color: QColors.ink, ar: isAr)),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

/// The month's logging, against its length; and, while the score is shown,
/// what a whole month earns.
class _MonthCard extends StatelessWidget {
  final AppState state;
  const _MonthCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final season = state.season;
    final logged = state.seasonDaysLogged;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(QText.eyebrowText(isAr ? 'الشهر ده' : 'This month', ar: isAr), style: QText.eyebrow(ar: isAr)),
          const SizedBox(height: 8),
          Text(
            isAr
                // The noun counts the days logged, as Arabic counts (one,
                // two, three to ten, eleven on); in English the month's days
                // take it.
                ? 'سجّلت ${Counted.day.of(logged, ar: true, iso: state.iso)} من ${state.iso('${season.days}')}'
                : 'Logged $logged of ${season.days} days',
            style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink),
          ),
          const SizedBox(height: 12),
          QBar(value: season.days == 0 ? 0 : logged / season.days),
          // The bonus keeps score, so it goes with "Points and streaks" (O4).
          if (state.showScore) ...[
            const SizedBox(height: 12),
            Text(
              isAr ? 'وجبة واحدة كل يوم لحد آخر الشهر، وتاخد ${state.suAmount(500)}.' : 'A meal logged every day to the end of the month earns ${state.suAmount(500)}.',
              style: QText.body(size: 13, color: QColors.inkTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The month read back: days logged, the average against the target, the
/// scale, the longest run. Shared as text. Then, quietly, the blueprint's
/// question at the standard price: keep the plan going?
class _EidCard extends StatelessWidget {
  final AppState state;
  const _EidCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final report = state.eidReport();
    final price = formatEgp(state.displayPlusQuote.listPounds, ar: isAr, eastern: state.easternDigits);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(QText.eyebrowText(isAr ? 'تقرير العيد' : 'Eid report', ar: isAr), style: QText.eyebrow(ar: isAr)),
          const SizedBox(height: 8),
          Text(isAr ? 'اللي اتغيّر في الشهر' : 'What changed this month', style: QText.display(size: 20, ar: isAr, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final l in report.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(isAr ? l.ar : l.en, style: QText.body(size: 15, color: QColors.inkSecondary)),
            ),
          const SizedBox(height: 16),
          QOutlineButton(label: isAr ? 'شارك' : 'Share', icon: QIcons.share, onTap: state.shareEidReport),
          if (!state.plusActive) ...[
            const SizedBox(height: 4),
            QTapArea(
              onTap: () => state.go(AppScreen.subscription),
              builder: (context, pressed) => Row(children: [
                Flexible(
                  child: Text(
                    isAr ? 'كمّل الخطة مع قمر+ بـ ${together(price)} في الشهر' : 'Keep the plan going with Qamar+, ${together(price)} a month',
                    style: QText.body(size: 15, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(QIcons.forward, size: 16, color: pressed ? QColors.ink : QColors.inkSecondary),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
