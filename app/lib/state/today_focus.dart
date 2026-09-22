import 'app_state.dart';

/// The cards that can take Today's one contextual slot (O15), highest first:
/// the declaration order is the priority. The slot holds exactly one. The
/// others that are due move below the fold, in this order. Never a stack.
///
/// Seat 3 adds two in its turn: `weekCard` (review day, three or more days
/// logged) between [fasting] and [earnedMonth], and `quest` (only when it is
/// real, O2) last. Each needs a value here, a line in [todayCardDue], a
/// widget in the Today screen's slot builder, and a case in the layout
/// contract test (test/today_layout_test.dart).
enum TodayCard {
  /// A safety answer: the general-guidance card, in place of any target.
  safety,

  /// The moon's three gestures, until the first hold.
  tutorial,

  /// The free week or the paid month, in its last 48 hours. Above fasting:
  /// its window is 48 hours and, with nothing renewing, it is the only word.
  billing,

  /// Ramadan's one question, in season, until it is answered. After it, if
  /// the answer could not rewrite today's plan, the slot keeps one line
  /// saying so, with its way on, until the plan catches up (O10).
  fasting,

  /// The earned month: being earned, or just granted.
  earnedMonth,
}

/// Whether [card] wants the slot now.
bool todayCardDue(AppState s, TodayCard card) => switch (card) {
      TodayCard.safety => s.generalGuidance,
      TodayCard.tutorial => s.holdTutorialDue,
      TodayCard.billing => s.billingMomentDue,
      TodayCard.fasting => s.fastingPromptDue || s.fastingNotYet != null,
      TodayCard.earnedMonth => s.earnedMonthJustGranted || (s.plusActive && s.earnedMonth.inProgress),
    };

/// Every card due now, highest first.
List<TodayCard> todayCardsDue(AppState s) => [
      for (final card in TodayCard.values)
        if (todayCardDue(s, card)) card,
    ];

/// The card in Today's slot, or none. Pure: it reads state and nothing else.
TodayCard? todayFocus(AppState s) {
  for (final card in TodayCard.values) {
    if (todayCardDue(s, card)) return card;
  }
  return null;
}
