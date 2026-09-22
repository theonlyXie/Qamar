/// The habit loop's external trigger, as the blueprint bounds it.
///
/// A nudge is Qamar asking about a meal at the time this person usually eats
/// it — "الغدا إيه النهاردة؟" — never "don't forget to log". Two a day by
/// default (lunch and dinner, the Egyptian day's two real meals); the person
/// can lower that to zero and never raise it above two. Pushed to the phone
/// only for the first fourteen days: by then the internal trigger — food
/// doubt — has either formed or it has not, and a notification is not going
/// to form it. In the app the same nudge is a slow pulse of the orb for the
/// hours the meal is usually eaten; holding the orb hears it.
library;

enum MealSlot { breakfast, lunch, dinner, iftar, suhoor }

/// Which slot a clock hour belongs to — the same cut the Today screen uses to
/// pick the next planned meal. On a fasting day there are two meals: iftar
/// from sunset into the night, suhoor in the small hours.
MealSlot slotForHour(int hour, {bool fasting = false}) {
  if (fasting) return hour >= 15 || hour < 1 ? MealSlot.iftar : MealSlot.suhoor;
  return hour < 11
      ? MealSlot.breakfast
      : hour < 17
          ? MealSlot.lunch
          : MealSlot.dinner;
}

/// When this person eats, as minutes after midnight on the phone's clock.
///
/// Starts as typical Cairo hours and is replaced, slot by slot, by the median
/// time of their own logs once there are enough of them (see
/// `qamar_meal_time_profile`). Nudges follow these, so the trigger lands
/// when the meal is actually on the table.
class MealTimes {
  final int breakfast;
  final int lunch;
  final int dinner;

  /// Ramadan's two meals. Not learned from logs — set from the sun each day
  /// (iftar at sunset, suhoor ending at dawn) while the mode is on.
  final int iftar;
  final int suhoor;

  const MealTimes({
    this.breakfast = 9 * 60,
    this.lunch = 14 * 60,
    this.dinner = 20 * 60 + 30,
    this.iftar = 18 * 60,
    this.suhoor = 3 * 60 + 30,
  });

  static const typical = MealTimes();

  int of(MealSlot slot) => switch (slot) {
        MealSlot.breakfast => breakfast,
        MealSlot.lunch => lunch,
        MealSlot.dinner => dinner,
        MealSlot.iftar => iftar,
        MealSlot.suhoor => suhoor,
      };

  MealTimes withRamadan({required int iftar, required int suhoor}) =>
      MealTimes(breakfast: breakfast, lunch: lunch, dinner: dinner, iftar: iftar, suhoor: suhoor);

  /// From the server's profile: minutes per slot, null where there is not
  /// enough history yet. Anything missing keeps the typical hour.
  factory MealTimes.fromJson(Map<String, dynamic> json, {MealTimes fallback = typical}) {
    int pick(String key, int def) {
      final v = json[key];
      if (v is num && v >= 0 && v < 24 * 60) return v.round();
      return def;
    }
    return MealTimes(
      breakfast: pick('breakfast', fallback.breakfast),
      lunch: pick('lunch', fallback.lunch),
      dinner: pick('dinner', fallback.dinner),
    );
  }
}

/// What a scheduled notification is about. Almost always a meal; once per
/// free week, the week ending; once per paid month, the month ending —
/// because nothing renews on its own, so without it a member's Qamar+
/// simply stops one evening with no word.
enum NudgeKind { meal, trialEnding, membershipEnding }

/// One scheduled question.
class Nudge {
  final MealSlot slot;

  /// Local instant it fires.
  final DateTime at;

  /// Which day of the schedule it belongs to (0 = today); with the slot it
  /// makes the notification id, so a reschedule replaces rather than stacks.
  final int dayIndex;

  final NudgeKind kind;

  const Nudge({required this.slot, required this.at, required this.dayIndex, this.kind = NudgeKind.meal});

  /// The free week's one reminder, 48 hours before it ends — scheduled the
  /// moment the trial starts, as the blueprint has it.
  const Nudge.trialEnding({required this.at})
      : slot = MealSlot.lunch,
        dayIndex = 0,
        kind = NudgeKind.trialEnding;

  /// The paid month's one reminder, 48 hours before it ends. Like the free
  /// week's, it is scheduled the moment the entitlement is read, and it is
  /// the only way a member hears that the month is ending.
  const Nudge.membershipEnding({required this.at})
      : slot = MealSlot.lunch,
        dayIndex = 0,
        kind = NudgeKind.membershipEnding;

