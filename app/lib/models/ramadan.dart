import 'dart:math' as math;

import '../l10n/words.dart';
import '../services/repositories.dart';
import 'days.dart';
import 'water.dart';

/// Ramadan as a product mode (the blueprint's acquisition loop): a season
/// with dates, a fasting switch on the profile, iftar and suhoor in place of
/// the three meals, hydration windows between them, a bonus for logging the
/// whole month, and an Eid report of what changed. Free for everyone.
///
/// Dates come from the server (`app_seasons`) because the month starts with a
/// moon sighting and the estimate below can be a day out; the estimate is
/// what the app uses until the server answers, so nothing depends on being
/// online to know it is Ramadan.
enum SeasonPhase { none, before, during, after }

class Season {
  final String key;
  final String nameAr;
  final String nameEn;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime eidOn;

  const Season({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.startsOn,
    required this.endsOn,
    required this.eidOn,
  });

  /// Umm al-Qura's expectation for 1448: first fast Monday 8 February 2027,
  /// 29 days, Eid al-Fitr Tuesday 9 March 2027. The sighting may move it a day.
  static final ramadan1448 = Season(
    key: 'ramadan_1448',
    nameAr: 'رمضان 1448',
    nameEn: 'Ramadan 1448',
    startsOn: DateTime(2027, 2, 8),
    endsOn: DateTime(2027, 3, 8),
    eidOn: DateTime(2027, 3, 9),
  );

  /// The mode shows itself a week before the first fast and stays a week
  /// after Eid for the report.
  static const leadDays = 7;
  static const tailDays = 7;

  int get days => Days.between(startsOn, endsOn) + 1;

  String name(bool ar) => ar ? nameAr : nameEn;

  static DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);

  SeasonPhase phase(DateTime now) {
    final d = _date(now);
    if (d.isBefore(Days.add(startsOn, -leadDays))) return SeasonPhase.none;
    if (d.isBefore(startsOn)) return SeasonPhase.before;
    if (!d.isAfter(endsOn)) return SeasonPhase.during;
    if (!d.isAfter(Days.add(eidOn, tailDays))) return SeasonPhase.after;
    return SeasonPhase.none;
  }

  /// 1-based day of the month, or null outside it.
  int? dayOf(DateTime now) {
    if (phase(now) != SeasonPhase.during) return null;
    return Days.between(startsOn, now) + 1;
  }

  /// Days until the first fast; null once it has begun.
  int? daysUntil(DateTime now) {
    final d = _date(now);
    if (!d.isBefore(startsOn)) return null;
    return Days.between(d, startsOn);
  }

  factory Season.fromJson(Map<String, dynamic> j) => Season(
        key: j['key'] as String? ?? '',
        nameAr: j['name_ar'] as String? ?? '',
        nameEn: j['name_en'] as String? ?? '',
        startsOn: DateTime.parse(j['starts_on'] as String),
        endsOn: DateTime.parse(j['ends_on'] as String),
        eidOn: DateTime.parse(j['eid_on'] as String),
      );
}

/// Sunset and dawn for a place and a day — iftar and the end of suhoor.
///
/// NOAA's solar position equations, good to a couple of minutes, which is
/// what a hydration window needs; the official Fajr (Egyptian General
/// Authority, sun 19.5° below the horizon) is what the suhoor window ends
/// on. Times are minutes after local midnight.
class SunTimes {
  SunTimes._();

  static const cairoLat = 30.0444;
  static const cairoLng = 31.2357;

  /// Egypt's dawn-prayer depression angle.
  static const fajrAngle = 19.5;

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;

  static int _dayOfYear(DateTime d) => Days.between(DateTime(d.year), d) + 1;

