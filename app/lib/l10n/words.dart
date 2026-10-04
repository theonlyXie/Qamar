/// How the app puts a count and its noun together, and keeps a closing phrase
/// on one line.
library;

/// A noun that is counted, in both languages, said the way each language
/// counts. This is the app's one count rule: the You screen's memory line,
/// the streak and the week's day counts all use it.
///
/// English: 1 day, 2 days. Arabic: one is the noun with واحد (يوم واحد),
/// two is the dual (يومين), three to ten take the plural (٣ أيام), and
/// eleven on take the singular (١١ يوم). The last two digits decide, so 103
/// takes the plural again. In Arabic the number is drawn in the app's digits
/// ([iso]).
class Counted {
  final String en;
  final String enPlural;
  final String arOne;
  final String arTwo;
  final String arFew;
  final String arMany;

  const Counted({
    required this.en,
    required this.enPlural,
    required this.arOne,
    required this.arTwo,
    required this.arFew,
    required this.arMany,
  });

  static const day = Counted(en: 'day', enPlural: 'days', arOne: 'يوم واحد', arTwo: 'يومين', arFew: 'أيام', arMany: 'يوم');
  static const item = Counted(en: 'item', enPlural: 'items', arOne: 'عنصر واحد', arTwo: 'عنصرين', arFew: 'عناصر', arMany: 'عنصر');
  static const meal = Counted(en: 'meal', enPlural: 'meals', arOne: 'وجبة واحدة', arTwo: 'وجبتين', arFew: 'وجبات', arMany: 'وجبة');

  /// [n] of this noun, in Arabic when [ar].
  String of(int n, {required bool ar, required String Function(String) iso}) {
    if (!ar) return n == 1 ? '1 $en' : '$n $enPlural';
    if (n == 1) return arOne;
    if (n == 2) return arTwo;
    final lastTwo = n % 100;
    return '${iso('$n')} ${lastTwo >= 3 && lastTwo <= 10 ? arFew : arMany}';
  }
}

/// [words] joined by no-break spaces, so they wrap as one: a sentence that
/// ends on them never leaves its last word alone on a line.
String together(String words) => words.replaceAll(' ', '\u00A0');