  static const trialPayload = 'trial:ending';
  static const membershipPayload = 'plus:ending';

  int get id => switch (kind) {
        NudgeKind.trialEnding => 90,
        NudgeKind.membershipEnding => 91,
        NudgeKind.meal => 100 + dayIndex * MealSlot.values.length + slot.index,
      };

  /// Travels with the notification; tapping it routes back into the app.
  String get payload => switch (kind) {
        NudgeKind.trialEnding => trialPayload,
        NudgeKind.membershipEnding => membershipPayload,
        NudgeKind.meal => 'nudge:${slot.name}',
      };

  String text({required bool ar}) => switch (kind) {
        NudgeKind.trialEnding => NudgeCopy.trialEnding(ar: ar),
        NudgeKind.membershipEnding => NudgeCopy.membershipEnding(ar: ar),
        NudgeKind.meal => NudgeCopy.text(slot, at, ar: ar),
      };
}

/// Qamar's voice, and nothing else. Two phrasings per meal, alternating by
/// day so the same words do not arrive every afternoon. None of them says
/// "log", "don't forget" or "reminder".
class NudgeCopy {
  NudgeCopy._();

  static const _ar = <MealSlot, List<String>>{
    MealSlot.breakfast: ['فطرت إيه النهاردة؟', 'الفطار إيه؟ قول لي وأنا أحسبها.'],
    MealSlot.lunch: ['الغدا إيه النهاردة؟', 'إيه اللي على الغدا؟ صوّره أو قول لي.'],
    MealSlot.dinner: ['العشا إيه النهاردة؟', 'خفيف ولا تقيل العشا؟ قول لي.'],
    MealSlot.iftar: ['فطرت على إيه النهاردة؟', 'إيه اللي كان على سفرة الإفطار؟ صوّره أو قول لي.'],
    MealSlot.suhoor: ['السحور إيه النهاردة؟', 'اتسحّرت بإيه؟ قول لي وأنا أحسبها.'],
  };

  static const _en = <MealSlot, List<String>>{
    MealSlot.breakfast: ['What did you have for breakfast?', 'Breakfast — what was it? Tell me and I’ll do the numbers.'],
    MealSlot.lunch: ['What’s for lunch today?', 'What’s on the plate? Photograph it or tell me.'],
    MealSlot.dinner: ['What’s for dinner tonight?', 'Light or heavy tonight? Tell me.'],
    MealSlot.iftar: ['What did you break the fast with today?', 'What was on the iftar table? Photograph it or tell me.'],
    MealSlot.suhoor: ['What was suhoor today?', 'What did you have for suhoor? Tell me and I’ll do the numbers.'],
  };

  static String text(MealSlot slot, DateTime day, {required bool ar}) {
    final variants = (ar ? _ar : _en)[slot]!;
    final dayOfYear = day.difference(DateTime(day.year)).inDays;
    return variants[dayOfYear % variants.length];
  }

  static Iterable<String> get all => [..._ar.values.expand((v) => v), ..._en.values.expand((v) => v)];

  /// Two days before the free week ends. A question, in the same voice —
  /// not "your trial is expiring".
  static String trialEnding({required bool ar}) =>
      ar ? 'باقي يومين في أسبوعك مع قمر+. نكمّل الخطة؟' : 'Two days left of your week with Qamar+. Keep the plan going?';

  /// Two days before a paid month ends. It says plainly that nothing renews
  /// on its own — that is the reason the message exists — and asks, in the
  /// same voice. No "expiring", no "don't lose", no "cancel".
  static String membershipEnding({required bool ar}) => ar
      ? 'باقي يومين في شهرك مع قمر+. مفيش حاجة بتتجدد لوحدها — نكمّل شهر كمان؟'
      : 'Two days left of your month with Qamar+. Nothing renews on its own — shall we do another month?';
}

/// What to put on the phone's notification schedule, from the day as it is.
class NudgeSchedule {
  NudgeSchedule._();

  /// The blueprint's ceiling. The person may go lower, never higher.
  static const maxPerDay = 2;

  /// Push nudges stop after this many days of use.
  static const externalDays = 14;

  /// iOS keeps at most this many pending local notifications per app and
  /// silently drops the rest; Android has no such limit, so this is the one
  /// that binds.
  static const maxPending = 64;

  /// Slots kept free under [maxPending] for the notifications that are not
  /// meal questions: the free week's reminder and the paid month's.
  static const reservedPending = 2;

  /// How long a meal's question stays "waiting" on the orb after its time.
  static const window = Duration(hours: 3);

