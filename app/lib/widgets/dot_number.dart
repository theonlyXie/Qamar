import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// A figure drawn in dots, the way Nothing draws its clocks and counters (the
/// mono-glass skill): Today's calories left, the water, a streak.
///
/// Every character is a 5 × 7 grid of dots, one dot per stroke. The grids are
/// drawn here for both digit sets the app shows — Western 0–9 and the
/// Arabic-Indic ٠–٩ the Arabic interface uses — so the figure looks the same
/// in either language (no open dot-matrix face carries Arabic-Indic digits).
/// A character with no grid (a letter, a unit) is not drawn: units sit beside
/// the figure in text, where they can be read and translated.
///
/// It is one figure to a screen reader: [text] is its label, and the dots are
/// not read.
class DotNumber extends StatelessWidget {
  final String text;

  /// The figure's height: seven rows of dots. The width follows from it.
  final double height;
  final Color color;

  /// Draw the unlit dots too, faintly, as a Glyph panel does.
  final bool grid;

  /// What a screen reader says, when [text] alone would not be enough ("960
  /// kcal left").
  final String? semanticsLabel;

  const DotNumber(this.text, {super.key, required this.height, this.color = QColors.ink, this.grid = false, this.semanticsLabel});

  /// The distance between dot centres at [height].
  static double pitch(double height) => height / DotGlyphs.rows;

  /// How wide [text] is drawn at [height]: each glyph's columns, a one-dot gap
  /// between glyphs.
  static double widthOf(String text, double height) {
    final p = pitch(height);
    var cols = 0;
    var n = 0;
    for (final ch in text.split('')) {
      final g = DotGlyphs.of(ch);
      if (g == null) continue;
      cols += g.first.length;
      n++;
    }
    return n == 0 ? 0 : (cols + (n - 1)) * p;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel ?? text,
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(widthOf(text, height), height),
        painter: _DotPainter(text, color: color, grid: grid),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  final String text;
  final Color color;
  final bool grid;
  const _DotPainter(this.text, {required this.color, required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    final p = size.height / DotGlyphs.rows;
    final r = p * 0.36;
    final lit = Paint()..color = color;
    final unlit = Paint()..color = color.withValues(alpha: color.a * 0.12);
    var x = 0.0;
    for (final ch in text.split('')) {
      final g = DotGlyphs.of(ch);
      if (g == null) continue;
      for (var row = 0; row < g.length; row++) {
        for (var col = 0; col < g[row].length; col++) {
          final on = g[row].codeUnitAt(col) == 0x23; // '#'
          if (!on && !grid) continue;
          canvas.drawCircle(Offset(x + col * p + p / 2, row * p + p / 2), r, on ? lit : unlit);
        }
      }
      x += (g.first.length + 1) * p;
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.text != text || old.color != color || old.grid != grid;
}

/// The dot grids: seven rows each, '#' a dot, '.' none.
abstract final class DotGlyphs {
  static const rows = 7;

  static List<String>? of(String ch) => _glyphs[ch];

  static const _glyphs = <String, List<String>>{
    // Western digits.
    '0': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
    '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
    '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
    '3': ['.###.', '#...#', '....#', '..##.', '....#', '#...#', '.###.'],
    '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
    '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
    '6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
    '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
    '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
    '9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
    // Arabic-Indic digits.
    '٠': ['.....', '.....', '..#..', '.#.#.', '..#..', '.....', '.....'],
    '١': ['..#..', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
    '٢': ['.#..#', '.#.#.', '.##..', '.#...', '.#...', '.#...', '.#...'],
    '٣': ['#.#.#', '#####', '#....', '#....', '#....', '#....', '#....'],
    '٤': ['..##.', '.#...', '.#...', '..##.', '.#...', '.#...', '..###'],
    '٥': ['..#..', '.#.#.', '#...#', '#...#', '#...#', '#...#', '.###.'],
    '٦': ['####.', '...#.', '...#.', '...#.', '...#.', '...#.', '...#.'],
    '٧': ['#...#', '#...#', '.#.#.', '.#.#.', '.#.#.', '..#..', '..#..'],
    '٨': ['..#..', '..#..', '.#.#.', '.#.#.', '.#.#.', '#...#', '#...#'],
    '٩': ['.##..', '#..#.', '#..#.', '.###.', '...#.', '...#.', '...#.'],
    // Marks.
    ' ': ['..', '..', '..', '..', '..', '..', '..'],
    '.': ['.', '.', '.', '.', '.', '.', '#'],
    ',': ['..', '..', '..', '..', '..', '.#', '#.'],
    '٫': ['..', '..', '..', '..', '..', '.#', '#.'],
    '٬': ['.#', '#.', '..', '..', '..', '..', '..'],
    ':': ['.', '.', '#', '.', '#', '.', '.'],
    '/': ['....#', '...#.', '...#.', '..#..', '.#...', '.#...', '#....'],
    '-': ['...', '...', '...', '###', '...', '...', '...'],
    '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
    '%': ['##..#', '##.#.', '...#.', '..#..', '.#...', '.#.##', '#..##'],
    '٪': ['##..#', '##.#.', '...#.', '..#..', '.#...', '.#.##', '#..##'],
    '×': ['.....', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '.....'],
  };

  /// Every character with a grid.
  static Iterable<String> get characters => _glyphs.keys;

  /// The widest glyph, in dots.
  static int get widest => _glyphs.values.map((g) => g.first.length).reduce(math.max);
}
