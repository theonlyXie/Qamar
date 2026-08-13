enum Goal { lose, maintain, gain }

class Profile {
  final String name;
  final int age;
  final int height;
  final int weight;
  final int fat;
  final Goal goal;
  final double activity;
  final List<String> prefs;

  const Profile({
    this.name = '',
    this.age = 29,
    this.height = 172,
    this.weight = 82,
    this.fat = 27,
    this.goal = Goal.lose,
    this.activity = 1.5,
    this.prefs = const [],
  });

  Profile copyWith({
    String? name,
    int? age,
    int? height,
    int? weight,
    int? fat,
    Goal? goal,
    double? activity,
    List<String>? prefs,
  }) =>
      Profile(
        name: name ?? this.name,
        age: age ?? this.age,
        height: height ?? this.height,
        weight: weight ?? this.weight,
        fat: fat ?? this.fat,
        goal: goal ?? this.goal,
        activity: activity ?? this.activity,
        prefs: prefs ?? this.prefs,
      );
}
