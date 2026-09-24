import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'surface.dart';

/// A page's name at its top (the kit's page title: "Analysis", "Settings"),
/// with whatever the page keeps beside it at the end — a round button, the
/// Su chip. [back] puts the one back control before it.
class QPageTitle extends StatelessWidget {
  final String title;
  final bool isAr;
  final VoidCallback? back;
  final List<Widget> trailing;
  const QPageTitle({super.key, required this.title, required this.isAr, this.back, this.trailing = const []});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: QLayout.minTap,
        child: Row(children: [
          if (back != null) ...[
            QBackButton(onTap: back!, isAr: isAr),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.display(size: 24, ar: isAr)),
            ),
          ),
          for (final (i, w) in trailing.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            w,
          ],
        ]),
      );
}

/// A group's heading on a page (the kit's "Diet Plan", "Diets"): title 3,
/// with an action at the end when the group has one.
class QSectionTitle extends StatelessWidget {
  final String text;
  final bool isAr;
  final Widget? trailing;
  const QSectionTitle(this.text, {super.key, required this.isAr, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text(text, style: QText.display(size: 20, ar: isAr)))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A pastel card (the kit's lavender, lime, mint and coral cards): black
/// words on the colour, the card's corner, the kit's inset.
class PastelCard extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const PastelCard({super.key, required this.color, required this.child, this.padding = const EdgeInsets.all(20), this.radius = QRadii.card});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: QDecor.pastel(color, radius: radius),
        child: DefaultTextStyle.merge(style: const TextStyle(color: QColors.onPastel), child: child),
      );
}

/// A glyph in a circle of black at 12%, the way the kit marks a pastel
/// card's subject (its grain on the carbs card, its egg on protein).
class PastelGlyph extends StatelessWidget {
  final IconData icon;
  final double size;
  const PastelGlyph(this.icon, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.pastelTrack),
        child: Center(child: QIcon(icon, size: (size * 0.5).roundToDouble(), color: QColors.onPastel)),
      );
}

/// A button on a pastel: the kit's black capsule with white words (its
/// onboarding "Next"), drawn [height] tall and touched across 48; [light]
/// is the quieter white one with black words, for a second way on.
class QPastelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool light;
  const QPastelButton({super.key, required this.label, required this.onTap, this.icon, this.height = 36, this.light = false});

  @override
  Widget build(BuildContext context) {
    final ink = light ? QColors.onPastel : QColors.ink;
    return QTapArea(
      onTap: onTap,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: QSurface(
          shape: QSurfaceShape.capsule,
          tint: light ? (pressed ? QColors.inkSecondary : QColors.white) : (pressed ? QColors.surface : QColors.canvas),
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height >= 44 ? 18 : 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              QIcon(icon!, size: height >= 44 ? 18 : 16, color: ink),
              const SizedBox(width: 6),
            ],
            Text(label, style: QText.body(size: height >= 44 ? 15 : 13, weight: FontWeight.w600, color: ink)),
          ]),
        ),
      ),
    );
  }
}

/// The kit's segmented control: a white track, the chosen segment burgundy
/// with white words, the others black. Every segment takes a whole touch.
class QSegmented<T> extends StatelessWidget {
  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// A segment that cannot be chosen yet, drawn with a lock and the muted
  /// word (the Plan's Tomorrow on Lite). Tapping it still calls [onChanged]:
  /// the page says why.
  final Set<T> locked;
  final double height;
  const QSegmented({super.key, required this.segments, required this.value, required this.onChanged, this.locked = const {}, this.height = 48});

