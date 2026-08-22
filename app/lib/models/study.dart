/// Study Mode domain — offline-first models for the feature paper (S63–S85 MVP).
///
/// Su rewards for study use the same wallet as nutrition. Time alone never
/// earns points; only validated completion / reflection events do.
library;

enum StudySourceType { book, pdf, subject, syllabus, custom }

enum StudyTaskStatus { planned, active, done, skipped, carried }

enum StudyPace { ahead, onTrack, needsAdjustment }

enum StudyView {
  hub,
  add,
  setup,
  generating,
  planReview,
  daily,
  task,
  session,
  finish,
  dashboard,
}

class StudyWorkspace {
  final String id;
  final StudySourceType type;
  final String title;
  final String? author;
  final String? level;
  final DateTime? deadline;
  final String outcome;
  final int currentProgressPct;
  final int maxDailyMin;
  final int blockMin;
  final double bufferRatio;
  final List<StudyUnit> units;
  final List<StudyTask> tasks;
  final List<StudySession> sessions;
  final bool planApproved;
  final DateTime createdAt;

  const StudyWorkspace({
    required this.id,
    required this.type,
    required this.title,
    this.author,
    this.level,
    this.deadline,
    required this.outcome,
    this.currentProgressPct = 0,
    this.maxDailyMin = 120,
    this.blockMin = 50,
    this.bufferRatio = 0.15,
    this.units = const [],
    this.tasks = const [],
    this.sessions = const [],
    this.planApproved = false,
    required this.createdAt,
  });

  StudyWorkspace copyWith({
    String? title,
    String? author,
    String? level,
    DateTime? deadline,
    String? outcome,
    int? currentProgressPct,
    int? maxDailyMin,
    int? blockMin,
    double? bufferRatio,
    List<StudyUnit>? units,
    List<StudyTask>? tasks,
    List<StudySession>? sessions,
    bool? planApproved,
  }) =>
      StudyWorkspace(
        id: id,
        type: type,
        title: title ?? this.title,
        author: author ?? this.author,
        level: level ?? this.level,
        deadline: deadline ?? this.deadline,
        outcome: outcome ?? this.outcome,
        currentProgressPct: currentProgressPct ?? this.currentProgressPct,
        maxDailyMin: maxDailyMin ?? this.maxDailyMin,
        blockMin: blockMin ?? this.blockMin,
        bufferRatio: bufferRatio ?? this.bufferRatio,
        units: units ?? this.units,
        tasks: tasks ?? this.tasks,
        sessions: sessions ?? this.sessions,
        planApproved: planApproved ?? this.planApproved,
        createdAt: createdAt,
      );

  List<StudyTask> get todayTasks {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return tasks.where((t) {
      final d = DateTime(t.dueAt.year, t.dueAt.month, t.dueAt.day);
      return d == day;
    }).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<StudyTask> get openTodayTasks =>
      todayTasks.where((t) => t.status != StudyTaskStatus.done).toList();

  StudyTask? get nextTask {
    for (final t in todayTasks) {
      if (t.status != StudyTaskStatus.done) return t;
    }
    for (final t in tasks) {
      if (t.status != StudyTaskStatus.done) return t;
    }
    return null;
  }

  int get plannedTodayMin => todayTasks.fold(0, (s, t) => s + t.estimateMin);

  int get completedTodayMin => todayTasks
      .where((t) => t.status == StudyTaskStatus.done)
      .fold(0, (s, t) => s + t.estimateMin);

  int get focusSecTotal => sessions.fold(0, (s, x) => s + x.focusSec);

  StudyPace get pace {
    if (!planApproved || tasks.isEmpty) return StudyPace.onTrack;
    final done = tasks.where((t) => t.status == StudyTaskStatus.done).length;
    final ratio = done / tasks.length;
    if (deadline == null) {
      if (ratio >= 0.6) return StudyPace.ahead;
      if (ratio >= 0.25) return StudyPace.onTrack;
      return StudyPace.needsAdjustment;
    }
    final totalDays = deadline!.difference(createdAt).inDays.clamp(1, 3650);
    final elapsed = DateTime.now().difference(createdAt).inDays.clamp(0, totalDays);
    final expected = elapsed / totalDays;
    if (ratio >= expected + 0.1) return StudyPace.ahead;
    if (ratio >= expected - 0.15) return StudyPace.onTrack;
    return StudyPace.needsAdjustment;
  }

  StudyMilestone? get nextMilestone {
    final open = tasks.where((t) => t.status != StudyTaskStatus.done).toList();
    if (open.isEmpty) return null;
    final remainingMin = open.fold(0, (s, t) => s + t.estimateMin);
    return StudyMilestone(
      title: open.first.milestoneTitle,
      remainingTasks: open.length,
      remainingMin: remainingMin,
    );
  }
}

class StudyUnit {
  final String id;
  final String title;
  final int order;
  final String? anchor;
  final int estimatedMin;
  const StudyUnit({
    required this.id,
    required this.title,
    required this.order,
    this.anchor,
    required this.estimatedMin,
  });
}

class StudyTask {
  final String id;
  final String workspaceId;
  final String title;
  final String finishCondition;
  final String? sourceAnchor;
  final String milestoneTitle;
  final DateTime dueAt;
  final int estimateMin;
  final int order;
  final StudyTaskStatus status;
  final int version;
  final int? rewardPreview;

  const StudyTask({
    required this.id,
    required this.workspaceId,
    required this.title,
    required this.finishCondition,
    this.sourceAnchor,
    required this.milestoneTitle,
    required this.dueAt,
    required this.estimateMin,
    required this.order,
    this.status = StudyTaskStatus.planned,
    this.version = 1,
    this.rewardPreview,
  });

