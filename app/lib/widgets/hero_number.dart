import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/text_styles.dart';

/// The screen's one hero figure (the qamar-design skill): a large numeral in
/// the interface's own face, bold, its digits tabular so a changing count
/// holds its place. Arabic-Indic digits come from the face's Arabic
/// fallback, so the figure reads the same in either language; its unit sits
/// beside it or under it, in text, where it can be read and translated.
///
/// One figure to a screen reader: [semanticsLabel], or the figure itself, is
/// what is read.
class HeroNumber extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  final String? semanticsLabel;
  const HeroNumber(this.text, {super.key, this.size = heroSize, this.color = QColors.ink, this.semanticsLabel});

  /// The hero's size, on the figure scale.
  static const heroSize = 56.0;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticsLabel ?? text,
        excludeSemantics: true,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: QText.number(size: size, height: size, weight: FontWeight.w700, color: color),
        ),
      );
}
