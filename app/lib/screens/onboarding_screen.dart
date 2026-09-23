import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/trial_words.dart';
import '../models/messages.dart';
import '../models/onboarding.dart';
import '../models/profile.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/motion.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/dish_card.dart';
import '../widgets/dot_number.dart';
import '../widgets/glass.dart';

/// The consultation (S06–S14), drawn the way a conversation with an
/// assistant already looks on the phone: the mono-glass chat pattern, as Ask
/// Qamar draws it (widgets/ask_qamar_overlay.dart).
///
/// A black page. At the top, the way back (a glass circle), Qamar's name and
/// one line saying where the consultation is. Qamar's words are plain text
/// across the page; the person's answers sit in a grey bubble on their side.
/// Each question's answers (chips, wheels, Continue) wait under it, and under
/// them one glass field for typing an answer instead. The last question is
/// the reveal: a dish, the day's target (the screen's one figure in dots),
/// and "Let's start".
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// The composer's send button, for tests.
  static const sendKey = ValueKey('onboarding-send');

  /// The conversation, drawn from the bottom up (O7).
  static const transcriptKey = ValueKey('onboarding-transcript');

  /// The dock under it: the step's inputs and the composer.
  static const dockKey = ValueKey('onboarding-dock');

  /// The header's one line of state.
  static const statusKey = ValueKey('onboarding-status');

  /// Where the consultation is, in words, for the header's line: "Question 3
  /// of 8", counted on the person's own route (general guidance asks fewer);
  /// the reveal's wait, said as what it is; "All done"; or nothing once a
  /// gate has stopped it.
  static String statusLine(AppState s) {
    final ar = s.isAr;
    if (s.blocked) return '';
    final step = s.currentStep;
    if (step == null) {
      if (!s.typing) return ar ? 'خلصنا' : 'All done';
      return s.generalGuidance ? (ar ? 'قربنا نخلص…' : 'Almost done…') : (ar ? 'بحسبلك هدفك…' : 'Setting your target…');
    }
    final route = [
      for (final st in kOnboardingSteps)
        if (!(s.generalGuidance && kGeneralGuidanceSkips.contains(st.id))) st.id,
    ];
    final at = route.indexOf(step.id) + 1;
    return ar ? 'سؤال ${s.iso('$at')} من ${s.iso('${route.length}')}' : 'Question $at of ${route.length}';
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _chat = ChatScroller();
  final _draftCtrl = TextEditingController();

  static const _typingKey = ValueKey('ob-typing');

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
    final isAr = state.isAr;
    final step = state.currentStep;

    // Any change in the transcript (a new message, or the typing dot coming
    // or going) re-pins the list to the newest message.
    _chat.sync(state.msgs.length * 2 + (state.typing ? 1 : 0));
    if (_draftCtrl.text != state.draft) {
      _draftCtrl.value = TextEditingValue(text: state.draft, selection: TextSelection.collapsed(offset: state.draft.length));
    }

    // An input never appears before its question (O7): each step's chips,
    // wheels and buttons wait until its question is on screen and Qamar has
    // stopped typing. At the end, "Let's start" waits for the last line too.
    final asked = state.questionShown;
    final open = !state.blocked;
    final waiting = state.typing || (step != null && !asked);
    final chips = asked && open && (step?.kind == StepKind.chips || step?.kind == StepKind.multi);
    final multi = chips && step?.kind == StepKind.multi;
    final date = asked && open && step?.kind == StepKind.date;
    final body = asked && open && step?.kind == StepKind.number;
    final end = open && step == null && !state.typing;
    final submit = end || date || body || multi;

    final String? submitLabel = end
        ? (isAr ? 'يلا نبدأ' : 'Let’s start')
        : multi && state.profile.prefs.isEmpty
            // Nothing picked is an answer too, and the button says it.
            ? (isAr ? 'مفيش حاجة' : 'Nothing to avoid')
            : submit
                ? t.next
                : null;

    // What the field takes now: nothing while Qamar types (what is typed
    // waits for the question), the answer, the name the reveal asked for, or
    // a question for Qamar.
    final placeholder = !open
        ? t.chatPlaceholder
        : waiting
            ? (isAr ? 'قمر بيكتب…' : 'Qamar is typing…')
            : step != null
                ? (isAr ? 'أو اكتب ردك' : 'Or type your answer')
                : state.nameAsked
                    ? (isAr ? 'اسمك' : 'Your name')
                    : t.chatPlaceholder;
    final canSend = !waiting && state.draft.trim().isNotEmpty;

    Widget? inputs;
    if (chips || date || body || submit) {
      inputs = _Entrance(
        key: ValueKey('inputs-${step?.id ?? 'end'}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: QSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chips && step != null) ...[
                Wrap(
                  spacing: QSpace.sm,
                  runSpacing: QSpace.sm,
                  children: [
                    for (final o in step.options)
                      // "Nothing" is the button under a question that can be
                      // answered with several (the multi step).
                      if (!(multi && o.value == 'none'))
                        QPillChip(
                          label: o.label(isAr),
                          selected: multi && state.profile.prefs.contains(o.value),
                          onTap: () => state.pickOption(o),
                        ),
                  ],
                ),
                if (step.id == 'consent') _LegalLinks(isAr: isAr),
                const SizedBox(height: QSpace.md),
              ],
              if (date) ...[
                _DateWheels(state: state),
                const SizedBox(height: QSpace.sm),
                _AgeReadout(state: state),
                const SizedBox(height: QSpace.md),
              ],
              if (body) ...[
                Row(
                  children: [
                    QWheelField(
                      unit: isAr ? 'سم' : 'cm',
                      value: state.profile.height,
                      min: 140,
                      max: 210,
                      format: (v) => state.digits('$v'),
                      onChanged: state.setHeight,
                    ),
                    const SizedBox(width: QSpace.sm),
                    QWheelField(
                      unit: isAr ? 'كجم' : 'kg',
                      value: state.profile.weight,
                      min: 40,
                      max: 200,
                      format: (v) => state.digits('$v'),
                      onChanged: state.setWeight,
                    ),
                  ],
                ),
                const SizedBox(height: QSpace.md),
              ],
              if (submitLabel != null) ...[
                QPrimaryButton(label: submitLabel, onTap: state.primarySubmit),
                const SizedBox(height: QSpace.md),
              ],
            ],
          ),
        ),
      );
    }

    final count = state.msgs.length + (state.typing ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(state: state),
        // Drawn from the bottom up (O7): each question sits right on the
        // answers it asks for, and the empty space is sky above the
        // conversation instead of a gap between a question and its answers.
        Expanded(
          child: _TopFade(
            child: ListView.builder(
              key: OnboardingScreen.transcriptKey,
              controller: _chat.controller,
              reverse: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(QSpace.page, QSpace.lg, QSpace.page, QSpace.md),
              itemCount: count,
              // Each message keeps its own entrance as the list grows under
              // it: only what is new arrives.
              findChildIndexCallback: (key) {
                if (key == _typingKey) return state.typing ? 0 : null;
                if (key is! ObjectKey) return null;
                final j = state.msgs.indexWhere((m) => identical(m, key.value));
                return j < 0 ? null : (state.typing ? 1 : 0) + state.msgs.length - 1 - j;
              },
              itemBuilder: (context, i) {
                // Newest first: the typing dot while Qamar types, then the
                // messages from the latest back.
                if (state.typing && i == 0) return const _TypingDot(key: _typingKey);
                final msg = state.msgs[state.msgs.length - 1 - (i - (state.typing ? 1 : 0))];
                return _Appear(key: ObjectKey(msg), child: _Message(msg: msg));
              },
            ),
          ),
        ),
        Padding(
          key: OnboardingScreen.dockKey,
          padding: const EdgeInsets.fromLTRB(QSpace.md, QSpace.xs, QSpace.md, QSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Between one question and the next the dock keeps its height,
              // so the conversation above it stays put; the inputs' entrance
              // starts on the frame their question paints. A gate that stops
              // the consultation lets the height go.
              QKeepHeight(child: open ? inputs : const SizedBox.shrink()),
              _Composer(
                state: state,
                ctrl: _draftCtrl,
                placeholder: placeholder,
                onSend: canSend ? state.sendDraft : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The way back, the name, and one line of state; the language switch on
/// the far side, so the questions can be read in the other language at any
/// point, with the answers kept. The name is centred on the screen while it
/// fits between the two; at large text it gives way to them, never the
/// other way round.
class _Header extends StatelessWidget {
  final AppState state;
  const _Header({required this.state});

  @override
  Widget build(BuildContext context) {
    final line = OnboardingScreen.statusLine(state);
    final scale = MediaQuery.textScalerOf(context);
    final lineHeight = scale.scale(18);
    return Padding(
      padding: const EdgeInsets.fromLTRB(QSpace.sm, 6, QSpace.sm, QSpace.xs),
      child: SizedBox(
        height: math.max(QLayout.minTap, scale.scale(22) + lineHeight),
        child: NavigationToolbar(
          middleSpacing: QSpace.sm,
          // Back to the welcome. The answers are kept: starting again
          // carries on from here.
          leading: Center(widthFactor: 1, child: QBackButton(onTap: state.back, isAr: state.isAr)),
          middle: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.t.brand, maxLines: 1, overflow: TextOverflow.ellipsis, style: QText.body(size: 17, weight: FontWeight.w600)),
              // The line keeps its height when it has nothing to say, so the
              // name never jumps.
              SizedBox(
                key: OnboardingScreen.statusKey,
                height: lineHeight,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Padding(
                    key: ValueKey(line),
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: QText.body(size: 12, height: 16, color: QColors.inkTertiary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          trailing: Center(widthFactor: 1, child: QLangToggle(lang: state.lang, onChanged: state.setLang)),
        ),
      ),
    );
  }
}

/// The transcript's top edge fades under the header instead of stopping at
/// a rule: what scrolls away goes behind it.
class _TopFade extends StatelessWidget {
  final Widget child;
  const _TopFade({required this.child});

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.transparent, QColors.canvas, QColors.canvas],
          stops: [0, 24 / r.height.clamp(24, double.infinity), 1],
        ).createShader(r),
        child: child,
      );
}

/// One line of the conversation. Qamar's words are plain text across the
/// page, the person's own in a grey bubble on their side; the reveal's cards
/// take the page's width.
class _Message extends StatelessWidget {
  final ObMessage msg;
  const _Message({required this.msg});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final Widget child;
    switch (msg.kind) {
      case ObKind.q:
        child = Semantics(
          container: true,
          label: '${isAr ? 'قمر' : 'Qamar'}: ${msg.text(isAr)}',
          excludeSemantics: true,
          child: Text(msg.text(isAr), style: QText.body(size: 17, height: 26)),
        );
      case ObKind.u:
        child = Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Semantics(
            container: true,
            label: '${isAr ? 'ردك' : 'You'}: ${msg.text(isAr)}',
            excludeSemantics: true,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
              padding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: 11),
              decoration: BoxDecoration(color: QColors.surfaceHigh, borderRadius: BorderRadius.circular(QRadii.card)),
              child: Text(msg.text(isAr), style: QText.body(size: 17, height: 24)),
            ),
          ),
        );
      case ObKind.target:
        child = _TargetCard(state: state);
      case ObKind.dish:
        final dish = state.revealDish;
        final facts = state.revealDishFacts;
        if (dish == null || facts == null) return const SizedBox.shrink();
        child = DishCard(dish: dish, facts: facts, targetKcal: state.target().kcal, slot: state.revealSlot, isAr: isAr, iso: state.iso);
      case ObKind.save:
        child = _SaveCard(state: state);
      case ObKind.trialOffer:
        child = _TrialOfferCard(state: state);
    }
    return Padding(padding: const EdgeInsets.only(top: QSpace.lg), child: child);
  }
}

