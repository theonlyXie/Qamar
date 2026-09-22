/// The day's quest (O2): real, or absent.
///
/// The server chooses it from what the day actually lacks
/// (`qamar_quest_for`, migration 0061) and pays it, 250 Su, from the row that
/// satisfies it: the meal or the glass that does what it asks. The phone only
/// shows it, and can put it away for the day ("not today"). No tap pays.
///
/// Every kind only ever adds something to the day. A kind that restricts
/// (stay under, skip a meal, a deficit) must never be added:
/// test/quest_test.dart reads 0061's SQL enum and fails if the two drift, or
/// if a kind or its words restrict.
enum QuestKind {
  /// No lunch logged yet: log lunch before 16:00, so dinner can still be
  /// adjusted.
  lunchBy16('lunch_by_16'),

  /// Under half the day's protein by 17:00: a dinner with 20 g or more.
  proteinDinner('protein_dinner'),

  /// Under 1.5 litres today: six glasses (1,500 ml, tea included).
  water6('water_6');

  /// The SQL enum value (public.quest_kind).
  final String wire;
  const QuestKind(this.wire);

  static QuestKind? fromWire(Object? w) {
    for (final k in values) {
      if (k.wire == w) return k;
    }
    return null;
  }

  /// What it asks, in one line. [iso] draws numbers the app's way.
  String title({required bool ar, required String Function(String) iso}) => switch (this) {
        QuestKind.lunchBy16 => ar ? 'سجّل الغدا قبل ${iso('4')} العصر' : 'Log lunch before 4pm',
        QuestKind.proteinDinner => ar ? 'عشا فيه ${iso('20')} جم بروتين أو أكتر' : 'A dinner with 20 g of protein or more',
        QuestKind.water6 => ar ? '${iso('6')} كوبايات مية النهارده' : 'Six glasses of water today',
      };

  /// Why it is today's, in one line.
  String why({required bool ar}) => switch (this) {
        QuestKind.lunchBy16 => ar ? 'لما تسجّل بدري بقدر أعدّل العشا قبل ما اليوم يخلص.' : 'Logged early, I can still adjust dinner.',
        QuestKind.proteinDinner => ar ? 'البروتين ناقص النهارده، وعشا واحد يكمّله.' : 'Protein is today’s gap so far; one dinner closes it.',
        QuestKind.water6 => ar ? 'يعني لتر ونص، أساس كويس في حر مصر، والشاي بيتحسب.' : 'That is 1.5 litres, a steady base in Egyptian heat; tea counts.',
      };
}

/// Today's quest as the server has it.
class DayQuest {
  final QuestKind kind;

  /// Paid: what it asked for was logged.
  final bool done;

  /// When it stops being today's, unpaid.
  final DateTime expiresAt;

  const DayQuest({required this.kind, required this.done, required this.expiresAt});

  /// The RPC's answer (`qamar_today_quest`), or null for no quest today, or
  /// a kind this build does not know.
  static DayQuest? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = QuestKind.fromWire(json['kind']);
    final expires = json['expires_at'] is String ? DateTime.tryParse(json['expires_at'] as String) : null;
    if (kind == null || expires == null) return null;
    return DayQuest(kind: kind, done: json['done'] == true, expiresAt: expires.toLocal());
  }
}
