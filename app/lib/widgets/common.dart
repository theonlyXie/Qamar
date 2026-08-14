import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';

class QPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Gradient gradient;
  const QPrimaryButton({super.key, required this.label, required this.onTap, this.height = 52, this.gradient = QColors.brandGradient});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.lg),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Ink(
            decoration: QDecor.gradientButton(gradient: gradient),
            child: Center(
              child: Text(label, style: QText.body(size: 16, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

class QOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Color color;
  const QOutlineButton({super.key, required this.label, required this.onTap, this.height = 44, this.color = QColors.textMuted});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: QColors.borderSoft),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(QRadii.md)),
          backgroundColor: Colors.transparent,
        ),
        child: Text(label, style: QText.body(size: 14, weight: FontWeight.w500, color: color)),
      ),
    );
  }
}

class QPillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const QPillChip({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.pill),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? QColors.violet.withOpacity(0.18) : QColors.cardDeep,
            border: Border.all(color: selected ? QColors.violet : QColors.borderSoft),
            borderRadius: BorderRadius.circular(QRadii.pill),
          ),
          child: Text(label, style: QText.body(size: 14, weight: FontWeight.w500, color: selected ? const Color(0xFFE9ECFF) : QColors.textMid)),
        ),
      ),
    );
  }
}

class SuCoinIcon extends StatelessWidget {
  final double size;
  const SuCoinIcon({super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset('assets/images/su_coin.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}

class ConfidenceBadge extends StatelessWidget {
  final bool high;
  final String label;
  const ConfidenceBadge({super.key, required this.high, required this.label});
  @override
  Widget build(BuildContext context) {
    final color = high ? QColors.green : QColors.amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: color.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.pill)),
      child: Text(label, style: QText.body(size: 11, weight: FontWeight.w500, color: color)),
    );
  }
}

class QRoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const QRoundIconButton({super.key, required this.icon, required this.onTap, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(side: BorderSide(color: QColors.borderSoft)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, size: size * 0.5, color: QColors.textMid),
        ),
      ),
    );
  }
}

/// An iOS-style value wheel: scroll to choose, with a selection tick on every
/// notch. Replaces the old +/- stepper, which needed one tap per unit — 30 of
/// them to move a birth year.
///
/// Values are supplied as a range so the wheel can be as long as it needs to
/// be; [format] renders each one (month names, for instance).
class QWheelField extends StatefulWidget {
  final String unit;
  final int value;
  final int min;
  final int max;

  /// Wrap past the ends — right for months and days, wrong for a birth year.
  final bool loop;
  final String Function(int)? format;
  final ValueChanged<int> onChanged;

  const QWheelField({
    super.key,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.loop = false,
    this.format,
  });

  @override
  State<QWheelField> createState() => _QWheelFieldState();
}

class _QWheelFieldState extends State<QWheelField> {
  late FixedExtentScrollController _ctrl;

  /// True while we are moving the wheel ourselves. Without this the sequence
  /// scroll -> onChanged -> parent notifies -> didUpdateWidget -> jumpToItem
  /// -> onSelectedItemChanged -> onChanged loops forever, and a wheel stuck in
  /// that loop starves the gesture arena: every button on the screen stops
  /// responding, including the one that submits the step.
  bool _syncing = false;

  int get _count => widget.max - widget.min + 1;
  int get _index => (widget.value - widget.min).clamp(0, _count - 1);

  @override
  void initState() {
    super.initState();
    _ctrl = FixedExtentScrollController(initialItem: _index);
  }