/// Qamar is typing: one white dot, breathing where the next line will start,
/// as the conversation's own does. Under reduce-motion it holds still, and
/// the field says the words ("Qamar is typing…").
class _TypingDot extends StatefulWidget {
  const _TypingDot({super.key});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: QSpace.lg + 6, bottom: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ExcludeSemantics(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = Curves.easeInOut.transform(_c.value);
                return Transform.scale(
                  scale: 0.72 + 0.28 * v,
                  child: Opacity(
                    opacity: 0.55 + 0.45 * v,
                    child: const SizedBox(width: 14, height: 14, child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: QColors.ink))),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of the conversation arriving: a short fade with 8 points of rise
/// on the settle spring, so the eye is told where the new words are without
/// being pulled. Under reduce-motion, the fade alone.
class _Appear extends StatefulWidget {
  final Widget child;
  const _Appear({super.key, required this.child});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    QSpring.drive(_c, 1, still: MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value.clamp(0.0, 1.0);
        final faded = Opacity(opacity: v, child: child);
        return still ? faded : Transform.translate(offset: Offset(0, 8 * (1 - v)), child: faded);
      },
      child: widget.child,
    );
  }
}

/// A step's inputs arriving (O7): from the first frame their question is on
/// screen they fade in and rise the last few points into place, ease-out, so
/// they arrive and stop. With reduced motion they are simply there.
class _Entrance extends StatelessWidget {
  final Widget child;
  const _Entrance({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: still ? Duration.zero : QMotion.riseIn,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

/// The documents the consent is given under, a touch away from it.
class _LegalLinks extends StatelessWidget {
  final bool isAr;
  const _LegalLinks({required this.isAr});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          QLegalLink(label: isAr ? 'الخصوصية' : 'Privacy', url: QamarConfig.privacyUrl, size: 12),
          const SizedBox(width: QSpace.sm),
          QLegalLink(label: isAr ? 'الشروط' : 'Terms', url: QamarConfig.termsUrl, size: 12),
        ],
      );
}

/// The date of birth, on three wheels in the order the date is written: the
/// day first, from the start. Numbers in the digits the phone asked for.
class _DateWheels extends StatelessWidget {
  final AppState state;
  const _DateWheels({required this.state});

