/// Movement, logged by hand: the blueprint's "manual activity quick-log
/// (football, walk, gym)". Two taps on the ring — the kind, then how long —
/// and the day shows it. Steps from the phone's health store are a later
/// step (the blueprint asks for that permission on day two, not at install).
enum ActivityKind { football, walk, gym, run, other }

class ActivityCatalog {
  ActivityCatalog._();

  /// Metabolic equivalents: multiples of resting energy, the standard way to
  /// estimate what a stretch of movement costs. Football as recreational
  /// play, walking at an ordinary pace, the gym as general training, running
  /// at a jog. Estimates — the card says so.
  static const met = <ActivityKind, double>{
    ActivityKind.football: 7.0,
    ActivityKind.walk: 3.5,
    ActivityKind.gym: 5.0,
    ActivityKind.run: 8.5,
    ActivityKind.other: 4.0,
  };

  /// The durations offered as chips.
  static const durations = [15, 30, 45, 60, 90];

  static const _ar = <ActivityKind, String>{
    ActivityKind.football: 'كورة',
    ActivityKind.walk: 'مشي',
    ActivityKind.gym: 'جيم',
    ActivityKind.run: 'جري',
    ActivityKind.other: 'حركة تانية',
  };
  static const _en = <ActivityKind, String>{
    ActivityKind.football: 'Football',
    ActivityKind.walk: 'Walk',
    ActivityKind.gym: 'Gym',
    ActivityKind.run: 'Run',
    ActivityKind.other: 'Other',
  };

  static String label(ActivityKind k, {required bool ar}) => (ar ? _ar : _en)[k]!;

  /// kcal ≈ MET × kg × hours.
  static int kcalFor(ActivityKind kind, int minutes, int weightKg) => (met[kind]! * weightKg * minutes / 60).round();
}

class ActivityLog {
  final String? id;
  final ActivityKind kind;
  final int minutes;
  final int kcal;
  final DateTime at;

  const ActivityLog({this.id, required this.kind, required this.minutes, required this.kcal, required this.at});

  ActivityLog copyWith({String? id}) => ActivityLog(id: id ?? this.id, kind: kind, minutes: minutes, kcal: kcal, at: at);

  Map<String, dynamic> toJson() => {'kind': kind.name, 'minutes': minutes, 'kcal': kcal, 'at': at.toIso8601String()};

  factory ActivityLog.fromJson(Map<String, dynamic> j) => ActivityLog(
        kind: ActivityKind.values.asNameMap()[j['kind']?.toString()] ?? ActivityKind.other,
        minutes: (j['minutes'] as num?)?.round() ?? 0,
        kcal: (j['kcal'] as num?)?.round() ?? 0,
        at: DateTime.tryParse(j['at']?.toString() ?? '') ?? DateTime.now(),
      );

  String label({required bool ar}) => ActivityCatalog.label(kind, ar: ar);
}