  static Key segmentKey(Object value) => ValueKey('segment-$value');

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: QDecor.segmentTrack,
      child: Row(children: [
        for (final (v, label) in segments)
          Expanded(
            child: QTapArea(
              key: segmentKey(v as Object),
              onTap: () {
                if (v == value) return;
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              label: label,
              builder: (context, pressed) => Semantics(
                selected: v == value,
                child: AnimatedContainer(
                  duration: still ? Duration.zero : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: v == value ? QDecor.segmentThumb : QDecor.segmentRest,
                  child: ExcludeSemantics(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (locked.contains(v)) ...[
                        QIcon(QIcons.locked, size: 14, color: v == value ? QColors.onAccent : QColors.onPastelSecondary),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QText.body(size: 15, weight: FontWeight.w500, color: v == value ? QColors.onAccent : QColors.onInk),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A grouped list (the kit's settings): rows on one card, no lines between
/// them, each a whole touch.
class QListGroup extends StatelessWidget {
  final List<Widget> rows;
  const QListGroup({super.key, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: QDecor.card(radius: QRadii.card),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      );
}

/// A row of a [QListGroup]: a glyph when it has one, its name, what it is
/// set to, and the chevron that says it opens something. With [trailing] it
/// carries its own control (a switch) and no chevron.
class QListRow extends StatelessWidget {
  final IconData? icon;
  final String label;
  final String? value;
  final String? sub;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// A row that ends something (Log out, delete): its words in burgundy.
  final bool destructive;
  const QListRow({super.key, this.icon, required this.label, this.value, this.sub, this.onTap, this.trailing, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final ink = destructive ? QColors.accentInk : QColors.ink;
    Widget body(bool pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          color: pressed ? QColors.surfaceRaised : Colors.transparent,
          padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 16, 12),
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            if (icon != null) ...[
              QIcon(icon!, size: 22, color: ink),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: QText.body(size: 16, color: ink)),
                if (sub != null && sub!.isNotEmpty) Text(sub!, style: QText.body(size: 13, color: QColors.inkSecondary)),
              ]),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: QText.body(size: 15, color: QColors.inkSecondary))),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: 8),
              QIcon(QIcons.forward, size: 20, color: destructive ? QColors.accentInk : QColors.ink),
            ],
          ]),
        );
    if (onTap == null) return body(false);
    return QTapArea(onTap: onTap, builder: (context, pressed) => body(pressed));
  }
}

/// The day's calories, the kit's gauge: a thick arc over the top of a
/// circle, black along the eaten part of the track from the start side (the
/// right in Arabic), with what is left in the middle and the target named
/// under the arc's far end. Drawn on the lavender card.
///
/// The near end carries no "0": the Arabic zero is a dot, and alone under
/// the arc it read as a stray mark.
class CalorieGauge extends StatelessWidget {
  /// How much of the day's target is eaten, 0 to 1.
  final double eaten;

  /// The figure in the middle and the word under it.
  final Widget centre;

  /// The target, under the far end.
  final String end;
  final double width;
  const CalorieGauge({super.key, required this.eaten, required this.centre, required this.end, this.width = 220});

  /// The gauge's height for its [width]: down to the foot of the disc.
  static double heightFor(double width) => width * 0.8;

  @override
  Widget build(BuildContext context) {
    // The target sits just under the arc's far end, outside the track.
    final labelTop = width * 0.6;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: width + 56,
      height: heightFor(width),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 28, top: 0, width: width, height: width, child: CustomPaint(painter: _GaugePainter(eaten.clamp(0.0, 1.0), rtl: rtl))),
          // The figure centred on the disc, the circle's own middle.
          Positioned(left: 28, top: 0, width: width, height: width, child: Center(child: centre)),
          PositionedDirectional(
            end: 0,
            top: labelTop,
            width: 56,
            child: Text(end, textAlign: TextAlign.center, maxLines: 1, style: QText.number(size: 13, color: QColors.onPastelSecondary)),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double eaten;
  final bool rtl;
  const _GaugePainter(this.eaten, {required this.rtl});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final r = size.width / 2 - stroke / 2;
    final c = Offset(size.width / 2, size.width / 2);
    final arc = Rect.fromCircle(center: c, radius: r);
    // Over the top from the left, a little past a half circle either side,
    // as the kit's gauge is (angles clockwise from the right).
    const sweep = math.pi * 1.1;
    const from = math.pi - (sweep - math.pi) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = QColors.pastelTrack;
    canvas.drawArc(arc, from, sweep, false, track);
    // The disc in the middle the figure sits on: white at a third, so it
    // rises off the lavender without a shadow.
    canvas.drawCircle(c, r - stroke, Paint()..color = QColors.white.withValues(alpha: 0.32));
    if (eaten <= 0) return;
    // From the start side: the left, or in Arabic the right, round the top.
    final fill = track..color = QColors.onPastel;
    if (rtl) {
      canvas.drawArc(arc, from + sweep, -sweep * eaten, false, fill);
    } else {
      canvas.drawArc(arc, from, sweep * eaten, false, fill);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.eaten != eaten || old.rtl != rtl;
}

/// A macro's card (the kit's Carbs and Protein cards): its pastel, its glyph
/// in a circle at the top end, its name, a bar and its figures.
class MacroTile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final double value;
  final String eaten;
  final String target;

  /// The figure's region for the orb's explain, and its mark.
  final Widget Function(Widget child)? wrapFigure;
  const MacroTile({super.key, required this.color, required this.icon, required this.label, required this.value, required this.eaten, required this.target, this.wrapFigure});

  @override
  Widget build(BuildContext context) {
    Widget figures = Row(children: [
      Flexible(child: Text(eaten, maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.onPastel))),
      const Spacer(),
      Text(target, maxLines: 1, softWrap: false, style: QText.number(size: 13, color: QColors.onPastelSecondary)),
    ]);
    if (wrapFigure != null) figures = wrapFigure!(figures);
    return PastelCard(
      color: color,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: AlignmentDirectional.centerEnd, child: PastelGlyph(icon, size: 34)),
          const SizedBox(height: 8),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.onPastel)),
          const SizedBox(height: 8),
          QBar(value: value, onPastel: true),
          const SizedBox(height: 6),
          figures,
        ],
      ),
    );
  }
}

/// An empty page's or an empty group's picture and words (the kit's empty
/// states): the mascot on a pastel disc, a title and a line under it.
class QEmptyState extends StatelessWidget {
  final String title;
  final String body;
  final Widget? action;
  final Widget mascot;
  final Color disc;
  const QEmptyState({super.key, required this.title, required this.body, required this.mascot, this.action, this.disc = QColors.lavender});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(shape: BoxShape.circle, color: disc),
            child: Center(child: mascot),
          ),
          const SizedBox(height: 20),
          QBalancedText(title, style: QText.display(size: 20, ar: QText.arabic(title))),
          const SizedBox(height: 6),
          QBalancedText(body, maxWidth: 300, style: QText.body(size: 15, color: QColors.inkSecondary)),
          if (action != null) ...[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      );
}