  StudyTask copyWith({StudyTaskStatus? status, int? version}) => StudyTask(
        id: id,
        workspaceId: workspaceId,
        title: title,
        finishCondition: finishCondition,
        sourceAnchor: sourceAnchor,
        milestoneTitle: milestoneTitle,
        dueAt: dueAt,
        estimateMin: estimateMin,
        order: order,
        status: status ?? this.status,
        version: version ?? this.version,
        rewardPreview: rewardPreview,
      );
}

class StudySession {
  final String id;
  final String taskId;
  final String workspaceId;
  final bool manual;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int focusSec;
  final int breakSec;
  final int progressPct;
  final int confidence; // 1–5 self-report
  final String? note;
  final bool confirmed;

  const StudySession({
    required this.id,
    required this.taskId,
    required this.workspaceId,
    this.manual = false,
    required this.startedAt,
    this.endedAt,
    this.focusSec = 0,
    this.breakSec = 0,
    this.progressPct = 0,
    this.confidence = 3,
    this.note,
    this.confirmed = false,
  });

  StudySession copyWith({
    DateTime? endedAt,
    int? focusSec,
    int? breakSec,
    int? progressPct,
    int? confidence,
    String? note,
    bool? confirmed,
  }) =>
      StudySession(
        id: id,
        taskId: taskId,
        workspaceId: workspaceId,
        manual: manual,
        startedAt: startedAt,
        endedAt: endedAt ?? this.endedAt,
        focusSec: focusSec ?? this.focusSec,
        breakSec: breakSec ?? this.breakSec,
        progressPct: progressPct ?? this.progressPct,
        confidence: confidence ?? this.confidence,
        note: note ?? this.note,
        confirmed: confirmed ?? this.confirmed,
      );
}

class StudyMilestone {
  final String title;
  final int remainingTasks;
  final int remainingMin;
  const StudyMilestone({
    required this.title,
    required this.remainingTasks,
    required this.remainingMin,
  });
}

/// Draft fields while adding a workspace (S65–S69).
class StudyDraft {
  StudySourceType type = StudySourceType.subject;
  String title = '';
  String author = '';
  String level = '';
  String outcome = '';
  DateTime? deadline;
  bool noDeadline = false;
  int progressPct = 0;
  int maxDailyMin = 120;
  int blockMin = 50;
  List<String> topics = const [];
  String topicsRaw = '';

  void reset() {
    type = StudySourceType.subject;
    title = '';
    author = '';
    level = '';
    outcome = '';
    deadline = null;
    noDeadline = false;
    progressPct = 0;
    maxDailyMin = 120;
    blockMin = 50;
    topics = const [];
    topicsRaw = '';
  }
}

/// Deterministic offline planner — estimates units and packs daily tasks.
class StudyPlanner {
  static List<StudyUnit> unitsFromDraft(StudyDraft d) {
    final raw = d.topicsRaw
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final topics = raw.isNotEmpty
        ? raw
        : (d.type == StudySourceType.book
            ? [
                'مقدمة ${d.title}'.trim(),
                'الفصول الأساسية',
                'تمارين ومراجعة',
                'اختبار ذاتي',
              ]
            : [
                d.title.isEmpty ? 'الموضوع الأول' : d.title,
                'مراجعة وممارسة',
                'أسئلة تطبيق',
              ]);
    return [
      for (var i = 0; i < topics.length; i++)
        StudyUnit(
          id: 'u$i',
          title: topics[i],
          order: i,
          anchor: d.type == StudySourceType.book ? 'ch${i + 1}' : 'topic ${i + 1}',
          estimatedMin: d.blockMin + (i % 2) * 15,
        ),
    ];
  }

  static List<StudyTask> schedule({
    required String workspaceId,
    required List<StudyUnit> units,
    required int maxDailyMin,
    required int blockMin,
    required double bufferRatio,
    DateTime? deadline,
    required int taskReward,
  }) {
    final start = DateTime.now();
    final day0 = DateTime(start.year, start.month, start.day);
    final usable = (maxDailyMin * (1 - bufferRatio)).round().clamp(blockMin, maxDailyMin);
    final tasks = <StudyTask>[];
    var dayOffset = 0;
    var usedToday = 0;
    var order = 0;
    var milestone = 1;

    for (final unit in units) {
      var remaining = unit.estimatedMin;
      var part = 1;
      while (remaining > 0) {
        if (usedToday + blockMin > usable && usedToday > 0) {
          dayOffset++;
          usedToday = 0;
          if (dayOffset % 3 == 0) milestone++;
        }
        final slice = remaining > blockMin && remaining - blockMin < 15
            ? remaining
            : (remaining > blockMin ? blockMin : remaining);
        final due = day0.add(Duration(days: dayOffset));
        tasks.add(StudyTask(
          id: 't${workspaceId}_$order',
          workspaceId: workspaceId,
          title: units.length == 1 || part == 1 ? unit.title : '${unit.title} ($part)',
          finishCondition: unit.anchor == null
              ? 'خلّص «${unit.title}» وسجّل ملاحظتين'
              : 'اقرا / راجع ${unit.anchor} واكتب ٥ أسئلة استرجاع',
          sourceAnchor: unit.anchor,
          milestoneTitle: 'معلم $milestone',
          dueAt: due,
          estimateMin: slice,
          order: order,
          rewardPreview: taskReward,
        ));
        remaining -= slice;
        usedToday += slice;
        order++;
        part++;
      }
    }

    // If a deadline exists and the last task falls after it, tasks still
    // schedule — the UI surfaces the gap rather than inventing impossible hours.
    if (deadline != null && tasks.isNotEmpty && tasks.last.dueAt.isAfter(deadline)) {
      // Keep as-is; hub / plan review show needsAdjustment.
    }
    return tasks;
  }
}
