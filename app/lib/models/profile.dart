enum Goal { lose, maintain, gain }

/// Needed for the Mifflin-St Jeor resting-metabolism equation, whose final
/// constant differs by sex (+5 / -161). Without it the app silently applied
/// the male constant to everyone, overstating women's targets by 166 kcal/day.
enum Gender { male, female }

/// A season the person is keeping. Ramadan changes the plan's meals to iftar
/// and suhoor and the water card to windows; it lives on the profile so the
/// night job on the server writes the right kind of day.
enum FastingMode { none, ramadan }

class Profile {
  final String name;

  /// Stored as parts rather than a DateTime so [Profile] stays const-
  /// constructible, and so a partially-entered date is representable while the
  /// user is still spinning the steppers.
  final int birthYear;
  final int birthMonth;
  final int birthDay;

  final Gender gender;
  final int height;
  final int weight;
  final int fat;
  final Goal goal;
  final double activity;
  final List<String> prefs;
  final FastingMode fasting;

  const Profile({
    this.name = '',
    this.birthYear = 1997,
    this.birthMonth = 6,
    this.birthDay = 15,
    this.gender = Gender.male,
    this.height = 172,
    this.weight = 82,
    this.fat = 27,
    this.goal = Goal.lose,
    this.activity = 1.5,
    this.prefs = const [],
    this.fasting = FastingMode.none,
  });

  /// Whole years elapsed, counting the birthday as it actually falls rather
  /// than by year subtraction alone.
  int get age {
    final now = DateTime.now();
    var years = now.year - birthYear;
    if (now.month < birthMonth || (now.month == birthMonth && now.day < birthDay)) {
      years--;
    }
    return years;
  }

  bool get isAdult => age >= 18;

  /// Days in the currently selected birth month, leap years included, so the
  /// day stepper can clamp correctly.
  static int daysInMonth(int year, int month) {
    const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))) return 29;
    return lengths[(month - 1).clamp(0, 11)];
  }

  Profile copyWith({
    String? name,
    int? birthYear,
    int? birthMonth,
    int? birthDay,
    Gender? gender,

    /// Convenience for callers that know an age but not a birth date (the
    /// InBody import, and free-text corrections like "I'm 31"). Shifts the
    /// birth year to match, keeping the month and day.
    int? age,
    int? height,
    int? weight,
    int? fat,
    Goal? goal,
    double? activity,
    List<String>? prefs,
    FastingMode? fasting,
  }) {
    var year = birthYear ?? this.birthYear;
    if (age != null && birthYear == null) {
      final now = DateTime.now();
      final month = birthMonth ?? this.birthMonth;
      final day = birthDay ?? this.birthDay;
      year = now.year - age;
      // Keep the derived age exact regardless of where in the year we are.
      if (now.month < month || (now.month == month && now.day < day)) year--;
    }
    return Profile(
      name: name ?? this.name,
      birthYear: year,
      birthMonth: birthMonth ?? this.birthMonth,
      birthDay: birthDay ?? this.birthDay,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      fat: fat ?? this.fat,
      goal: goal ?? this.goal,
      activity: activity ?? this.activity,
      prefs: prefs ?? this.prefs,
      fasting: fasting ?? this.fasting,
    );
  }
}
