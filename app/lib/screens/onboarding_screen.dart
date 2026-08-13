import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/messages.dart';
import '../models/onboarding.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _scroll = ScrollController();
  final _draftCtrl = TextEditingController();
  int _lastLen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _draftCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final step = state.currentStep;

    if (state.msgs.length != _lastLen || state.typing) {
      _lastLen = state.msgs.length;
      _scrollToBottom();
    }
    if (_draftCtrl.text != state.draft) {
      _draftCtrl.value = TextEditingValue(text: state.draft, selection: TextSelection.collapsed(offset: state.draft.length));
    }

    final stepChips = step != null && (step.kind == StepKind.chips || step.kind == StepKind.multi) && !state.blocked;
    final stepNumber = step != null && step.kind == StepKind.number;
    final canSkip = step != null && step.kind == StepKind.text;
    final hasSubmit = (step == null || step.kind == StepKind.number || step.kind == StepKind.multi) && !state.blocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: QColors.borderFaint))),
          child: Row(
            children: [
              ClipOval(child: Image.asset('assets/images/qamar_orb_sm.png', width: 36, height: 36, fit: BoxFit.cover)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.brand, style: QText.display(size: 20, height: 24, color: const Color(0xFFF5F7FF))),
                  Text(t.obSub, style: QText.body(size: 11, color: QColors.textMuted)),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: QColors.borderSoft), borderRadius: BorderRadius.circular(999)),
                child: Text('${(state.step + 1).clamp(1, kOnboardingSteps.length)}/${kOnboardingSteps.length}',
                    style: QText.number(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            itemCount: state.msgs.length + (state.typing ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              if (i >= state.msgs.length) return const _TypingBubble();
              return _MessageBubble(msg: state.msgs[i]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 34),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: QColors.borderFaint))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stepChips) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: step.options.map((o) {
                    final selected = step.kind == StepKind.multi
                        ? state.profile.prefs.contains(o.value)
                        : (step.id == 'goal'
                            ? state.profile.goal.name == o.value
                            : step.id == 'activity'
                                ? state.profile.activity == o.value
                                : false);
                    return QPillChip(label: o.label(state.isAr), selected: selected, onTap: () => state.pickOption(o));
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
              if (stepNumber) ...[
                Row(
                  children: [
                    QStepperField(unit: state.isAr ? 'سنة' : 'age', value: state.profile.age, onInc: () => state.bumpAge(1), onDec: () => state.bumpAge(-1)),
                    const SizedBox(width: 8),
                    QStepperField(unit: state.isAr ? 'سم' : 'cm', value: state.profile.height, onInc: () => state.bumpHeight(1), onDec: () => state.bumpHeight(-1)),
                    const SizedBox(width: 8),
                    QStepperField(unit: state.isAr ? 'كجم' : 'kg', value: state.profile.weight, onInc: () => state.bumpWeight(1), onDec: () => state.bumpWeight(-1)),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (hasSubmit) ...[
                QPrimaryButton(
                  label: step == null ? (state.isAr ? 'يلا نبدأ' : 'Let’s start') : t.next,
                  onTap: state.primarySubmit,
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: TextField(
                        controller: _draftCtrl,
                        onChanged: state.onDraftChanged,
                        onSubmitted: (_) => state.sendDraft(),
                        style: QText.body(size: 15, color: QColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: step != null ? (state.isAr ? 'اكتب ردك بكلامك…' : 'Or just type your answer…') : (state.isAr ? 'اسأل قمر أي حاجة…' : 'Ask Qamar anything…'),
                          hintStyle: QText.body(size: 15, color: QColors.textFaint),
                          filled: true,
                          fillColor: QColors.cardDeep,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: QColors.borderSoft)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: QColors.borderSoft)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: QColors.violet)),
                        ),
                      ),
                    ),
                  ),
                  if (canSkip)
                    TextButton(onPressed: state.skipStep, child: Text(t.skip, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textMuted))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Material(
                      color: Colors.transparent,
                      child: Ink(
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: QColors.brandGradient),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: state.sendDraft,
                          child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: QDecor.card(color: QColors.cardMid, radius: 18),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [_Dot(0), SizedBox(width: 5), _Dot(1), SizedBox(width: 5), _Dot(2)]),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  final int i;
  const _Dot(this.i);
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final phase = (_c.value + widget.i * 0.2) % 1.0;
        final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
        return Opacity(opacity: opacity.clamp(0.3, 1.0), child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: QColors.violet)));
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ObMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;

    switch (msg.kind) {
      case ObKind.q:
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: QDecor.card(color: QColors.cardMid, radius: 18),
              child: Text(msg.text(isAr), style: QText.body(size: 15, height: 23, color: QColors.textPrimary)),
            ),
          ),
        );
      case ObKind.u:
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.circular(18)),
              child: Text(msg.text(isAr), style: QText.body(size: 15, height: 23, color: Colors.white)),
            ),
          ),
        );
      case ObKind.target:
        return _TargetCard(state: state);
      case ObKind.save:
        return _SaveCard(state: state);
    }
  }
}

class _TargetCard extends StatelessWidget {
  final AppState state;
  const _TargetCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final tg = state.target();
    final p = state.profile;
    final assumptions = state.isAr
        ? 'على أساس ${state.iso('${p.age}')} سنة · ${state.iso('${p.height}')} سم · ${state.iso('${p.weight}')} كجم · نشاط متوسط'
        : 'Based on ${p.age} yrs · ${p.height} cm · ${p.weight} kg · moderate activity';

    return FractionallySizedBox(
      widthFactor: 0.88,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: QColors.borderStrong),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: QColors.blue.withOpacity(0.18), blurRadius: 34)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.dailyTarget, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.4)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ShaderMask(
                  shaderCallback: (r) => QColors.blueCyanGradient.createShader(r),
                  child: Text('${tg.kcal}', style: QText.number(size: 36, weight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(t.kcalDay, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MacroBox(label: t.protein, g: tg.protein),
                const SizedBox(width: 8),
                _MacroBox(label: t.carbs, g: tg.carbs),
                const SizedBox(width: 8),
                _MacroBox(label: t.fat, g: tg.fat),
              ],
            ),
            const SizedBox(height: 14),
            Text(assumptions, style: QText.body(size: 12, height: 18, color: QColors.textMuted)),
            const SizedBox(height: 6),
            Text(t.estimateNote, style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
          ],
        ),
      ),
    );
  }
}

class _MacroBox extends StatelessWidget {
  final String label;
  final int g;
  const _MacroBox({required this.label, required this.g});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: QDecor.card(color: QColors.cardNavy, border: QColors.borderFaint, radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: QText.body(size: 11, color: QColors.textMuted)),
            Text('${g}g', style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _SaveCard extends StatelessWidget {
  final AppState state;
  const _SaveCard({required this.state});
  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return FractionallySizedBox(
      widthFactor: 0.88,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: QColors.violet.withOpacity(0.1),
          border: Border.all(color: QColors.violet.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.saveTitle, style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFE9ECFF))),
            const SizedBox(height: 4),
            Text(t.saveSub, style: QText.body(size: 13, height: 20, color: QColors.textMid)),
            const SizedBox(height: 8),
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: state.dismissSave,
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(999))),
                      child: Text(t.saveNow, style: QText.body(size: 12, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: state.dismissSave, child: Text(t.saveLater, style: QText.body(size: 12, weight: FontWeight.w500, color: QColors.textMuted))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
