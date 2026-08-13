import 'package:flutter/material.dart';
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
          onTap: onTap,
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
        onTap: onTap,
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

class QStepperField extends StatelessWidget {
  final String unit;
  final int value;
  final VoidCallback onInc;
  final VoidCallback onDec;
  const QStepperField({super.key, required this.unit, required this.value, required this.onInc, required this.onDec});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.md),
        child: Column(
          children: [
            Text(unit, style: QText.body(size: 10, color: QColors.textMuted)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                QRoundIconButton(icon: Icons.remove, onTap: onDec, size: 26),
                SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.center, style: QText.number(size: 19, weight: FontWeight.w600))),
                QRoundIconButton(icon: Icons.add, onTap: onInc, size: 26),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
