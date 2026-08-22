import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/study.dart';
import '../../models/su_economy.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../theme/text_styles.dart';
import '../../widgets/common.dart';
import '../../widgets/moon.dart';

/// Study Mode shell — one [AppScreen.study], many [StudyView]s.
class StudyShell extends StatelessWidget {
  const StudyShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return switch (state.studyView) {
      StudyView.hub => const _StudyHub(),
      StudyView.add => const _StudyAdd(),
      StudyView.setup => const _StudySetup(),
      StudyView.generating => const _StudyGenerating(),
      StudyView.planReview => const _StudyPlanReview(),
      StudyView.daily => const _StudyDaily(),
      StudyView.task => const _StudyTask(),
      StudyView.session => const _StudySession(),
      StudyView.finish => const _StudyFinish(),
      StudyView.dashboard => const _StudyDashboard(),
    };
  }
}

class _ModeHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  const _ModeHeader({required this.title, this.subtitle, this.onBack});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: QColors.textMid, size: 20),
            ),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: QColors.violet.withOpacity(0.14),
              border: Border.all(color: QColors.violet.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_rounded, size: 14, color: QColors.moonlight),
                const SizedBox(width: 6),
                Text(
                  state.isAr ? 'وضع الدراسة' : 'Study Mode',
                  style: QText.body(size: 11, weight: FontWeight.w600, color: QColors.moonlight),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: QText.display(size: 18, height: 22, color: QColors.textBrand)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: QText.body(size: 12, color: QColors.textMuted)),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: state.openWallet,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: QColors.gold.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFF0F1730),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SuCoinIcon(size: 14),
                  const SizedBox(width: 5),
                  Text('${state.formatSu(state.suAvailable)}',
                      style: QText.number(size: 11, weight: FontWeight.w600, color: QColors.gold)),
                ]),
              ),
            ),
          ),
          IconButton(
            tooltip: state.isAr ? 'خروج' : 'Exit',
            onPressed: state.exitStudyMode,
            icon: const Icon(Icons.close, color: QColors.textMid, size: 20),
          ),
        ],
      ),
    );
  }
}

class _StudyHub extends StatelessWidget {
  const _StudyHub();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final w = state.activeStudyWorkspace;

