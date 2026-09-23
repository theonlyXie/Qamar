/// The free trial's words wherever they carry a number of days, in one place
/// (O12, seat 5's copy). Every count goes through [Counted.day], the app's one
/// count rule, so "1 day", "2 days", "يومين", "٣ أيام" and "١١ يوم" come out
/// right whatever the server's days are: the free week is 7 today, a
/// nutritionist's code 14 (billing_config), and neither is promised to stay.
/// English verbs agree with the count ("1 day … is", "14 days … are").
library;

import 'words.dart';

typedef Iso = String Function(String);

class TrialWords {
  TrialWords._();

  static String _days(int n, bool ar, Iso iso) => Counted.day.of(n, ar: ar, iso: iso);

  /// The reveal's offer card, its first line.
  static String offerTitle(int days, {required bool ar, required Iso iso}) =>
      ar ? '${_days(days, ar, iso)} من قمر كامل.' : '${_days(days, ar, iso)} of the full Qamar.';

  /// Me's Qamar+ tile while the week waits.
  static String waitingInMe(int days, {required bool ar, required Iso iso}) => ar
      ? 'أسبوعك المجاني مستنيك: ${_days(days, ar, iso)}، من غير بطاقة، ومفيش حاجة بتتجدد لوحدها.'
      : 'Your free week is waiting: ${_days(days, ar, iso)}, no card, nothing renews.';

  /// The notice once the week has started.
  static String started(int days, {required bool ar, required Iso iso}) => ar
      ? 'أسبوعك مع قمر كامل بدأ: ${_days(days, ar, iso)}، من غير بطاقة، ومفيش حاجة بتتجدد لوحدها.'
      : 'Your week of the full Qamar has started: ${_days(days, ar, iso)}, no card, and nothing renews on its own.';

  /// The paywall's button: a verb and what it starts, short enough for one
  /// line. Its days are said by [paywallRule], right under it.
  static String paywallButton({required bool ar}) => ar ? 'ابدأ الأسبوع المجاني' : 'Start the free week';

  /// The paywall's rule under the button.
  static String paywallRule(int days, {required bool ar, required Iso iso}) => ar
      ? 'من غير بطاقة، ومفيش حاجة بتتجدد لوحدها: بعد ${_days(days, ar, iso)} بترجع لقمر المجاني.'
      : 'No card, and nothing renews on its own: after ${_days(days, ar, iso)} you are simply back on the free Qamar.';

  /// The first locked tomorrow card's link.
  static String lockLink(int days, {required bool ar, required Iso iso}) => ar
      ? 'افتح الخطة بأسبوعك المجاني: ${_days(days, ar, iso)}، من غير بطاقة'
      : 'Open the plan with your free week: ${_days(days, ar, iso)}, no card';

  /// A nutritionist's code, redeemed with days.
  static String proRedeemed(String name, int days, {required bool ar, required Iso iso}) => ar
      ? '$name بعتك. ${_days(days, ar, iso)} قمر+ عليك من دلوقتي — من غير بطاقة، ومفيش حاجة بتتجدد لوحدها.'
      : '$name sent you. ${_days(days, ar, iso)} of Qamar+ ${days == 1 ? 'is' : 'are'} yours from now — no card, and nothing renews on its own.';

  /// The professional's card: what their clients get. [confirmed] is the
  /// operator's confirmation of the code (0069).
  static String clientDays(int days, {required bool confirmed, required bool ar, required Iso iso}) {
    final d = _days(days, ar, iso);
    if (confirmed) {
      return ar
          ? ' عميلك لما يكتبه في «حسابي» قبل ما يشترك بياخد $d قمر+ ببلاش.'
          : ' A client who enters it in Me before subscribing also gets $d of Qamar+ free.';
    }
    return ar
        ? ' لما قمر يتأكد إنك أخصائي أو مدرّب، عميلك اللي يكتبه في «حسابي» بياخد كمان $d قمر+ ببلاش.'
        : ' Once Qamar confirms you are a nutritionist or coach, a client who enters it in Me also gets $d of Qamar+ free.';
  }

  /// The professional's clients card: days this week within 10% of the
  /// target. "في حدود الهدف" takes no agreement, so it reads right after
  /// one day, two days and many.
  static String nearTarget(int days, {required bool ar, required Iso iso}) =>
      ar ? '${_days(days, ar, iso)} في حدود الهدف' : '${_days(days, ar, iso)} near target';
}