  static const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  static const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final p = state.profile;
    final year = DateTime.now().year;
    String n(int v) => state.digits('$v');
    return Row(
      children: [
        QWheelField(unit: isAr ? 'يوم' : 'day', value: p.birthDay, min: 1, max: state.birthMonthLength, loop: true, format: n, onChanged: state.setBirthDay),
        const SizedBox(width: QSpace.sm),
        QWheelField(
          unit: isAr ? 'شهر' : 'month',
          value: p.birthMonth,
          min: 1,
          max: 12,
          loop: true,
          format: (m) => (isAr ? _monthsAr : _monthsEn)[m - 1],
          onChanged: state.setBirthMonth,
        ),
        const SizedBox(width: QSpace.sm),
        QWheelField(unit: isAr ? 'سنة' : 'year', value: p.birthYear, min: year - 90, max: year - 10, format: n, onChanged: state.setBirthYear),
      ],
    );
  }
}

/// Under the birth-date wheels: the age the date makes, and, under 18, why
/// it will stop there, so the rule is seen before the answer is given.
class _AgeReadout extends StatelessWidget {
  final AppState state;
  const _AgeReadout({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final age = state.profile.age;
    final adult = state.profile.isAdult;
    final years = isAr ? '${state.iso('$age')} سنة' : '$age years old';
    final rule = isAr ? 'قمر للي عندهم ${state.iso('18')} سنة أو أكتر' : 'Qamar is for adults 18 and over';
    final ink = adult ? QColors.inkTertiary : QColors.inkSecondary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!adult) ...[
          const Icon(QIcons.warning, size: 15, color: QColors.inkSecondary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(adult ? years : '$years · $rule', textAlign: TextAlign.center, style: QText.body(size: 13, color: ink)),
        ),
      ],
    );
  }
}