    if (w == null || !w.planApproved) {
      return Column(
        children: [
          _ModeHeader(title: isAr ? 'مركز المذاكرة' : 'Study Hub'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const QamarMoon(size: 72),
                  const SizedBox(height: 18),
                  Text(
                    isAr ? 'حوّل كتابك أو مادتك لخطة مذاكرة تناسب وقتك.' : 'Turn a book or subject into a plan that fits your time.',
                    textAlign: TextAlign.center,
                    style: QText.body(size: 16, height: 24, color: QColors.textHigh),
                  ),
                  const SizedBox(height: 22),
                  QPrimaryButton(
                    label: isAr ? 'ابدأ' : 'Start',
                    onTap: () {
                      state.studyDraft.reset();
                      state.studyGo(StudyView.add);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final next = w.nextTask;
    final pace = switch (w.pace) {
      StudyPace.ahead => isAr ? 'قدام الخطة' : 'Ahead',
      StudyPace.onTrack => isAr ? 'على المسار' : 'On track',
      StudyPace.needsAdjustment => isAr ? 'محتاجة ظبط' : 'Needs a small adjust',
    };
    final today = w.todayTasks;
    final open = w.openTodayTasks;

    return Column(
      children: [
        _ModeHeader(title: w.title, subtitle: pace),
        if (state.studyStatusMessage != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(state.studyStatusMessage!, style: QText.body(size: 13, color: QColors.cyan)),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: QDecor.card(
                  gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
                  radius: QRadii.xxl,
                ),
                child: Row(
                  children: [
                    const QamarMoon(size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAr
                                ? 'النهارده ${w.completedTodayMin}/${w.plannedTodayMin} د'
                                : 'Today ${w.completedTodayMin}/${w.plannedTodayMin} min',
                            style: QText.number(size: 18, weight: FontWeight.w600, color: QColors.textBrand),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            next == null
                                ? (isAr ? 'خلّصت مهام النهارده.' : 'Today’s planned tasks are done.')
                                : (isAr ? 'التالي: ${next.title}' : 'Next: ${next.title}'),
                            style: QText.body(size: 13, height: 20, color: QColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (next != null) ...[
                QPrimaryButton(
                  label: isAr ? 'ابدأ المهمة التالية' : 'Start next task',
                  onTap: () => state.studyStartSession(taskId: next.id),
                ),
                const SizedBox(height: 14),
              ],
              Text(isAr ? 'مهام النهارده' : 'Today’s tasks',
                  style: QText.body(size: 14, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              if (today.isEmpty)
                Text(isAr ? 'مفيش مهام مجدولة النهارده — يوم راحة أو ظبط الخطة.' : 'No tasks scheduled today — rest day or rebalance.',
                    style: QText.body(size: 13, color: QColors.textFaint))
              else
                for (final t in today.take(3)) _TaskCard(task: t),
              if (today.length > 3) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: state.studyOpenDaily,
                  child: Text(isAr ? 'عرض الباقي' : 'Show more',
                      style: QText.body(size: 13, color: QColors.violetSoft)),
                ),
              ],
              const SizedBox(height: 12),
              if (w.nextMilestone != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isAr ? 'المعلم الجاي' : 'Next milestone',
                                style: QText.body(size: 12, color: QColors.textMuted)),
                            Text(w.nextMilestone!.title,
                                style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                            Text(
                              isAr
                                  ? '${w.nextMilestone!.remainingTasks} مهام · ~${(w.nextMilestone!.remainingMin / 60).toStringAsFixed(1)} س'
                                  : '${w.nextMilestone!.remainingTasks} tasks · ~${(w.nextMilestone!.remainingMin / 60).toStringAsFixed(1)} h',
                              style: QText.number(size: 12, color: QColors.textFaint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: QOutlineButton(
                      label: isAr ? 'اليوم' : 'Daily',
                      onTap: state.studyOpenDaily,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: QOutlineButton(
                      label: isAr ? 'التقدم' : 'Progress',
                      onTap: state.studyOpenDashboard,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              QOutlineButton(
                label: isAr ? 'أضف مادة / كتاب' : 'Add subject / book',
                onTap: () {
                  state.studyDraft.reset();
                  state.studyGo(StudyView.add);
                },
              ),
              if (open.isEmpty && today.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  isAr
                      ? '+${SuEconomy.studyDayComplete} Su لما تخلّص كل مهام النهارده (اتحسبت لو خلصت).'
                      : '+${SuEconomy.studyDayComplete} Su when the day’s set is done (already counted if finished).',
                  style: QText.body(size: 12, color: QColors.goldMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final StudyTask task;
  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final isAr = state.isAr;
    final done = task.status == StudyTaskStatus.done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.xl),
          onTap: done ? null : () => state.studyOpenTask(task.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: QDecor.card(
              color: done ? QColors.cardSlate : QColors.cardDeep,
              border: done ? QColors.borderFaint : QColors.borderSoft,
              radius: QRadii.xl,
            ),
            child: Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 20,
                  color: done ? QColors.green : QColors.violetSoft,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          style: QText.body(size: 14, weight: FontWeight.w600, color: QColors.textHigh)),
                      Text(
                        '${task.estimateMin} ${isAr ? 'د' : 'min'} · +${task.rewardPreview ?? SuEconomy.studyTaskComplete} Su',
                        style: QText.number(size: 12, color: QColors.textFaint),
                      ),
                    ],
                  ),
                ),
                if (!done)
                  const Icon(Icons.chevron_right, size: 18, color: QColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyAdd extends StatelessWidget {
  const _StudyAdd();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    return Column(
      children: [
        _ModeHeader(
          title: isAr ? 'أضف حاجة تذاكرها' : 'Add something to study',
          onBack: () => state.studyWorkspaces.isEmpty ? state.exitStudyMode() : state.studyGo(StudyView.hub),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(
                isAr ? 'اختار نوع المصدر. قمر بيبني الخطة من هنا.' : 'Pick a source type. Qamar builds the route from here.',
                style: QText.body(size: 14, height: 22, color: QColors.textMuted),
              ),
              const SizedBox(height: 16),
              _ChoiceCard(
                icon: Icons.menu_book_outlined,
                title: isAr ? 'كتاب أو ملف' : 'Book or document',
                sub: isAr ? 'عنوان، مؤلف، فصول أو PDF عندك حق تستخدمه' : 'Title, author, chapters, or a PDF you may use',
                onTap: () => state.studyPickType(StudySourceType.book),
              ),
              _ChoiceCard(
                icon: Icons.school_outlined,
                title: isAr ? 'مادة أو منهج' : 'Subject or syllabus',
                sub: isAr ? 'مواضيع، مستوى، وامتحان لو موجود' : 'Topics, level, and an exam date if you have one',
                onTap: () => state.studyPickType(StudySourceType.subject),
              ),
              _ChoiceCard(
                icon: Icons.flag_outlined,
                title: isAr ? 'هدف مخصص' : 'Custom goal',
                sub: isAr ? 'مثلاً: خلّص ١٢ فصل و٣٠٠ سؤال' : 'e.g. finish 12 chapters and 300 questions',
                onTap: () => state.studyPickType(StudySourceType.custom),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _ChoiceCard({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(QRadii.xl),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: QDecor.card(
              gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
              radius: QRadii.xl,
            ),
            child: Row(
              children: [
                Icon(icon, color: QColors.moonlight, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textBrand)),
                      const SizedBox(height: 4),
                      Text(sub, style: QText.body(size: 13, height: 19, color: QColors.textMuted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: QColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudySetup extends StatefulWidget {
  const _StudySetup();
  @override
  State<_StudySetup> createState() => _StudySetupState();
}

class _StudySetupState extends State<_StudySetup> {
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _outcome;
  late final TextEditingController _topics;

  @override
  void initState() {
    super.initState();
    final d = context.read<AppState>().studyDraft;
    _title = TextEditingController(text: d.title);
    _author = TextEditingController(text: d.author);
    _outcome = TextEditingController(text: d.outcome);
    _topics = TextEditingController(text: d.topicsRaw);
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _outcome.dispose();
    _topics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final d = state.studyDraft;

    return Column(
      children: [
        _ModeHeader(
          title: isAr ? 'الهدف والوقت المتاح' : 'Goal and availability',
          onBack: () => state.studyGo(StudyView.add),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (state.studyStatusMessage != null) ...[
                Text(state.studyStatusMessage!, style: QText.body(size: 13, color: QColors.amber)),
                const SizedBox(height: 10),
              ],
              _field(isAr ? 'العنوان' : 'Title', _title, (v) => state.studyUpdateDraft(title: v)),
              if (d.type == StudySourceType.book) ...[
                const SizedBox(height: 10),
                _field(isAr ? 'المؤلف (اختياري)' : 'Author (optional)', _author, (v) => state.studyUpdateDraft(author: v)),
              ],
              const SizedBox(height: 10),
              _field(isAr ? 'إيه اللي يتعتبر خلصان؟' : 'What counts as done?', _outcome, (v) => state.studyUpdateDraft(outcome: v)),
              const SizedBox(height: 10),
              _field(
                isAr ? 'المواضيع / الفصول (سطر أو فاصلة)' : 'Topics / chapters (line or comma)',
                _topics,
                (v) => state.studyUpdateDraft(topicsRaw: v),
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              Text(isAr ? 'ميعاد التسليم' : 'Deadline', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  QPillChip(
                    label: isAr ? 'مفيش معاد' : 'No deadline',
                    selected: d.noDeadline,
                    onTap: () => state.studyUpdateDraft(noDeadline: true),
                  ),
                  QPillChip(
                    label: isAr ? 'خلال أسبوعين' : 'In 2 weeks',
                    selected: !d.noDeadline && d.deadline != null,
                    onTap: () => state.studyUpdateDraft(
                      noDeadline: false,
                      deadline: DateTime.now().add(const Duration(days: 14)),
                    ),
                  ),
                  QPillChip(
                    label: isAr ? 'خلال شهر' : 'In 1 month',
                    selected: false,
                    onTap: () => state.studyUpdateDraft(
                      noDeadline: false,
                      deadline: DateTime.now().add(const Duration(days: 30)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(isAr ? 'أقصى وقت مذاكرة في اليوم' : 'Max study time per day',
                  style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in [60, 90, 120, 180])
                    QPillChip(
                      label: isAr ? '$m د' : '$m min',
                      selected: d.maxDailyMin == m,
                      onTap: () => state.studyUpdateDraft(maxDailyMin: m),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(isAr ? 'مدة الجلسة' : 'Focus block',
                  style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in [25, 50, 90])
                    QPillChip(
                      label: isAr ? '$m د' : '$m min',
                      selected: d.blockMin == m,
                      onTap: () => state.studyUpdateDraft(blockMin: m),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isAr
                    ? 'بنسيب ${(0.15 * 100).round()}٪ من وقتك فاضي كهامش — مش ضغط.'
                    : 'We keep ${(0.15 * 100).round()}% of your time as buffer — not pressure.',
                style: QText.body(size: 12, color: QColors.textFaint),
              ),
              const SizedBox(height: 22),
              QPrimaryButton(
                label: isAr ? 'ولّد الخطة' : 'Generate plan',
                onTap: state.studyGeneratePlan,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, ValueChanged<String> onChanged, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: QText.body(size: 12, color: QColors.textMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          onChanged: onChanged,
          maxLines: maxLines,
          style: QText.body(size: 15, color: QColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: QColors.cardDeep,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}

class _StudyGenerating extends StatelessWidget {
  const _StudyGenerating();

  @override
  Widget build(BuildContext context) {
    final isAr = context.watch<AppState>().isAr;
    return Column(
      children: [
        _ModeHeader(title: isAr ? 'بقرا وبظبط الوقت' : 'Reading structure & fitting time'),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const QamarMoon(size: 88),
                const SizedBox(height: 20),
                Text(isAr ? 'بقدر الهيكل… بقدّر الجهد… بركّب على وقتك المتاح.' : 'Reading structure… estimating effort… fitting your availability.',
                    textAlign: TextAlign.center,
                    style: QText.body(size: 14, height: 22, color: QColors.textMuted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyPlanReview extends StatelessWidget {
  const _StudyPlanReview();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final w = state.activeStudyWorkspace;
    if (w == null) return const SizedBox.shrink();

    final hours = w.tasks.fold<int>(0, (s, t) => s + t.estimateMin) / 60.0;
    final tight = w.deadline != null && w.tasks.isNotEmpty && w.tasks.last.dueAt.isAfter(w.deadline!);

    return Column(
      children: [
        _ModeHeader(title: isAr ? 'راجع الخطة' : 'Review the plan', onBack: () => state.studyGo(StudyView.setup)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(w.title, style: QText.display(size: 24, height: 30, color: QColors.textBrand)),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'حوالي ${hours.toStringAsFixed(1)} ساعة · هامش ${(w.bufferRatio * 100).round()}٪ · ${w.tasks.length} مهمة'
                    : 'About ${hours.toStringAsFixed(1)} h · ${(w.bufferRatio * 100).round()}% buffer · ${w.tasks.length} tasks',
                style: QText.number(size: 14, color: QColors.textMuted),
              ),
              if (tight) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: QDecor.card(border: QColors.amber.withOpacity(0.5), radius: QRadii.lg),
                  child: Text(
                    isAr
                        ? 'بالوقت المتاح، الخطة محتاجة وقت زيادة قبل المعاد. وافق وبظبط بعدين، أو خفّف المحتوى.'
                        : 'With your available time, the route needs more hours before the deadline. Approve and adjust later, or reduce scope.',
                    style: QText.body(size: 13, height: 20, color: QColors.amberSoft),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(isAr ? 'افتراضات' : 'Assumptions', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? '· الجلسة ${w.blockMin} د\n· أقصى ${w.maxDailyMin} د/يوم\n· التقديرات قابلة للظبط من جلساتك الحقيقية'
                    : '· ${w.blockMin}-min blocks\n· Max ${w.maxDailyMin} min/day\n· Estimates calibrate from real sessions',
                style: QText.body(size: 13, height: 22, color: QColors.textMuted),
              ),
              const SizedBox(height: 16),
              Text(isAr ? 'أول مهام' : 'First tasks', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.textMid)),
              const SizedBox(height: 8),
              for (final t in w.tasks.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('· ${t.title} (${t.estimateMin} ${isAr ? 'د' : 'min'})',
                      style: QText.body(size: 13, color: QColors.textHigh)),
                ),
              const SizedBox(height: 20),
              QPrimaryButton(label: isAr ? 'وافق على الخطة' : 'Approve plan', onTap: state.studyApprovePlan),
              TextButton(
                onPressed: () => state.studyGo(StudyView.setup),
                child: Text(isAr ? 'عدّل المدخلات' : 'Edit inputs', style: QText.body(size: 13, color: QColors.textMuted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudyDaily extends StatelessWidget {
  const _StudyDaily();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final w = state.activeStudyWorkspace;
    if (w == null) return const SizedBox.shrink();
    return Column(
      children: [
        _ModeHeader(title: isAr ? 'مهام النهارده' : 'Daily study goals', onBack: () => state.studyGo(StudyView.hub)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
            children: [
              Text(
                isAr
                    ? 'مخطط ${w.plannedTodayMin} د · خلصان ${w.completedTodayMin} د'
                    : 'Planned ${w.plannedTodayMin} min · done ${w.completedTodayMin} min',
                style: QText.number(size: 14, color: QColors.textMuted),
              ),
              const SizedBox(height: 12),
              for (final t in w.todayTasks) _TaskCard(task: t),
              if (w.todayTasks.isEmpty)
                Text(isAr ? 'يوم فاضي في الجدول.' : 'Nothing scheduled today.',
                    style: QText.body(size: 14, color: QColors.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudyTask extends StatelessWidget {
  const _StudyTask();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final t = state.activeStudyTask;
    if (t == null) return const SizedBox.shrink();
    return Column(
      children: [
        _ModeHeader(title: isAr ? 'تفاصيل المهمة' : 'Task detail', onBack: () => state.studyGo(StudyView.hub)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(t.title, style: QText.display(size: 26, height: 32, color: QColors.textBrand)),
              const SizedBox(height: 10),
              Text(t.finishCondition, style: QText.body(size: 15, height: 23, color: QColors.textHigh)),
              if (t.sourceAnchor != null) ...[
                const SizedBox(height: 8),
                Text('${isAr ? 'المصدر' : 'Source'}: ${t.sourceAnchor}',
                    style: QText.body(size: 13, color: QColors.textMuted)),
              ],
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'تقدير ${t.estimateMin} د · +${t.rewardPreview ?? SuEconomy.studyTaskComplete} Su بعد التأكيد'
                    : 'Estimate ${t.estimateMin} min · +${t.rewardPreview ?? SuEconomy.studyTaskComplete} Su after confirm',
                style: QText.number(size: 13, color: QColors.goldMuted),
              ),
              const SizedBox(height: 22),
              QPrimaryButton(label: isAr ? 'ابدأ الجلسة' : 'Start session', onTap: () => state.studyStartSession(taskId: t.id)),
              const SizedBox(height: 10),
              QOutlineButton(label: isAr ? 'علّمها خلصانة' : 'Mark complete', onTap: () => state.studyCompleteTaskQuick(t.id)),
              TextButton(
                onPressed: () => state.studyCarryTask(t.id),
                child: Text(isAr ? 'انقلها ليوم تاني' : 'Move to another day',
                    style: QText.body(size: 13, color: QColors.textMuted)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudySession extends StatefulWidget {
  const _StudySession();
  @override
  State<_StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends State<_StudySession> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      context.read<AppState>().studyTickSession();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final task = state.activeStudyTask;
    final sec = state.studySessionFocusSec;
    final mm = (sec ~/ 60).toString().padLeft(2, '0');
    final ss = (sec % 60).toString().padLeft(2, '0');

    return Column(
      children: [
        _ModeHeader(title: isAr ? 'جلسة تركيز' : 'Focus session', onBack: state.studyOpenFinish),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(task?.title ?? '', textAlign: TextAlign.center,
                    style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textHigh)),
                const Spacer(),
                const QamarMoon(size: 64),
                const SizedBox(height: 18),
                Text('$mm:$ss', style: QText.number(size: 56, weight: FontWeight.w600, color: QColors.moonlight)),
                const SizedBox(height: 8),
                Text(
                  state.studySessionPaused
                      ? (isAr ? 'متوقفة — خد نفسك' : 'Paused — take your time')
                      : (isAr ? 'بذاكر…' : 'Focusing…'),
                  style: QText.body(size: 14, color: QColors.textMuted),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: QOutlineButton(
                        label: state.studySessionPaused ? (isAr ? 'كمّل' : 'Resume') : (isAr ? 'إيقاف' : 'Pause'),
                        onTap: state.studyTogglePause,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QPrimaryButton(label: isAr ? 'خلّصت' : 'Finish', onTap: state.studyOpenFinish),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StudyFinish extends StatelessWidget {
  const _StudyFinish();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final mins = (state.studySessionFocusSec / 60).round();
    return Column(
      children: [
        _ModeHeader(title: isAr ? 'سجّل الجلسة' : 'Log the session', onBack: () => state.studyGo(StudyView.session)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Text(
                isAr ? 'وقت تركيز فعلي: $mins د' : 'Focus time: $mins min',
                style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textBrand),
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'النقاط بتتسجل بعد التأكيد — الوقت لوحده مش بيجيب Su.'
                    : 'Points post after you confirm — time alone never earns Su.',
                style: QText.body(size: 13, color: QColors.textMuted),
              ),
              const SizedBox(height: 18),
              Text(isAr ? 'نسبة إنجاز المهمة' : 'Task progress', style: QText.body(size: 13, color: QColors.textMid)),
              Slider(
                value: state.studyFinishProgress.toDouble(),
                min: 0,
                max: 100,
                divisions: 10,
                label: '${state.studyFinishProgress}%',
                activeColor: QColors.violet,
                onChanged: (v) => state.studySetFinish(progress: v.round()),
              ),
              Text(isAr ? 'ثقتك في اللي اتعلمته (١–٥)' : 'Confidence in what you learned (1–5)',
                  style: QText.body(size: 13, color: QColors.textMid)),
              Slider(
                value: state.studyFinishConfidence.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '${state.studyFinishConfidence}',
                activeColor: QColors.cyan,
                onChanged: (v) => state.studySetFinish(confidence: v.round()),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => state.studySetFinish(note: v),
                maxLines: 3,
                style: QText.body(size: 14, color: QColors.textPrimary),
                decoration: InputDecoration(
                  hintText: isAr ? 'ملاحظة (اختياري)' : 'Note (optional)',
                  hintStyle: QText.body(size: 14, color: QColors.textFaint),
                  filled: true,
                  fillColor: QColors.cardDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
                ),
              ),
              const SizedBox(height: 18),
              if (state.studyFinishProgress >= 80)
                Text(
                  isAr
                      ? '+${SuEconomy.studyTaskComplete} Su بعد التأكيد (مرة لكل نسخة مهمة)'
                      : '+${SuEconomy.studyTaskComplete} Su after confirm (once per task version)',
                  style: QText.body(size: 13, color: QColors.gold),
                ),
              const SizedBox(height: 12),
              QPrimaryButton(
                label: isAr ? 'أكّد وسجّل' : 'Confirm and log',
                onTap: () => state.studyConfirmSession(markTaskDone: state.studyFinishProgress >= 80),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudyDashboard extends StatelessWidget {
  const _StudyDashboard();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final w = state.activeStudyWorkspace;
    if (w == null) return const SizedBox.shrink();
    final done = w.tasks.where((t) => t.status == StudyTaskStatus.done).length;
    final pace = switch (w.pace) {
      StudyPace.ahead => isAr ? 'قدام' : 'Ahead',
      StudyPace.onTrack => isAr ? 'على المسار' : 'On track',
      StudyPace.needsAdjustment => isAr ? 'محتاجة ظبط' : 'Needs adjustment',
    };

    return Column(
      children: [
        _ModeHeader(title: isAr ? 'تقدم المذاكرة' : 'Study progress', onBack: () => state.studyGo(StudyView.hub)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
            children: [
              _stat(isAr ? 'إيقاع الهدف' : 'Goal pace', pace),
              _stat(isAr ? 'مهام خلصانة' : 'Tasks done', '$done / ${w.tasks.length}'),
              _stat(isAr ? 'وقت تركيز' : 'Focus time', '${(w.focusSecTotal / 60).round()} ${isAr ? 'د' : 'min'}'),
              _stat(isAr ? 'Su من المذاكرة النهارده' : 'Study Su today', '${state.studySuEarnedToday} / ${SuEconomy.studyDailyCap}'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: QColors.gold.withOpacity(0.08),
                  border: Border.all(color: QColors.gold.withOpacity(0.32)),
                  borderRadius: BorderRadius.circular(QRadii.xl),
                ),
                child: Row(
                  children: [
                    const SuCoinIcon(size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'نفس محفظة Su بتاعة الأكل — الفنكس واحد.'
                            : 'Same Su wallet as nutrition — one phoenix ledger.',
                        style: QText.body(size: 13, height: 20, color: const Color(0xFFF2E4C6)),
                      ),
                    ),
                    QOutlineButton(label: isAr ? 'المحفظة' : 'Wallet', onTap: state.openWallet, height: 36, color: QColors.gold),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              QOutlineButton(
                label: isAr ? 'مراجعة أسبوعية (+${SuEconomy.studyWeeklyReview} Su)' : 'Weekly review (+${SuEconomy.studyWeeklyReview} Su)',
                onTap: state.studyWeeklyReview,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(String k, String v) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: QText.body(size: 14, color: QColors.textMuted)),
            Text(v, style: QText.number(size: 14, weight: FontWeight.w600, color: QColors.textHigh)),
          ],
        ),
      );
}