  @override
  void didUpdateWidget(covariant QWheelField old) {
    super.didUpdateWidget(old);
    if (!_ctrl.hasClients) return;

    // Only correct the wheel when it genuinely disagrees with the value —
    // e.g. the day was clamped because the month changed under it. Never while
    // the user is still moving it, and never during this build.
    final needsSync = _ctrl.selectedItem != _index;
    final rangeChanged = widget.min != old.min || widget.max != old.max;
    if (!needsSync && !rangeChanged) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      if (_ctrl.position.isScrollingNotifier.value) return; // still flinging
      if (_ctrl.selectedItem == _index) return;
      _syncing = true;
      _ctrl.jumpToItem(_index);
      // Cleared a frame later: jumpToItem's notification arrives after this.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncing = false);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = [
      for (var v = widget.min; v <= widget.max; v++)
        Center(
          child: Text(
            widget.format?.call(v) ?? '$v',
            maxLines: 1,
            style: QText.number(size: 19, weight: FontWeight.w600),
          ),
        ),
    ];

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.md),
        child: Column(
          children: [
            Text(widget.unit, style: QText.body(size: 10, color: QColors.textMuted)),
            const SizedBox(height: 2),
            SizedBox(
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The selection band, so it is obvious what the wheel is on.
                  IgnorePointer(
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: QColors.violet.withValues(alpha: 0.12),
                        border: Border.symmetric(
                          horizontal: BorderSide(color: QColors.violet.withValues(alpha: 0.45)),
                        ),
                      ),
                    ),
                  ),
                  ListWheelScrollView.useDelegate(
                    controller: _ctrl,
                    itemExtent: 32,
                    diameterRatio: 1.5,
                    perspective: 0.004,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) {
                      if (_syncing) return;
                      final next = widget.min + (i % _count);
                      if (next == widget.value) return;
                      HapticFeedback.selectionClick();
                      widget.onChanged(next);
                    },
                    childDelegate: widget.loop
                        ? ListWheelChildLoopingListDelegate(children: children)
                        : ListWheelChildListDelegate(children: children),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact AR/EN switch.
///
/// The only language control used to be a row at the bottom of the You screen,
/// which is unreachable until onboarding is finished — so someone who does not
/// read Arabic had to complete an Arabic conversation before they could switch
/// out of it. This goes wherever that matters: the welcome screen, the
/// onboarding header, the scan header.
class QLangToggle extends StatelessWidget {
  final AppLang lang;
  final ValueChanged<AppLang> onChanged;

  /// Slightly larger, for screens with room for it.
  final bool large;

  const QLangToggle({super.key, required this.lang, required this.onChanged, this.large = false});

  @override
  Widget build(BuildContext context) {
    final h = large ? 34.0 : 28.0;
    return Container(
      height: h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: QColors.cardDeep.withValues(alpha: 0.9),
        border: Border.all(color: QColors.borderSoft),
        borderRadius: BorderRadius.circular(999),
      ),
      // Fixed left-to-right so the two options never swap places when the
      // direction flips — a control that moves as you use it is disorienting.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(label: 'ع', selected: lang == AppLang.ar, large: large, onTap: () => onChanged(AppLang.ar)),
            _Segment(label: 'EN', selected: lang == AppLang.en, large: large, onTap: () => onChanged(AppLang.en)),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final bool large;
  final VoidCallback onTap;
  const _Segment({required this.label, required this.selected, required this.large, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: large ? 14 : 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? QColors.brandGradient : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: QText.body(
              size: large ? 13 : 12,
              weight: FontWeight.w600,
              color: selected ? Colors.white : QColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps a message list pinned to the newest message.
///
/// A single post-frame `animateTo(maxScrollExtent)` is not enough: the extent
/// is measured before tall content (the target card, a meal breakdown) has
/// finished laying out, so the list stops short and the newest message stays
/// off screen until the user scrolls by hand. This re-settles a moment later,
/// and gets out of the way if the user has deliberately scrolled up to read
/// back through the conversation.
class ChatScroller {
  final ScrollController controller = ScrollController();
  Timer? _settle;
  int _signature = -1;

  /// Distance from the bottom within which we still consider the user "at the
  /// bottom" and safe to auto-scroll.
  static const _stickyWindow = 160.0;

  /// Call from build with a value that changes whenever the content does.
  void sync(int signature) {
    if (signature == _signature) return;
    _signature = signature;
    _schedule();
  }

  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _go(animate: true));
    _settle?.cancel();
    // Second pass once late-laid-out content has grown the extent.
    _settle = Timer(const Duration(milliseconds: 240), () => _go(animate: false));
  }

  void _go({required bool animate}) {
    if (!controller.hasClients) return;
    final pos = controller.position;
    // Never yank the view away from someone reading earlier messages.
    if (pos.pixels < pos.maxScrollExtent - _stickyWindow && !animate) return;
    if (animate) {
      controller.animateTo(pos.maxScrollExtent,
          duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    } else {
      controller.jumpTo(pos.maxScrollExtent);
    }
  }

  void dispose() {
    _settle?.cancel();
    controller.dispose();
  }
}