/// The day's target, the consultation's one hero: the figure in dots, the
/// three macros under it, and what it was worked out from, in words.
class _TargetCard extends StatelessWidget {
  final AppState state;
  const _TargetCard({required this.state});

  /// The activity answered, as the chip said it ("mostly sitting"): the
  /// nearest of the consultation's own three.
  static String activityWords(AppState s) {
    final options = kOnboardingSteps.where((x) => x.id == 'activity').expand((x) => x.options).toList();
    if (options.isEmpty) return s.isAr ? 'نشاط متوسط' : 'moderate activity';
    options.sort((a, b) => ((a.value as num) - s.profile.activity).abs().compareTo(((b.value as num) - s.profile.activity).abs()));
    final words = options.first.label(s.isAr);
    return s.isAr ? words : words[0].toLowerCase() + words.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    final isAr = state.isAr;
    final tg = state.target();
    final p = state.profile;
    String grams(int g) => isAr ? '${state.iso('$g')} جم' : '$g g';
    final sex = p.gender == Gender.female ? (isAr ? 'أنثى' : 'female') : (isAr ? 'ذكر' : 'male');
    // Each figure held to its unit, and each part to the dot after it, so a
    // line never breaks between "82" and "kg".
    const nb = ' ';
    final parts = isAr
        ? ['${state.iso('${p.age}')}$nbسنة', sex, '${state.iso('${p.height}')}$nbسم', '${state.iso('${p.weight}')}$nbكجم', activityWords(state)]
        : ['${p.age}${nb}years', sex, '${p.height}${nb}cm', '${p.weight}${nb}kg', activityWords(state)];
    final from = '${isAr ? 'من إجاباتك:' : 'From your answers:'} ${parts.join('$nb· ')}';
    final kcal = state.digits('${tg.kcal}');

    return Container(
      padding: const EdgeInsets.all(QSpace.xl),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(QText.eyebrowText(t.dailyTarget, ar: isAr), style: QText.eyebrow(ar: isAr)),
          const SizedBox(height: QSpace.md),
          DotNumber(kcal, height: 48, semanticsLabel: '$kcal ${t.kcalDay}'),
          const SizedBox(height: 10),
          Text(t.kcalDay, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.inkSecondary)),
          const SizedBox(height: QSpace.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Macro(label: t.protein, value: grams(tg.protein), ar: isAr),
              _Macro(label: t.carbs, value: grams(tg.carbs), ar: isAr),
              _Macro(label: t.fat, value: grams(tg.fat), ar: isAr),
            ],
          ),
          const SizedBox(height: QSpace.lg),
          Text(from, style: QText.body(size: 13, color: QColors.inkTertiary)),
          const SizedBox(height: QSpace.xs),
          Text(t.estimateNote, style: QText.body(size: 13, color: QColors.inkTertiary)),
        ],
      ),
    );
  }
}

