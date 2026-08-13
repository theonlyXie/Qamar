import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;

    if (_ctrl.text != state.mealDraft) {
      _ctrl.value = TextEditingValue(text: state.mealDraft, selection: TextSelection.collapsed(offset: state.mealDraft.length));
    }

    final methods = [
      (label: t.photo, sub: t.photoSub, onTap: state.startAnalyze),
      (label: t.voice, sub: t.voiceSub, onTap: state.startAnalyze),
      (label: t.text, sub: t.textSub, onTap: state.presetMealDraftExample),
      (label: t.barcode, sub: t.barcodeSub, onTap: state.startAnalyze),
      (label: t.label, sub: t.labelSub, onTap: state.startAnalyze),
      (label: t.recent, sub: t.recentSub, onTap: state.startAnalyze),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.logMeal, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 4),
        Text(t.logSub, style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            for (final m in methods)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(QRadii.xl),
                  onTap: m.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep], begin: Alignment.topLeft, end: Alignment.bottomRight), radius: QRadii.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: QColors.blue.withOpacity(0.14), border: Border.all(color: QColors.violet.withOpacity(0.45)), borderRadius: BorderRadius.circular(12)),
                        ),
                        const Spacer(),
                        Text(m.label, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
                        Text(m.sub, style: QText.body(size: 12, color: QColors.textMuted)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: QDecor.card(color: QColors.cardDeep, radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.describeMeal, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: TextField(
                  controller: _ctrl,
                  onChanged: state.onMealDraftChanged,
                  style: QText.body(size: 15, color: QColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: t.mealPlaceholder,
                    hintStyle: QText.body(size: 15, color: QColors.textFaint),
                    filled: true,
                    fillColor: QColors.cardNavy,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.violet)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              QPrimaryButton(label: t.continueLabel, onTap: state.startAnalyze, height: 48),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Text(t.permissionNote, style: QText.body(size: 12, height: 18, color: QColors.textMuted)),
        ),
      ],
    );
  }
}