  /// How long before the free week ends its one reminder fires. The paid
  /// month's reminder uses the same lead.
  static const trialLead = Duration(hours: 48);

  /// The free week's reminder, or null when there is no trial running or
  /// the 48-hour mark has already passed (then the Today card carries it).
  static Nudge? trialReminder({required DateTime? trialEnd, required DateTime now}) {
    if (trialEnd == null) return null;
    final at = trialEnd.subtract(trialLead);
    if (!at.isAfter(now)) return null;
    return Nudge.trialEnding(at: at);
  }

  /// The paid month's reminder, or null when there is no paid (or earned)
  /// month running or its 48-hour mark has passed (then the billing-moment
  /// card carries it). Not a meal question, so it sits outside the
  /// fourteen-day window, like the free week's.
  static Nudge? membershipReminder({required DateTime? periodEnd, required DateTime now}) {
    if (periodEnd == null) return null;
    final at = periodEnd.subtract(trialLead);
    if (!at.isAfter(now)) return null;
    return Nudge.membershipEnding(at: at);
  }

  /// Which meals get asked about for a given daily allowance: lunch first,
  /// then dinner. Breakfast is irregular enough in Egypt that asking about
  /// it reads as nagging. On a fasting day: iftar, then suhoor.
  static List<MealSlot> slotsFor(int perDay, {bool fasting = false}) {
    final n = perDay.clamp(0, maxPerDay);
    final order = fasting ? const [MealSlot.iftar, MealSlot.suhoor] : const [MealSlot.lunch, MealSlot.dinner];
    return order.take(n).toList();
  }

  /// Every question still to come in the fourteen-day external window, oldest
  /// first — the whole rest of the window, not the next few days.
  ///
  /// These are local notifications: the phone fires only what is already on
  /// its schedule, and the schedule is only rebuilt while the app is running.
  /// A shorter horizon meant that a person who stopped opening the app went
  /// silent a few days later, well inside the window the questions exist for.
  /// So the rest of the window is scheduled up front, and never more than
  /// [maxPending] less [reservedPending] of them.
  ///
  /// Today's questions for meals already eaten, or whose time has passed, are
  /// left out; days past the window (counted from [firstDay]) are left out
  /// entirely. [firstDay] null means the window has not started, so it is
  /// taken to start today. [days] caps the horizon below the window.
  ///
  /// [fastingOn] and [timesOn] decide each day on its own, so a schedule that
  /// crosses the first or last fast of Ramadan asks about lunch and dinner on
  /// one side and iftar and suhoor on the other, at that day's sun. Without
  /// them, [fasting] and [times] hold for every day.
  static List<Nudge> build({
    required int perDay,
    required MealTimes times,
    required DateTime now,
    Set<MealSlot> loggedToday = const {},
    DateTime? firstDay,
    int days = externalDays,
    bool fasting = false,
    bool Function(DateTime day)? fastingOn,
    MealTimes Function(DateTime day)? timesOn,
  }) {
    if (perDay.clamp(0, maxPerDay) == 0) return const [];
    final today = DateTime(now.year, now.month, now.day);
    final first = firstDay == null ? today : DateTime(firstDay.year, firstDay.month, firstDay.day);
    final out = <Nudge>[];
    for (var d = 0; d < days; d++) {
      final day = today.add(Duration(days: d));
      if (day.difference(first).inDays >= externalDays) break;
      final fastingDay = fastingOn?.call(day) ?? fasting;
      final dayTimes = timesOn?.call(day) ?? times;
      for (final slot in slotsFor(perDay, fasting: fastingDay)) {
        final at = day.add(Duration(minutes: dayTimes.of(slot)));
        if (d == 0 && (!at.isAfter(now) || loggedToday.contains(slot))) continue;
        out.add(Nudge(slot: slot, at: at, dayIndex: d));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    const cap = maxPending - reservedPending;
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  /// The question the orb is holding right now, if a meal's usual time has
  /// come, its window is still open and it has not been logged. This is the
  /// in-app side of the trigger and it does not stop after fourteen days:
  /// the orb having something to say is how Qamar talks, not a push.
  static Nudge? waiting({
    required int perDay,
    required MealTimes times,
    required DateTime now,
    Set<MealSlot> loggedToday = const {},
    bool fasting = false,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    for (final slot in slotsFor(perDay, fasting: fasting)) {
      if (loggedToday.contains(slot)) continue;
      final at = today.add(Duration(minutes: times.of(slot)));
      if (!now.isBefore(at) && now.isBefore(at.add(window))) {
        return Nudge(slot: slot, at: at, dayIndex: 0);
      }
    }
    return null;
  }
}