/// A macro's name over its grams, one of three in a row: grouped by space,
/// not boxed.
class _Macro extends StatelessWidget {
  final String label;
  final String value;
  final bool ar;
  const _Macro({required this.label, required this.value, required this.ar});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: QText.body(size: 13, color: QColors.inkTertiary)),
            const SizedBox(height: 2),
            Text(value, style: QText.number(size: 17, weight: FontWeight.w600, ar: ar)),
          ],
        ),
      );
}

/// Saving the progress, offered once there is something to save. Its way in
/// is an outline: the white button on this screen is "Let's start".
class _SaveCard extends StatelessWidget {
  final AppState state;
  const _SaveCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = state.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(QSpace.xl, QSpace.xl, QSpace.xl, QSpace.md),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.saveTitle, style: QText.body(size: 17, weight: FontWeight.w600)),
          const SizedBox(height: QSpace.xs),
          Text(t.saveSub, style: QText.body(size: 15, color: QColors.inkSecondary)),
          const SizedBox(height: QSpace.md),
          // Side by side, or one under the other at large text.
          Wrap(
            spacing: QSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // "Link account" links one: the account sheet opens.
              QOutlineButton(label: t.saveNow, icon: QIcons.link, onTap: state.linkFromSaveCard),
              _TextAction(label: t.saveLater, onTap: state.dismissSave),
            ],
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.fromLTRB(QSpace.xl, QSpace.xl, QSpace.xl, QSpace.md),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: Icon(QIcons.gift, size: 20, color: QColors.ink)),
              const SizedBox(width: QSpace.sm),
              Expanded(
                child: Text(TrialWords.offerTitle(days, ar: isAr, iso: state.iso), style: QText.body(size: 17, weight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: QSpace.xs),
          Text(
            isAr ? 'من غير بطاقة، ومفيش حاجة بتتجدد لوحدها. خطة بكرة، وصور وأسئلة أكتر.' : 'No card, and nothing renews. Tomorrow’s plan, and more photos and questions.',
            style: QText.body(size: 15, color: QColors.inkSecondary),
          ),
          const SizedBox(height: QSpace.md),
          Wrap(
            spacing: QSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              QOutlineButton(label: isAr ? 'ابدأ الأسبوع' : 'Start the week', onTap: state.acceptTrialOffer),
              _TextAction(label: isAr ? 'مش دلوقتي' : 'Not now', onTap: state.declineTrialOffer),
            ],
          ),
        ],
      ),
    );
  }
}