  /// Minutes after local midnight at which the sun's centre passes [zenith]
  /// degrees, in the evening ([evening]) or the morning.
  static int? _crossing(DateTime day, double zenith, {required bool evening, required double lat, required double lng, required int utcOffsetMinutes}) {
    final n = _dayOfYear(day);
    final g = 2 * math.pi / 365 * (n - 1);
    final eqtime = 229.18 *
        (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g));
    final decl = 0.006918 -
        0.399912 * math.cos(g) +
        0.070257 * math.sin(g) -
        0.006758 * math.cos(2 * g) +
        0.000907 * math.sin(2 * g) -
        0.002697 * math.cos(3 * g) +
        0.00148 * math.sin(3 * g);
    final cosHa = math.cos(_rad(zenith)) / (math.cos(_rad(lat)) * math.cos(decl)) - math.tan(_rad(lat)) * math.tan(decl);
    if (cosHa < -1 || cosHa > 1) return null; // polar day or night — not Egypt
    final ha = _deg(math.acos(cosHa));
    final utc = 720 - 4 * (lng + (evening ? -ha : ha)) - eqtime;
    return ((utc + utcOffsetMinutes).round() + 24 * 60) % (24 * 60);
  }

  /// Sunset — iftar.
  static int sunset(DateTime day, {double lat = cairoLat, double lng = cairoLng, int? utcOffsetMinutes}) =>
      _crossing(day, 90.833, evening: true, lat: lat, lng: lng, utcOffsetMinutes: utcOffsetMinutes ?? day.timeZoneOffset.inMinutes) ?? 18 * 60;

  /// Dawn at the Fajr angle — the end of suhoor.
  static int fajr(DateTime day, {double lat = cairoLat, double lng = cairoLng, int? utcOffsetMinutes}) =>
      _crossing(day, 90 + fajrAngle, evening: false, lat: lat, lng: lng, utcOffsetMinutes: utcOffsetMinutes ?? day.timeZoneOffset.inMinutes) ?? 5 * 60;

  static String clock(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// One stretch of the night in which to drink, and how much.
class HydrationWindow {
  final String labelAr;
  final String labelEn;
  final int fromMin;
  final int toMin;
  final int glasses;

  const HydrationWindow({required this.labelAr, required this.labelEn, required this.fromMin, required this.toMin, required this.glasses});

  String label(bool ar) => ar ? labelAr : labelEn;

  /// [minute] may be past midnight (as minutes since the iftar day's midnight).
  bool contains(int minute) => minute >= fromMin && minute < toMin;
}

/// The fasting day's water: eight glasses between iftar and fajr, in three
/// windows, because "drink two litres" is not advice a person who cannot
/// drink for fourteen hours can act on.
class HydrationWindows {
  final int iftarMin;
  final int fajrMin;

  const HydrationWindows({required this.iftarMin, required this.fajrMin});

  /// Two litres: what a fasting day can realistically carry.
  static const goalMl = 8 * Water.glassMl;

  /// Fajr on the day after iftar, as minutes since the iftar day's midnight.
  int get fajrNext => fajrMin + 24 * 60;

  List<HydrationWindow> get windows => [
        HydrationWindow(labelAr: 'الإفطار', labelEn: 'Iftar', fromMin: iftarMin, toMin: iftarMin + 120, glasses: 3),
        HydrationWindow(labelAr: 'بعد التراويح', labelEn: 'After taraweeh', fromMin: iftarMin + 120, toMin: iftarMin + 330, glasses: 3),
        HydrationWindow(labelAr: 'السحور', labelEn: 'Suhoor', fromMin: fajrNext - 120, toMin: fajrNext, glasses: 2),
      ];

  /// The window open at [now] (minutes after midnight), or null while fasting.
  HydrationWindow? current(int nowMin) {
    final m = nowMin < iftarMin ? nowMin + 24 * 60 : nowMin;
    for (final w in windows) {
      if (w.contains(m)) return w;
    }
    return null;
  }

  /// True from fajr to sunset.
  bool fastingAt(int nowMin) => nowMin >= fajrMin && nowMin < iftarMin;
}

/// One line of the Eid report, in both languages.
typedef ReportLine = ({String ar, String en});

/// What changed in the month, from the person's own rows: how many days were
/// logged, how the average sat against the target, what the scale said, the
/// longest run. Nothing here is a judgement; it is the month read back.
class EidReport {
  final Season season;
  final int daysLogged;
  final int? avgKcal;
  final int targetKcal;
  final double? weightDelta;
  final int bestRun;
  final List<ReportLine> lines;

  const EidReport({
    required this.season,
    required this.daysLogged,
    required this.avgKcal,
    required this.targetKcal,
    required this.weightDelta,
    required this.bestRun,
    required this.lines,
  });

  bool get full => daysLogged >= season.days;

  static EidReport build({
    required Season season,
    required List<DayTotals> history,
    required List<WeightReading> weights,
    required int targetKcal,
    required String Function(String) iso,
  }) {
    bool inSeason(DateTime d) {
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(season.startsOn) && !day.isAfter(season.endsOn);
    }

    final logged = history.where((d) => d.meals > 0 && inSeason(d.day)).toList()..sort((a, b) => a.day.compareTo(b.day));
    final daysLogged = logged.length;
    final avg = daysLogged == 0 ? null : (logged.fold(0, (s, d) => s + d.kcal) / daysLogged).round();

    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in logged) {
      final day = DateTime(d.day.year, d.day.month, d.day.day);
      run = (prev != null && Days.between(prev, day) == 1) ? run + 1 : 1;
      prev = day;
      if (run > best) best = run;
    }

    final ws = weights.where((w) => inSeason(w.at)).toList()..sort((a, b) => a.at.compareTo(b.at));
    final delta = ws.length >= 2 ? ws.last.kg - ws.first.kg : null;

    final target = math.max(targetKcal, 1);
    final lines = <ReportLine>[
      (
        ar: 'سجّلت ${Counted.day.of(daysLogged, ar: true, iso: iso)} من ${iso('${season.days}')}${daysLogged >= season.days ? ' — الشهر كله.' : '.'}',
        en: 'You logged $daysLogged of ${season.days} days${daysLogged >= season.days ? ' — the whole month.' : '.'}',
      ),
    ];
    if (avg != null) {
      final pct = ((avg / target - 1) * 100).round();
      lines.add(pct.abs() < 5
          ? (
              ar: 'متوسطك في الشهر ${iso('$avg')} سعرة في اليوم — على هدفك تقريباً.',
              en: 'Your month averaged $avg kcal a day — about on your target.',
            )
          : (
              ar: 'متوسطك في الشهر ${iso('$avg')} سعرة في اليوم — ${pct > 0 ? 'أعلى' : 'أقل'} من هدفك بـ ${iso('${pct.abs()}')}٪.',
              en: 'Your month averaged $avg kcal a day — ${pct.abs()}% ${pct > 0 ? 'above' : 'below'} your target.',
            ));
    }
    if (delta != null) {
      final kg = delta.abs().toStringAsFixed(1);
      lines.add(delta.abs() < 0.3
          ? (ar: 'الميزان ثابت من أول الشهر لآخره.', en: 'The scale held steady from the first day to the last.')
          : (
              ar: 'الميزان ${delta < 0 ? 'نزل' : 'زاد'} ${iso(kg)} كيلو بين أول قراءة وآخرها.',
              en: 'The scale went ${delta < 0 ? 'down' : 'up'} $kg kg between the first reading and the last.',
            ));
    }
    if (best >= 3) {
      lines.add((ar: 'أطول سلسلة: ${Counted.day.of(best, ar: true, iso: iso)} ورا بعض.', en: 'Longest run: ${Counted.day.of(best, ar: false, iso: iso)} in a row.'));
    }
    if (daysLogged == 0) {
      lines.add((ar: 'مفيش تسجيل في الشهر ده، فمفيش حاجة أقولها غير: كل سنة وإنت طيب.', en: 'Nothing was logged this month, so there is nothing to read back — Eid Mubarak all the same.'));
    }

    return EidReport(
      season: season,
      daysLogged: daysLogged,
      avgKcal: avg,
      targetKcal: targetKcal,
      weightDelta: delta,
      bestRun: best,
      lines: lines,
    );
  }

  String text({required bool ar, required String site}) =>
      '${ar ? 'رمضان مع قمر' : 'Ramadan with Qamar'}\n${lines.map((l) => ar ? l.ar : l.en).join('\n')}\n$site';
}
