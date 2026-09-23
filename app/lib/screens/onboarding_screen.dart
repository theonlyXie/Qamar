import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/messages.dart';
import '../models/onboarding.dart';
import '../models/profile.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/dish_card.dart';
import '../widgets/moon.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// The composer's send button, for tests.
  static const sendKey = ValueKey('onboarding-send');
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _chat = ChatScroller();
  final _draftCtrl = TextEditingController();

  @override
  void dispose() {
    _chat.dispose();
    _draftCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final step = state.currentStep;

    // Any change in the transcript — a new message, or the typing bubble
    // appearing or going away — re-pins the list to the bottom.
    _chat.sync(state.msgs.length * 2 + (state.typing ? 1 : 0));
    if (_draftCtrl.text != state.draft) {
      _draftCtrl.value = TextEditingValue(text: state.draft, selection: TextSelection.collapsed(offset: state.draft.length));
    }

    // An input never appears before its question: each step's chips, wheels
    // and buttons wait until that step's question is on screen and Qamar has
    // stopped typing. At the end, "Let's start" waits for the last line too.
    final asked = state.questionShown;
    final stepChips = asked && step != null && (step.kind == StepKind.chips || step.kind == StepKind.multi) && !state.blocked;
    final stepNumber = asked && step != null && step.kind == StepKind.number;
    final stepDate = asked && step != null && step.kind == StepKind.date && !state.blocked;
    final canSkip = asked && step != null && step.kind == StepKind.text;
    final hasSubmit = (step == null
            ? !state.typing
            : asked && (step.kind == StepKind.number || step.kind == StepKind.multi || step.kind == StepKind.date)) &&
        !state.blocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: QColors.borderFaint))),
          child: Row(
            children: [
              // The way back to the welcome screen. The answers are kept:
              // starting again carries on from here.
              QBackButton(onTap: state.back, isAr: state.isAr),
              const SizedBox(width: 2),
              const QamarMoon(size: 36),
              const SizedBox(width: 10),
              // Where the conversation is goes on the line under the name:
              // a count, not a control, so it is words and not a pill that
              // looks tappable.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.brand, style: QText.display(size: 20, height: 24, color: const Color(0xFFF5F7FF))),
                    Text('${t.obSub} · ${state.iso('${(state.step + 1).clamp(1, kOnboardingSteps.length)}/${kOnboardingSteps.length}')}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 11, color: QColors.textMuted)),
                  ],
                ),
              ),
              // Switchable mid-conversation: the questions re-render in the
              // other language and the answers already given are kept.
              QLangToggle(lang: state.lang, onChanged: state.setLang),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _chat.controller,
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
              if (stepDate) ...[
                Row(
                  children: [
                    QWheelField(
                      unit: state.isAr ? 'يوم' : 'day',
                      value: state.profile.birthDay,
                      min: 1,
                      max: state.birthMonthLength,
                      loop: true,
                      onChanged: state.setBirthDay,
                    ),
                    const SizedBox(width: 8),
                    QWheelField(
                      unit: state.isAr ? 'شهر' : 'month',
                      value: state.profile.birthMonth,
                      min: 1,
                      max: 12,
                      loop: true,
                      format: (m) => (state.isAr ? _monthsAr : _monthsEn)[m - 1],
                      onChanged: state.setBirthMonth,
                    ),
                    const SizedBox(width: 8),
                    QWheelField(
                      unit: state.isAr ? 'سنة' : 'year',
                      value: state.profile.birthYear,
                      min: DateTime.now().year - 90,
                      max: DateTime.now().year - 10,
                      onChanged: state.setBirthYear,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _AgeReadout(state: state),
                const SizedBox(height: 10),
              ],
              if (stepNumber) ...[
                Row(
                  children: [
                    QWheelField(
                      unit: state.isAr ? 'سم' : 'cm',
                      value: state.profile.height,
                      min: 140,
                      max: 210,
                      onChanged: state.setHeight,
                    ),
                    const SizedBox(width: 8),
                    QWheelField(
                      unit: state.isAr ? 'كجم' : 'kg',
                      value: state.profile.weight,
                      min: 40,
                      max: 200,
                      onChanged: state.setWeight,
                    ),
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
                          // Until the question is on screen the box asks
                          // for nothing: what is typed waits for it (O7).
                          hintText: step != null && !asked
                              ? (state.isAr ? 'قمر بيكتب…' : 'Qamar is typing…')
                              : step != null
                                  ? (state.isAr ? 'اكتب ردك بكلامك…' : 'Or just type your answer…')
                                  : (state.isAr ? 'اسأل قمر أي حاجة…' : 'Ask Qamar anything…'),
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
                  // Send waits for the question too.
                  Opacity(
                    opacity: step != null && !asked ? 0.4 : 1,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Material(
                        color: Colors.transparent,
                        child: Ink(
                          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: QColors.brandGradient),
                          child: InkWell(
                            key: OnboardingScreen.sendKey,
                            customBorder: const CircleBorder(),
                            onTap: step != null && !asked ? null : state.sendDraft,
                            child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                          ),
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

/// Live feedback under the birth-date steppers: the age the date implies, and
/// an up-front warning when it falls under 18, so the eligibility rule is
/// visible before the user commits rather than only after.
class _AgeReadout extends StatelessWidget {
  final AppState state;
  const _AgeReadout({required this.state});

  @override
  Widget build(BuildContext context) {
    final age = state.profile.age;
    final adult = state.profile.isAdult;
    final label = state.isAr ? '${state.iso('$age')} سنة' : '$age years old';
    final warn = state.isAr ? 'قمر للبالغين ١٨ سنة أو أكتر' : 'Qamar is for adults 18 and over';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(adult ? Icons.cake_outlined : Icons.info_outline, size: 14, color: adult ? QColors.textMuted : QColors.amber),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            adult ? label : '$label · $warn',
            textAlign: TextAlign.center,
            style: QText.body(size: 12, color: adult ? QColors.textMuted : QColors.amber),
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
      case ObKind.dish:
        final dish = state.revealDish;
        final facts = state.revealDishFacts;
        if (dish == null || facts == null) return const SizedBox.shrink();
        return FractionallySizedBox(
          widthFactor: 0.88,
          alignment: Alignment.centerLeft,
          child: DishCard(
            dish: dish,
            facts: facts,
            targetKcal: state.target().kcal,
            slot: state.revealSlot,
            isAr: isAr,
            iso: state.iso,
          ),
        );
      case ObKind.save:
        return _SaveCard(state: state);
      case ObKind.trialOffer:
        return _TrialOfferCard(state: state);
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
    // Numbers the way the app draws them: Eastern digits in Arabic.
    String grams(int g) => state.isAr ? '${state.iso('$g')} جم' : '${g}g';
    final sexAr = p.gender == Gender.female ? 'أنثى' : 'ذكر';
    final sexEn = p.gender == Gender.female ? 'female' : 'male';
    final assumptions = state.isAr
        ? 'على أساس ${state.iso('${p.age}')} سنة · $sexAr · ${state.iso('${p.height}')} سم · ${state.iso('${p.weight}')} كجم · نشاط متوسط'
        : 'Based on ${p.age} yrs · $sexEn · ${p.height} cm · ${p.weight} kg · moderate activity';

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
                  child: Text(state.digits('${tg.kcal}'), style: QText.number(size: 36, weight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Text(t.kcalDay, style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _MacroBox(label: t.protein, grams: grams(tg.protein)),
                const SizedBox(width: 8),
                _MacroBox(label: t.carbs, grams: grams(tg.carbs)),
                const SizedBox(width: 8),
                _MacroBox(label: t.fat, grams: grams(tg.fat)),
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
  final String grams;
  const _MacroBox({required this.label, required this.grams});
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
            Text(grams, style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// The free week, offered after the reveal: a gift with its rules stated.
class _TrialOfferCard extends StatelessWidget {
  final AppState state;
  const _TrialOfferCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    const days = AppState.trialOfferDays;
    return FractionallySizedBox(
      widthFactor: 0.88,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: QColors.gold.withValues(alpha: 0.08),
          border: Border.all(color: QColors.gold.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAr ? '${state.iso('$days')} أيام من قمر كامل.' : '$days days of the full Qamar.',
              style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFE9ECFF)),
            ),
            const SizedBox(height: 4),
            Text(
              isAr
                  ? 'من غير بطاقة، ومفيش حاجة بتتجدد لوحدها. خطة بكرة، وصور وأسئلة أكتر.'
                  : 'No card, nothing renews. Tomorrow’s plan, and more photos and questions.',
              style: QText.body(size: 13, height: 20, color: QColors.textMid),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => state.acceptTrialOffer(),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(999))),
                      child: Text(isAr ? 'ابدأ' : 'Start', style: QText.body(size: 13, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: state.declineTrialOffer,
                  child: Text(isAr ? 'مش دلوقتي' : 'Not now', style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
                ),
              ],
            ),
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


const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