/// A quiet action beside an outline: words in the second ink, a whole touch.
class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _TextAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => QTapArea(
        onTap: onTap,
        builder: (context, pressed) => qPressed(
          context,
          pressed: pressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
            child: Text(label, style: QText.body(size: 15, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary)),
          ),
        ),
      );
}

/// The composer, as the conversation's: one glass field, the words, and at
/// its end one white circle that sends them. With nothing to send, or while
/// Qamar is typing, the circle has nothing to do and says so.
class _Composer extends StatelessWidget {
  final AppState state;
  final TextEditingController ctrl;
  final String placeholder;
  final VoidCallback? onSend;
  const _Composer({required this.state, required this.ctrl, required this.placeholder, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return QGlass(
      shape: QGlassShape.rounded,
      radius: 26,
      padding: const EdgeInsetsDirectional.only(start: 4, end: 4, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            // The field itself is the touch, [QLayout.minTap] tall (O11).
            child: TextField(
              controller: ctrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onChanged: state.onDraftChanged,
              onSubmitted: (_) => state.sendDraft(),
              cursorColor: QColors.ink,
              style: QText.body(size: 17, height: 22),
              decoration: InputDecoration(
                hintText: placeholder,
                hintStyle: QText.body(size: 17, height: 22, color: QColors.inkTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.only(start: 14, end: 4, top: (QLayout.minTap - 22) / 2 + 0.5, bottom: (QLayout.minTap - 22) / 2 + 0.5),
              ),
            ),
          ),
          _Send(onTap: onSend, label: state.isAr ? 'ابعت' : 'Send'),
        ],
      ),
    );
  }
}

/// The composer's one filled button: a white circle and a black arrow.
class _Send extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;
  const _Send({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return QTapArea(
      key: OnboardingScreen.sendKey,
      label: label,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      builder: (context, pressed) => qPressed(
        context,
        pressed: pressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 36,
          height: 36,
          decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? QColors.ink : QDisabled.fill),
          child: Icon(QIcons.send, size: 18, color: enabled ? QColors.onInk : QDisabled.label),
        ),
      ),
    );
  }
}
