/// A day's drinking water. Not food water, not tea, not juice — the taps
/// and bottles people actually log.
///
/// One running total in millilitres. Glasses and bottles are just how you
/// add, and how the card reads the same number back.
class Water {
  Water._();

  /// A drinking glass. Round so four glasses are a litre.
  static const glassMl = 250;

  /// A small bottle. Two glasses, six bottles to the 3 L goal.
  static const bottleMl = 500;

  /// A glass of tea — the Egyptian one, not a mug. Counts toward the total:
  /// tea is water with leaves in it, whatever the sugar does elsewhere.
  static const teaMl = 200;

  /// Starting point from Qamar's hydration note: two to three litres a day
  /// for an adult; Egypt heat sits at the top of that range.
  static const goalMl = 3000;

  static int mlFor(WaterUnit unit) => switch (unit) {
        WaterUnit.glass => glassMl,
        WaterUnit.bottle => bottleMl,
        WaterUnit.tea => teaMl,
      };
}

enum WaterUnit { glass, bottle, tea }

class WaterSip {
  final String? id;
  final WaterUnit unit;
  final int ml;
  final DateTime at;

  const WaterSip({
    this.id,
    required this.unit,
    required this.ml,
    required this.at,
  });

  WaterSip copyWith({String? id}) => WaterSip(
        id: id ?? this.id,
        unit: unit,
        ml: ml,
        at: at,
      );
}

/// Four numbers the Today card shows. All derived from millilitres.
class WaterStatus {
  final int ml;

  /// The day's goal: three litres, or the fasting day's two.
  final int goalMl;
  const WaterStatus(this.ml, {this.goalMl = Water.goalMl});

  double get litres => ml / 1000;
  double get litresLeft => ((goalMl - ml).clamp(0, goalMl)) / 1000;
  double get glasses => ml / Water.glassMl;
  double get bottles => ml / Water.bottleMl;
  double get progress => (ml / goalMl).clamp(0, 1).toDouble();
  bool get isEmpty => ml <= 0;

  /// 3, 1.5, 0.25 — no trailing zeros.
  static String qty(double n) {
    final two = n.toStringAsFixed(2);
    if (two.endsWith('00')) return n.round().toString();
    if (two.endsWith('0')) return n.toStringAsFixed(1);
    return two;
  }
}
