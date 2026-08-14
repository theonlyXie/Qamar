import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import '../models/meal.dart';
import '../models/messages.dart';
import '../models/onboarding.dart';
import '../services/ai_gateway.dart';
import '../services/dictation.dart';
import '../services/repositories.dart';
import '../widgets/explain.dart';
import '../models/profile.dart';
import 'chat_replies.dart';

/// Qamar+ billing period.
enum PlusPlan { monthly, annual }

/// How a meal gets logged straight from the orb, with no page in between.
enum QuickLog { voice, text, photo }

enum AppScreen { welcome, scan, onboard, today, plan, progress, you, wallet, subscription }

enum ChatState { idle, listening, thinking }

enum WalletTab { spend, history }

/// Single app-wide store — the Dart counterpart of the prototype's one
/// `Component extends DCLogic { state = {...} }`. Screens read it via
/// `context.watch<AppState>()` and call its methods the way the prototype's
/// markup called `{{ handler }}`.
class AppState extends ChangeNotifier {
  /// Optional persistence. When every repository is null — the default —
  /// AppState behaves exactly as it always has: entirely in memory, no
  /// network, fully demoable and testable offline. Supplying them makes the
  /// same methods write through to Supabase as well, without changing a
  /// single method signature the screens depend on.
  AppState({
    ProfileRepository? profileRepo,
    MealRepository? mealRepo,
    WalletRepository? walletRepo,
    AiGateway? ai,
    Dictation? dictation,
    String? userId,
  })  : _profileRepo = profileRepo,
        _mealRepo = mealRepo,
        _walletRepo = walletRepo,
        _ai = ai,
        _dictation = dictation,
        _userId = userId {
    if (isBacked) hydrate();
  }

  final ProfileRepository? _profileRepo;
  final MealRepository? _mealRepo;
  final WalletRepository? _walletRepo;

  /// The real assistant, when AI_GATEWAY_URL is configured. Null means the
  /// app tells the truth about being unconnected rather than pretending.
  final AiGateway? _ai;
  bool get hasAssistant => _ai != null;

  /// The device's speech recogniser. Null in tests and on platforms without
  /// one, where the UI falls back to typing.
  final Dictation? _dictation;
  final String? _userId;

  /// True when there is a signed-in user and repositories to talk to.
  bool get isBacked => _userId != null;

  /// Set when a write failed. The UI keeps working on local state regardless —
  /// losing a round trip must never cost the user their meal — but the failure
  /// is recorded rather than swallowed so it can be surfaced and retried.
  String? syncError;

  /// Runs a backend call without ever letting it break the screen.
  Future<void> _push(String what, Future<void> Function(String userId) work) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await work(uid);
      if (syncError != null) {
        syncError = null;
        _notify();
      }
    } catch (e) {
      syncError = '$what: $e';
      _notify();
    }
  }

  /// Pulls the server's copy over the local defaults on start.
  Future<void> hydrate() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final saved = await _profileRepo?.loadProfile(uid);
      if (saved != null) profile = saved;

      final today = await _mealRepo?.mealsForDay(uid, DateTime.now());
      if (today != null) {
        meals
          ..clear()
          ..addAll(today);
      }

      final bal = await _walletRepo?.balance(uid);
      if (bal != null) {
        suAvailable = bal.available;
        suLifetime = bal.lifetime;
      }

      final history = await _mealRepo?.dailyTotals(uid, days: 7);
      if (history != null) {
        dayHistory
          ..clear()
          ..addAll(history);
      }

      final weights = await _mealRepo?.weightHistory(uid);
      if (weights != null) {
        weightHistory
          ..clear()
          ..addAll(weights);
      }

      final entries = await _walletRepo?.ledger(uid);
      if (entries != null) {
        serverLedger
          ..clear()
          ..addAll(entries);
      }
      _notify();
    } catch (e) {
      syncError = 'load: $e';
      _notify();
    }
  }

  AppLang lang = AppLang.ar;
  AppScreen screen = AppScreen.welcome;
  int step = 0;
  final List<ObMessage> msgs = [];
  bool typing = false;
  String draft = '';

  Profile profile = const Profile();
  bool scanned = false;
  bool scanReading = false;

  final List<LoggedMeal> meals = [];

  /// Days that actually have logged meals behind them, from the backend.
  /// Empty offline and empty for a new user — the Progress screen says so
  /// rather than drawing a week that never happened.
  final List<DayTotals> dayHistory = [];

  /// Recorded weigh-ins, oldest first.
  final List<WeightReading> weightHistory = [];

  /// The wallet ledger as the database has it. Authoritative when present;
  /// [ledgerExtra] covers the offline case.
  final List<LedgerEntry> serverLedger = [];

  final List<ChatTurn> chat = [];
  String chatDraft = '';

  ChatState chatState = ChatState.idle;
  String lastUser = '';
  int turn = 0;
  bool chatOpen = false;

  double orbX = 290;
  double orbY = 620;

  bool treeOpen = false;
  int suAvailable = 0;
  int suLifetime = 0;
  bool questDone = false;
  /// Meal slots the user has swapped to their alternative, keyed by slot id
  /// ('breakfast' | 'lunch' | 'dinner'). Previously a single bool, which meant
  /// every meal's swap button drove the same flag and only lunch ever changed.
  final Set<String> swappedSlots = {};
  bool blocked = false;
  bool minor = false;
  bool improve = false;
  WalletTab walletTab = WalletTab.spend;
  bool whyOpen = false;
  final List<String> redeemed = [];
  final List<LedgerEntry> ledgerExtra = [];

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- language / strings -------------------------------------------------

  QStrings get t => QStrings.of(lang);
  bool get isAr => lang == AppLang.ar;

  /// Wraps mixed number/word fragments in Unicode bidi isolates, exactly
  /// like the prototype's `iso()` — keeps "٨٢ كجم" reading correctly in RTL.
  String iso(String x) => '⁦$x⁩';

  void setLang(AppLang l) {
    lang = l;
    _notify();
  }

  void restart() {
    screen = AppScreen.welcome;
    step = 0;
    msgs.clear();
    meals.clear();
    chat.clear();
    blocked = false;
    minor = false;
    swappedSlots.clear();
    explainHoverId = null;
    explainOpen = null;
    plusActive = false;
    plusNotice = null;
    plusPlan = PlusPlan.annual;
    improve = false;
    questDone = false;
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    lastMealPhotoPath = null;
    scanned = false;
    scanReading = false;
    suAvailable = 0;
    suLifetime = 0;
    redeemed.clear();
    ledgerExtra.clear();
    serverLedger.clear();
    dayHistory.clear();
    weightHistory.clear();
    walletTab = WalletTab.spend;
    whyOpen = false;
    _notify();
  }

  void go(AppScreen s) {
    screen = s;
    treeOpen = false;
    _notify();
  }

  // ---- welcome / scan -------------------------------------------------

  void openScan() {
    scanPhotoPath = null;
    scanCameraError = null;
    screen = AppScreen.scan;
    scanReading = false;
    _notify();
  }

  void backToWelcome() {
    screen = AppScreen.welcome;
    scanReading = false;
    _notify();
  }

  void startOnboarding() {
    screen = AppScreen.onboard;
    step = 0;
    msgs.clear();
    scanned = false;
    _notify();
    Future.delayed(const Duration(milliseconds: 120), () => askStep(0));
  }

  /// Absolute path of the photo the user just took of their InBody report,
  /// once the camera returns one. Null while the screen is still a preview.
  String? scanPhotoPath;

  /// Set when the camera could not be opened at all (no camera, permission
  /// refused, unsupported platform) so the screen can say so instead of
  /// looking broken.
  String? scanCameraError;

  void setScanPhoto(String? path) {
    scanPhotoPath = path;
    scanCameraError = null;
    _notify();
  }

  void setScanCameraError(String message) {
    scanCameraError = message;
    _notify();
  }

  /// What the reader could actually make out on the report. Drives the line
  /// onboarding opens with, and which questions it still has to ask.
  BodyScan? scanRead;

  /// Reads the photographed report and starts onboarding from what it says.
  ///
  /// The numbers here become the person's calorie target, so nothing is
  /// invented: whatever the reader cannot see stays unset, and onboarding asks
  /// for it in the ordinary way. With no assistant configured, the photo is
  /// simply not read and the user is told that, rather than being handed a
  /// stranger's body composition.
  Future<void> capture() async {
    final path = scanPhotoPath;
    final gateway = _ai;
    scanReading = true;
    scanCameraError = null;
    scanRead = null;
    _notify();

    if (gateway != null && path != null) {
      try {
        scanRead = await gateway.readBodyScan(imagePath: path, lang: lang.code);
      } catch (e) {
        scanRead = BodyScan(
          note: isAr
              ? 'مقدرتش أقرا التقرير دلوقتي، فهسألك الأرقام بنفسي.'
              : 'I could not read the report just now, so I will ask you for the numbers.',
        );
        debugPrint('Qamar: body scan read failed — $e');
      }
    } else {
      scanRead = BodyScan(
        note: isAr
            ? 'لسه مش متوصل بالمساعد، فمش هقدر أقرا التقرير. هسألك الأرقام.'
            : 'I am not connected to the assistant, so I cannot read the report. I will ask you instead.',
      );
    }
    if (_disposed) return;

    final read = scanRead!;
    profile = profile.copyWith(
      age: read.age ?? profile.age,
      height: read.heightCm ?? profile.height,
      weight: read.weightKg ?? profile.weight,
      fat: read.bodyFatPct ?? profile.fat,
    );

    scanReading = false;
    // 'scanned' means the body questions can be skipped — only true when the
    // figures that drive the target actually came off the page.
    scanned = read.heightCm != null && read.weightKg != null;
    screen = AppScreen.onboard;
    step = 0;
    msgs.clear();
    // When the report could not be read, say why before asking — otherwise the
    // user has photographed something and been silently ignored.
    if (!scanned && read.note != null && read.note!.isNotEmpty) {
      msgs.add(ObMessage.q(ar: read.note!, en: read.note!));
    }
    _notify();
    Future.delayed(const Duration(milliseconds: 140), () => askStep(0));
  }

  // ---- onboarding chat -------------------------------------------------

  void _pushQ(String ar, String en) {
    msgs.add(ObMessage.q(ar: ar, en: en));
    _notify();
  }

  void qamarSay(String ar, String en, [VoidCallback? cb]) {
    typing = true;
    _notify();
    Future.delayed(const Duration(milliseconds: 550), () {
      if (_disposed) return;
      typing = false;
      _pushQ(ar, en);
      cb?.call();
    });
  }

  /// Pushes the user's turn, then continues after the prototype's 260ms beat.
  void answerStep(String ar, String en, VoidCallback next) {
    msgs.add(ObMessage.u(ar: ar, en: en));
    _notify();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!_disposed) next();
    });
  }

  void advance() {
    step += 1;
    _notify();
    // Persist once per answered step rather than on every stepper notch, so a
    // half-finished onboarding survives the app being closed without turning
    // each wheel tick into a request.
    if (isBacked) _saveProfile();
    askStep(step);
  }

  void askStep(int i) {
    if (i >= kOnboardingSteps.length) {
      calcTarget();
      return;
    }
    final st = kOnboardingSteps[i];
    if (st.id == 'body' && scanned) {
      typing = true;
      _notify();
      Future.delayed(const Duration(milliseconds: 700), () {
        if (_disposed) return;
        typing = false;
        // Only the figures that were genuinely on the page are read back. A
        // number the reader never saw must not appear in this sentence.
        final read = scanRead;
        final ar = <String>[
          if (read?.age != null) '${iso('${read!.age}')} سنة',
          if (read?.heightCm != null) '${iso('${read!.heightCm}')} سم',
          if (read?.weightKg != null) '${iso('${read!.weightKg}')} كجم',
          if (read?.bodyFatPct != null) 'دهون ${iso('${read!.bodyFatPct}')}٪',
        ];
        final en = <String>[
          if (read?.age != null) '${read!.age} yrs',
          if (read?.heightCm != null) '${read!.heightCm} cm',
          if (read?.weightKg != null) '${read!.weightKg} kg',
          if (read?.bodyFatPct != null) '${read!.bodyFatPct}% body fat',
        ];
        _pushQ(
          'قريت من التقرير: ${ar.join(' · ')}. لو في حاجة غلط اكتبهالي.',
          'I read this off the report: ${en.join(' · ')}. Type a correction if anything is off.',
        );
        advance();
      });
      return;
    }
    typing = true;
    _notify();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_disposed) return;
      typing = false;
      _pushQ(st.askAr, st.askEn);
    });
  }

  OnboardingStep? get currentStep => step < kOnboardingSteps.length ? kOnboardingSteps[step] : null;

  void pickOption(StepOption o) {
    final st = currentStep;
    if (st == null) return;
    if (st.kind == StepKind.multi) {
      final v = o.value as String;
      final has = profile.prefs.contains(v);
      List<String> prefs;
      if (v == 'none') {
        prefs = [];
      } else if (has) {
        prefs = profile.prefs.where((x) => x != v).toList();
      } else {
        prefs = [...profile.prefs.where((x) => x != 'none'), v];
      }
      profile = profile.copyWith(prefs: prefs);
      _notify();
      return;
    }
    if (st.id == 'goal') {
      profile = profile.copyWith(goal: _goalFromValue(o.value as String));
    }
    if (st.id == 'activity') {
      profile = profile.copyWith(activity: o.value as double);
    }
    if (st.id == 'gender') {
      profile = profile.copyWith(gender: o.value == 'female' ? Gender.female : Gender.male);
    }
    if (st.id == 'safety' && o.value != 'none') {
      answerStep(o.ar, o.en, () {
        _pushQ(
          'شكراً إنك قلتلي. في الحالة دي مش هحسبلك هدف سعرات — الأنسب متابعة مع أخصائي. تقدر تستخدم قمر للأسئلة العامة بس.',
          'Thank you for telling me. In this case I won’t calculate a calorie target — a qualified professional is the right route. You can still use Qamar for general questions.',
        );
        blocked = true;
        _notify();
      });
      return;
    }
    answerStep(o.ar, o.en, advance);
  }

  Goal _goalFromValue(String v) => switch (v) {
        'lose' => Goal.lose,
        'gain' => Goal.gain,
        _ => Goal.maintain,
      };

  void onDraftChanged(String v) {
    draft = v;
    _notify();
  }

  void sendDraft() {
    final raw = draft.trim();
    if (raw.isEmpty) return;
    draft = '';
    msgs.add(ObMessage.u(ar: raw, en: raw));
    _notify();
    Future.delayed(const Duration(milliseconds: 240), () {
      if (!_disposed) handleFree(raw);
    });
  }

  void skipStep() {
    answerStep('تخطي', 'Skip', advance);
  }

  void bumpAge(int d) => _bumpProfile(age: (profile.age + d).clamp(18, 90).toInt());

  /// Absolute setters, for the value wheels. The old bump-by-one API is kept
  /// for the InBody correction path.
  void setHeight(int cm) => _bumpProfile(height: cm.clamp(140, 210).toInt());
  void setWeight(int kg) => _bumpProfile(weight: kg.clamp(40, 200).toInt());

  void setBirthYear(int year) {
    final now = DateTime.now();
    final y = year.clamp(now.year - 90, now.year - 10).toInt();
    profile = profile.copyWith(birthYear: y, birthDay: _clampDay(y, profile.birthMonth, profile.birthDay));
    _notify();
  }

  void setBirthMonth(int month) {
    final m = month.clamp(1, 12).toInt();
    profile = profile.copyWith(birthMonth: m, birthDay: _clampDay(profile.birthYear, m, profile.birthDay));
    _notify();
  }

  void setBirthDay(int day) {
    profile = profile.copyWith(birthDay: _clampDay(profile.birthYear, profile.birthMonth, day));
    _notify();
  }

  /// Days available in the currently selected birth month — the day wheel's
  /// upper bound, so February never offers a 31st.
  int get birthMonthLength => Profile.daysInMonth(profile.birthYear, profile.birthMonth);

  /// Birth-date steppers. The year range runs down to 10 years old rather than
  /// stopping at 18, so an under-age user can actually express their real date
  /// and get an honest answer instead of being forced to misreport it.
  void bumpBirthYear(int d) {
    final now = DateTime.now();
    final year = (profile.birthYear + d).clamp(now.year - 90, now.year - 10).toInt();
    profile = profile.copyWith(birthYear: year, birthDay: _clampDay(year, profile.birthMonth, profile.birthDay));
    _notify();
  }

  void bumpBirthMonth(int d) {
    var month = profile.birthMonth + d;
    if (month < 1) month = 12;
    if (month > 12) month = 1;
    profile = profile.copyWith(birthMonth: month, birthDay: _clampDay(profile.birthYear, month, profile.birthDay));
    _notify();
  }

  void bumpBirthDay(int d) {
    final last = Profile.daysInMonth(profile.birthYear, profile.birthMonth);
    var day = profile.birthDay + d;
    if (day < 1) day = last;
    if (day > last) day = 1;
    profile = profile.copyWith(birthDay: day);
    _notify();
  }

  int _clampDay(int year, int month, int day) => day.clamp(1, Profile.daysInMonth(year, month));

  /// Shared by the stepper submit and the free-text path.
  void _submitDob() {
    final p = profile;
    final dateAr = '${iso('${p.birthDay}')}/${iso('${p.birthMonth}')}/${iso('${p.birthYear}')}';
    final dateEn = '${p.birthDay}/${p.birthMonth}/${p.birthYear}';
    if (!p.isAdult) {
      answerStep(dateAr, dateEn, () {
        blocked = true;
        minor = true;
        _notify();
        _pushQ(
          'شكراً إنك قلتلي. قمر للبالغين ١٨ سنة أو أكتر بس، فمش هكمّل حساب هدف. لو محتاج مساعدة في الأكل، الأنسب متابعة مع أخصائي بموافقة ولي الأمر.',
          'Thanks for telling me. Qamar is for adults 18 and over, so I won’t continue to a target. For food support at your age, a professional with guardian consent is the right route.',
        );
      });
      return;
    }
    answerStep('$dateAr · ${iso('${p.age}')} سنة', '$dateEn · ${p.age} yrs', advance);
  }
  void bumpHeight(int d) => _bumpProfile(height: (profile.height + d).clamp(140, 210).toInt());
  void bumpWeight(int d) => _bumpProfile(weight: (profile.weight + d).clamp(40, 200).toInt());
  void _bumpProfile({int? age, int? height, int? weight}) {
    profile = profile.copyWith(age: age, height: height, weight: weight);
    _notify();
  }

  /// Write the profile through. Called at the points where it has genuinely
  /// settled — not on every stepper tick, which would be a request per notch.
  void _saveProfile() {
    final p = profile;
    _push('save profile', (uid) => _profileRepo!.saveProfile(uid, p));
  }

  /// The onboarding composer's primary CTA: submits number/multi steps, or
  /// — once every step is answered — moves into the app.
  void primarySubmit() {
    final st = currentStep;
    if (st == null) {
      go(AppScreen.today);
      return;
    }
    if (st.kind == StepKind.date) {
      _submitDob();
    } else if (st.kind == StepKind.number) {
      final p = profile;
      answerStep(
        '${iso('${p.height}')} سم · ${iso('${p.weight}')} كجم',
        '${p.height} cm · ${p.weight} kg',
        advance,
      );
    } else if (st.kind == StepKind.multi) {
      final sel = profile.prefs;
      final labels = st.options.where((o) => sel.contains(o.value));
      final ar = labels.isNotEmpty ? labels.map((o) => o.ar).join('، ') : 'مفيش';
      final en = labels.isNotEmpty ? labels.map((o) => o.en).join(', ') : 'Nothing';
      answerStep(ar, en, advance);
    }
  }

  /// Best-effort NLU over free text typed instead of tapping a chip — ported
  /// regex-for-regex from the prototype's handleFree().
  void handleFree(String raw) {
    final st = currentStep;
    final low = raw.toLowerCase();
    bool has(List<String> words) => words.any((w) => low.contains(w));
    final nums = RegExp(r'\d+').allMatches(raw).map((m) => int.parse(m.group(0)!)).toList();

    void unclear() => qamarSay('مش متأكد إني فهمت. تقدر تختار من التحت أو تقولهالي بطريقة تانية.',
        'I’m not sure I got that. Pick one below or say it another way.');

    if (blocked) {
      qamarSay('موجود لأي سؤال عام، بس مش هحسب هدف سعرات في الحالة دي.',
          'I’m here for general questions, but I won’t calculate a calorie target in this case.');
      return;
    }
    if (st == null) {
      qamarSay('خلصنا الأسئلة. اضغط "يلا نبدأ" وهنكمل جوه التطبيق.', 'That’s all my questions. Tap “Let’s start” and we’ll keep going inside the app.');
      return;
    }

    if (st.id != 'body') {
      final cw = RegExp(r'(\d+)\s*(كجم|كيلو|kg|kilos?)', caseSensitive: false).firstMatch(raw) ??
          (RegExp(r'وزن|weigh', caseSensitive: false).hasMatch(raw) ? RegExp(r'(\d+)').firstMatch(raw) : null);
      final ch = RegExp(r'(\d+)\s*(سم|cm)', caseSensitive: false).firstMatch(raw) ??
          (RegExp(r'طول|height|tall', caseSensitive: false).hasMatch(raw) ? RegExp(r'(\d+)').firstMatch(raw) : null);
      final ca = RegExp(r'(\d+)\s*(سنة|سنه|عام|yrs?|years?)', caseSensitive: false).firstMatch(raw) ??
          (RegExp(r'سني|عمري|\bage\b', caseSensitive: false).hasMatch(raw) ? RegExp(r'(\d+)').firstMatch(raw) : null);
      if (cw != null || ch != null || ca != null) {
        int? w, h, age;
        if (cw != null) {
          final v = int.parse(cw.group(1)!);
          if (v >= 30 && v <= 250) w = v;
        }
        if (ch != null) {
          final v = int.parse(ch.group(1)!);
          if (v >= 100 && v <= 230) h = v;
        }
        if (ca != null) {
          final v = int.parse(ca.group(1)!);
          if (v >= 13 && v <= 100) age = v;
        }
        if (w != null || h != null || age != null) {
          profile = profile.copyWith(weight: w, height: h, age: age);
          _notify();
          final p = profile;
          qamarSay('ظبطتها: ${iso('${p.age}')} سنة · ${iso('${p.height}')} سم · ${iso('${p.weight}')} كجم.', 'Updated: ${p.age} yrs · ${p.height} cm · ${p.weight} kg.');
          return;
        }
      }
    }

    switch (st.id) {
      case 'dob':
        // A written date first: 15/6/1997, 15-6-1997, 1997/6/15.
        final dm = RegExp(r'(\d{1,4})\s*[/\-\.]\s*(\d{1,2})\s*[/\-\.]\s*(\d{1,4})').firstMatch(raw);
        if (dm != null) {
          final a = int.parse(dm.group(1)!), b = int.parse(dm.group(2)!), c = int.parse(dm.group(3)!);
          // Whichever end carries the 4-digit number is the year.
          final year = a > 31 ? a : c;
          final day = a > 31 ? c : a;
          if (year > 1900 && b >= 1 && b <= 12 && day >= 1 && day <= 31) {
            profile = profile.copyWith(
              birthYear: year,
              birthMonth: b,
              birthDay: day.clamp(1, Profile.daysInMonth(year, b)),
            );
            _notify();
            _submitDob();
            return;
          }
        }
        // A bare year.
        final year = nums.where((n) => n > 1900 && n <= DateTime.now().year).firstOrNull;
        if (year != null) {
          profile = profile.copyWith(birthYear: year);
          _notify();
          _submitDob();
          return;
        }
        // Or just an age.
        final stated = nums.where((n) => n >= 5 && n <= 100).firstOrNull;
        if (stated != null) {
          profile = profile.copyWith(age: stated);
          _notify();
          _submitDob();
          return;
        }
        unclear();
        return;

      case 'gender':
        if (has(['انثى', 'أنثى', 'بنت', 'ست', 'مرا', 'female', 'woman', 'girl', 'f'])) {
          profile = profile.copyWith(gender: Gender.female);
          _notify();
          answerStep('أنثى', 'Female', advance);
          return;
        }
        if (has(['ذكر', 'راجل', 'رجل', 'ولد', 'male', 'man', 'boy', 'm'])) {
          profile = profile.copyWith(gender: Gender.male);
          _notify();
          answerStep('ذكر', 'Male', advance);
          return;
        }
        unclear();
        return;

      case 'consent':
        if (has(['تحسين', 'ساعد', 'improve', 'help'])) {
          improve = true;
          _notify();
          advance();
          return;
        }
        if (has(['موافق', 'اوافق', 'أوافق', 'تمام', 'ماشي', 'اكيد', 'أكيد', 'يلا', 'agree', 'yes', 'ok', 'sure', 'fine'])) {
          advance();
          return;
        }
        if (has(['اعرف', 'أعرف', 'ليه', 'معلومات', 'more', 'why', 'tell'])) {
          qamarSay('باختصار: بحسبلك هدف سعرات تقريبي وأقترح أكل مصري في حدوده. مش بشخّص ولا بوصف علاج. لو تمام قولي "موافق".',
              'In short: I estimate a calorie target and suggest Egyptian meals inside it. I don’t diagnose or prescribe. Say “I agree” when you’re ready.');
          return;
        }
        unclear();
        return;

      case 'name':
        final n = raw.replaceFirst(RegExp(r"^(اسمي|أنا|انا|my name is|i am|i'm|im|call me)\s*", caseSensitive: false), '').trim();
        final trimmed = n.length > 24 ? n.substring(0, 24) : n;
        if (trimmed.isEmpty) {
          unclear();
          return;
        }
        profile = profile.copyWith(name: trimmed);
        _notify();
        advance();
        return;

      case 'body':
        int? age, h, w;
        final la = RegExp(r'(\d+)\s*(سنة|سنه|عام|yrs?|years?)', caseSensitive: false).firstMatch(raw);
        if (la != null) age = int.parse(la.group(1)!);
        final lh = RegExp(r'(\d+)\s*(سم|cm)', caseSensitive: false).firstMatch(raw);
        if (lh != null) h = int.parse(lh.group(1)!);
        final lw = RegExp(r'(\d+)\s*(كجم|كيلو|kg|kilos?)', caseSensitive: false).firstMatch(raw);
        if (lw != null) w = int.parse(lw.group(1)!);
        for (final n in nums) {
          if (n == age || n == h || n == w) continue;
          if (n >= 100 && h == null) {
            h = n;
          } else if (n >= 40 && n < 100 && w == null) {
            w = n;
          } else if (n < 100 && age == null) {
            age = n;
          }
        }
        final missAr = <String>[];
        final missEn = <String>[];
        if (h == null) {
          missAr.add('الطول');
          missEn.add('height');
        }
        if (w == null) {
          missAr.add('الوزن');
          missEn.add('weight');
        }
        if (missAr.isNotEmpty) {
          qamarSay('ناقصني ${missAr.join(' و')}. مثال: ١٧٢ سم، ٨٢ كجم — أو ظبطهم من التحت.',
              'I still need your ${missEn.join(' and ')}. Example: 172 cm, 82 kg — or set them below.');
          return;
        }
        profile = profile.copyWith(age: age, height: h, weight: w);
        _notify();
        advance();
        return;

      case 'goal':
        Goal? g;
        if (has(['خس', 'انحف', 'أنحف', 'ارفع الدهون', 'رشاق', 'lose', 'cut', 'slim', 'weight off'])) {
          g = Goal.lose;
        } else if (has(['ثبت', 'أثبت', 'ثابت', 'زي ما انا', 'maintain', 'stay', 'keep'])) {
          g = Goal.maintain;
        } else if (has(['عضل', 'أزيد', 'ازيد', 'ضخامة', 'muscle', 'gain', 'bulk', 'build'])) {
          g = Goal.gain;
        }
        if (g == null) {
          unclear();
          return;
        }
        profile = profile.copyWith(goal: g);
        _notify();
        advance();
        return;

      case 'activity':
        double? a;
        if (has(['قاعد', 'مكتب', 'مش بتحرك', 'مابتحركش', 'sit', 'desk', 'sedentary'])) {
          a = 1.35;
        } else if (has(['تمرين', 'جيم', 'رياضة', 'حركة كتير', 'active', 'gym', 'train', 'workout'])) {
          a = 1.65;
        } else if (has(['مشي', 'بتحرك', 'شوية', 'walk', 'some', 'moderate'])) {
          a = 1.5;
        }
        if (a == null) {
          unclear();
          return;
        }
        profile = profile.copyWith(activity: a);
        _notify();
        advance();
        return;

      case 'food':
        final prefs = <String>[];
        if (has(['مكسرات', 'فول سوداني', 'nut', 'peanut'])) prefs.add('nuts');
        if (has(['لحوم', 'لحمة', 'نباتي', 'red meat', 'meat', 'vegetarian'])) prefs.add('meat');
        if (has(['لبن', 'ألبان', 'لاكتوز', 'dairy', 'lactose', 'milk'])) prefs.add('lactose');
        if (has(['ميزانية', 'فلوس', 'رخيص', 'budget', 'cheap', 'expensive'])) prefs.add('budget');
        if (prefs.isEmpty && has(['مفيش', 'ولا حاجة', 'لا', 'none', 'nothing', 'no'])) prefs.add('none');
        if (prefs.isEmpty) {
          unclear();
          return;
        }
        profile = profile.copyWith(prefs: prefs.first == 'none' ? [] : prefs);
        _notify();
        advance();
        return;

      case 'safety':
        if (has(['حامل', 'حمل', 'رضاعة', 'مرضعة', 'pregnan', 'breastfeed', 'nursing']) ||
            has(['مزمن', 'سكر', 'ضغط', 'قلب', 'كلى', 'chronic', 'diabet', 'blood pressure', 'kidney', 'heart'])) {
          blocked = true;
          _notify();
          qamarSay('شكراً إنك قلتلي. في الحالة دي مش هحسبلك هدف سعرات — الأنسب متابعة مع أخصائي. تقدر تستخدم قمر للأسئلة العامة بس.',
              'Thank you for telling me. In this case I won’t calculate a calorie target — a qualified professional is the right route. You can still use Qamar for general questions.');
          return;
        }
        if (has(['ولا واحدة', 'مفيش', 'لا', 'none', 'no', 'nope'])) {
          advance();
          return;
        }
        unclear();
        return;
    }
  }

  void calcTarget() {
    typing = true;
    _notify();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_disposed) return;
      typing = false;
      msgs.addAll([
        const ObMessage.q(
          ar: 'حسبتلك الهدف على أساس اللي قلته. دي تقديرات، وتقدر تعدلها في أي وقت.',
          en: 'I calculated your target from what you told me. These are estimates and you can change them any time.',
        ),
        const ObMessage.target(),
        const ObMessage.save(),
      ]);
      // Awarded locally for now: crediting Su Points is server-only (see
      // SupabaseWalletRepository.credit), so the balance reconciles to the
      // server's number on the next hydrate once the Edge Function exists.
      _credit(20, ar: 'إكمال التهيئة', en: 'Onboarding completed');
      _notify();

      if (isBacked) {
        final p = profile;
        final t = target();
        _push('save profile', (uid) => _profileRepo!.saveProfile(uid, p));
        _push('save target', (uid) => _profileRepo!.saveTarget(uid, t, inputs: p));
        // The weight they just gave is the first real point on the trend.
        // Without it the Progress chart has nothing to draw from for weeks.
        _push('record weight', (uid) async {
          await _mealRepo?.recordWeight(uid, kg: p.weight.toDouble());
          final w = await _mealRepo?.weightHistory(uid);
          if (w != null) {
            weightHistory
              ..clear()
              ..addAll(w);
            _notify();
          }
        });
      }
    });
  }

  void dismissSave() {
    msgs.removeWhere((m) => m.kind == ObKind.save);
    _notify();
  }

  Target target() {
    final p = profile;
    // Mifflin-St Jeor. The trailing constant is sex-specific: +5 male,
    // -161 female.
    final sexConstant = p.gender == Gender.female ? -161 : 5;
    final bmr = 10 * p.weight + 6.25 * p.height - 5 * p.age + sexConstant;
    double kcal = bmr * p.activity;
    if (p.goal == Goal.lose) {
      kcal -= 450;
    } else if (p.goal == Goal.gain) {
      kcal += 300;
    }
    kcal = math.max(1500, (kcal / 10).round() * 10).toDouble();
    final protein = (p.weight * 1.8).round();
    final fat = (kcal * 0.28 / 9).round();
    final carbs = ((kcal - protein * 4 - fat * 9) / 4).round();
    return Target(kcal: kcal.round(), protein: protein, carbs: carbs, fat: fat);
  }

  Totals consumed() {
    var kcal = 0, p = 0, c = 0, f = 0;
    for (final m in meals) {
      kcal += m.kcal;
      p += m.p;
      c += m.c;
      f += m.f;
    }
    return Totals(kcal: kcal, p: p, c: c, f: f);
  }

  // ---- logging a meal -------------------------------------------------
  //
  // Logging happens inside the conversation. The assistant reads the photo or
  // the description, proposes items, and *nothing is written* until the user
  // confirms — so a wrong reading costs a tap, never a corrupted day.

  /// What the assistant proposed for the meal being logged, or null when
  /// there is nothing awaiting confirmation.
  MealAnalysis? proposal;

  /// How many of each proposed item the user says they actually ate. Starts
  /// at one apiece; zero drops the item without deleting the assistant's
  /// reading of it.
  List<int> proposalQty = [];

  /// How the meal reached us — 'photo', 'voice' or 'text'. Stored with the
  /// draft so a later correction can be traced to the input that caused it.
  String proposalInput = 'text';

  /// What the user said or the caption on the photo, kept for the draft row.
  String? proposalRaw;

  /// Set while the next chat message should be read as a meal rather than a
  /// question. Quick-logging arms it; producing a proposal disarms it.
  bool _loggingMeal = false;

  bool get hasProposal => proposal != null && proposal!.items.isNotEmpty;

  List<({ConfirmItemDef def, int q})> proposalItems() => [
        for (var i = 0; i < (proposal?.items.length ?? 0); i++)
          (def: proposal!.items[i], q: i < proposalQty.length ? proposalQty[i] : 1),
      ];

  Totals proposalTotals() {
    var k = 0, p = 0, c = 0, f = 0;
    for (final it in proposalItems()) {
      k += it.def.kcal * it.q;
      p += it.def.p * it.q;
      c += it.def.c * it.q;
      f += it.def.f * it.q;
    }
    return Totals(kcal: k, p: p, c: c, f: f);
  }

  void incQty(int i) {
    if (i >= proposalQty.length) return;
    proposalQty[i] = math.min(9, proposalQty[i] + 1);
    _notify();
  }

  void decQty(int i) {
    if (i >= proposalQty.length) return;
    proposalQty[i] = math.max(0, proposalQty[i] - 1);
    _notify();
  }

  void discardProposal() {
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    lastMealPhotoPath = null;
    _notify();
  }

  /// Asks the assistant to read a meal, and puts the answer up for
  /// confirmation. Never writes anything by itself.
  Future<void> _analyseMeal({required String inputType, String? text, String? imagePath}) async {
    final gateway = _ai;
    proposalInput = inputType;
    proposalRaw = text;

    if (gateway == null) {
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'لسه مش متوصل بالمساعد، فمش هقدر أقرأ الوجبة دي دلوقتي.'
            : 'I am not connected to the assistant yet, so I cannot read this meal.',
        sub: isAr ? 'مش هخمّن أرقام' : 'I will not guess the numbers',
      ));
      _notify();
      return;
    }

    chatState = ChatState.thinking;
    _notify();
    try {
      final result = await gateway.analyzeMeal(
        inputType: inputType,
        text: text,
        imagePath: imagePath,
        lang: lang.code,
      );
      if (_disposed) return;
      chatState = ChatState.idle;

      if (result.items.isEmpty) {
        // An empty reading is a real answer — usually a photo too dark or too
        // crowded to trust. Saying so beats inventing a plate of food.
        chat.add(ChatTurn(
          who: ChatWho.q,
          text: result.note ??
              (isAr
                  ? 'مقدرتش أقرأ الوجبة من الصورة دي. جرّب صورة أوضح، أو احكيلي أكلت إيه.'
                  : 'I could not read this meal. Try a clearer photo, or tell me what you ate.'),
        ));
        proposal = null;
        proposalQty = [];
      } else {
        proposal = result;
        proposalQty = List.filled(result.items.length, 1);
        chat.add(ChatTurn(
          who: ChatWho.q,
          text: isAr ? 'شايف كده. ظبّط الكميات وأكّد.' : 'Here is what I see. Adjust the amounts and confirm.',
          sub: result.note,
        ));
      }
    } catch (e) {
      if (_disposed) return;
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'مقدرتش أوصل للمساعد عشان أقرأ الوجبة. جرّب تاني بعد شوية.'
            : 'I could not reach the assistant to read the meal. Try again in a moment.',
        sub: '$e'.length > 120 ? null : '$e',
      ));
    }
    _notify();
  }

  /// Writes the meal the user just confirmed.
  void confirmProposal() {
    final items = proposalItems().where((it) => it.q > 0).toList();
    if (items.isEmpty) {
      discardProposal();
      return;
    }

    final totals = proposalTotals();
    final name = items.map((it) => isAr ? it.def.ar : it.def.en).take(3).join(' + ');
    final how = switch (proposalInput) {
      'photo' => isAr ? 'بالصورة' : 'by photo',
      'voice' => isAr ? 'بالصوت' : 'by voice',
      _ => isAr ? 'بالكتابة' : 'by text',
    };
    final anyLow = items.any((it) => it.def.conf != Confidence.high);
    final sub = isAr
        ? 'مسجّل $how${anyLow ? ' · تقدير' : ''}'
        : 'Logged $how${anyLow ? ' · estimate' : ''}';
    final meal = LoggedMeal(name: name, sub: sub, kcal: totals.kcal, p: totals.p, c: totals.c, f: totals.f);
    final drafted = items.map((it) => (def: it.def, qty: it.q)).toList();
    final raw = proposalRaw;

    meals.add(meal);
    _credit(10, ar: 'تأكيد وجبة', en: 'Meal confirmed');
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: isAr ? 'اتسجّلت: ${totals.kcal} سعرة.' : 'Logged: ${totals.kcal} kcal.',
      sub: isAr ? '+١٠ نقطة' : '+10 Su',
    ));
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    lastMealPhotoPath = null;
    _notify();

    // The schema keeps the draft the user confirmed as well as the log, so a
    // correction stays traceable back to what was proposed.
    if (isBacked) {
      final repo = _mealRepo!;
      final input = proposalInput;
      _push('log meal', (uid) async {
        final draftId = await repo.saveDraft(
          uid,
          MealAnalysisDraft(inputType: input, items: drafted, rawText: raw),
        );
        await repo.confirmMeal(uid, draftId: draftId, meal: meal);
      });
    }
  }

  // ---- quest / wallet -------------------------------------------------

  void completeQuest() {
    questDone = true;
    _credit(5, ar: 'مهمة اليوم', en: 'Primary daily quest');
    _notify();
  }

  void replaceQuest() {
    questDone = false;
    _notify();
  }

  void openWallet() {
    screen = AppScreen.wallet;
    treeOpen = false;
    _notify();
  }

  // ---- Qamar+ subscription --------------------------------------------

  /// Which tier the paywall has selected. Annual is preselected because it is
  /// the better-value option; nothing is charged until a real store product is
  /// wired in (lib/services/payments.dart).
  PlusPlan plusPlan = PlusPlan.annual;

  /// Entitlement. In production this is set only from a server-verified
  /// purchase — never decided on the client (spec_mvp.txt §29.1). Here it is
  /// local so the subscribed state is demoable.
  bool plusActive = false;

  /// Set when a purchase is attempted with no store products configured, which
  /// is the expected state until App Store Connect / Play Console are set up.
  String? plusNotice;

  void openSubscription() {
    screen = AppScreen.subscription;
    treeOpen = false;
    plusNotice = null;
    _notify();
  }

  void selectPlusPlan(PlusPlan p) {
    plusPlan = p;
    plusNotice = null;
    _notify();
  }

  /// Stands in for the real store purchase flow. [PaymentsService] holds the
  /// `in_app_purchase` calls; this cannot reach a store until real product IDs
  /// exist, so it reports that plainly rather than pretending to charge.
  void startPlusPurchase() {
    plusNotice = isAr
        ? 'الاشتراك مش متوصل بمتجر حقيقي لسه. لما تتعمل منتجات qamar_plus في App Store Connect و Play Console، الزرار ده هيفتح شاشة الدفع.'
        : 'Billing isn’t connected to a real store yet. Once the qamar_plus products exist in App Store Connect and Play Console, this button opens the native purchase sheet.';
    _notify();
  }

  void restorePlusPurchases() {
    plusNotice = isAr
        ? 'استرجاع المشتريات محتاج ربط المتجر كمان.'
        : 'Restoring purchases also needs the store connection.';
    _notify();
  }

  void showSpend() {
    walletTab = WalletTab.spend;
    _notify();
  }

  void showHistory() {
    walletTab = WalletTab.history;
    _notify();
  }

  bool isRedeemed(String id) => redeemed.contains(id);

  void _pushRedeem(SpendItemDef item) {
    _push('redeem', (uid) => _walletRepo!.redeem(uid, item: item, idempotencyKey: '${uid}_redeem_${item.id}'));
  }

  void redeem(SpendItemDef item) {
    final done = isRedeemed(item.id);
    final afford = suAvailable >= item.price && !done;
    if (!afford) return;
    suAvailable -= item.price;
    redeemed.add(item.id);
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? item.nameAr : item.nameEn, amount: -item.price, when: isAr ? 'دلوقتي' : 'Just now'));
    _notify();

    // The database is the authority on the balance: the RPC re-checks the
    // price and refuses if the points are not really there.
    if (isBacked) _pushRedeem(item);
  }

  /// Every entry here is written when the thing it describes actually
  /// happens — see [_credit]. Nothing is reconstructed from the balance.
  List<LedgerEntry> ledger() => serverLedger.isNotEmpty ? serverLedger : ledgerExtra;

  /// Records points earned, and the reason, at the moment it is earned.
  ///
  /// The balance is still the server's to decide — crediting is server-side
  /// only (see SupabaseWalletRepository.credit) — so this is the local view
  /// until the next hydrate replaces it with the database's.
  void _credit(int amount, {required String ar, required String en}) {
    suAvailable += amount;
    suLifetime += amount;
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? ar : en, amount: amount, when: isAr ? 'دلوقتي' : 'Just now'));
  }

  // ---- progress -------------------------------------------------
  //
  // Everything here is arithmetic over what was actually logged. A day with
  // nothing logged is a zero, not a gap to be filled in, and a week with no
  // data says so instead of drawing a plausible-looking chart.

  /// The last seven days ending today, oldest first. Today's entry always
  /// reflects the meals in memory, so a meal just logged shows immediately
  /// rather than waiting for the next hydrate.
  List<DayTotals> week() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final byDay = {for (final d in dayHistory) DateTime(d.day.year, d.day.month, d.day.day): d};

    final todayTotals = consumed();
    if (meals.isNotEmpty) {
      byDay[today] = DayTotals(day: today, kcal: todayTotals.kcal, meals: meals.length);
    }

    return [
      for (var i = 6; i >= 0; i--)
        byDay[today.subtract(Duration(days: i))] ??
            DayTotals(day: today.subtract(Duration(days: i)), kcal: 0, meals: 0),
    ];
  }

  /// Days in the last week with anything logged at all.
  int activeDays() => week().where((d) => d.meals > 0).length;

  int mealsThisWeek() => week().fold(0, (sum, d) => sum + d.meals);

  /// Days whose intake landed within 10% of the target. Only counted over days
  /// that were actually logged — an unlogged day is unknown, not a miss.
  int daysInRange() {
    final tgt = target().kcal;
    return week().where((d) => d.meals > 0 && (d.kcal - tgt).abs() <= tgt * 0.1).length;
  }

  /// How much Qamar actually holds about this person. Only things the user
  /// gave it count — the defaults a fresh Profile carries do not.
  int rememberedCount() {
    const fresh = Profile();
    var n = 0;
    if (profile.name.isNotEmpty) n++;
    if (profile.birthYear != fresh.birthYear || profile.birthMonth != fresh.birthMonth || profile.birthDay != fresh.birthDay) n++;
    if (profile.height != fresh.height) n++;
    if (profile.weight != fresh.weight) n++;
    if (profile.goal != fresh.goal) n++;
    if (profile.activity != fresh.activity) n++;
    n += profile.prefs.where((p) => p != 'none').length;
    if (meals.isNotEmpty) n++;
    return n;
  }

  int level() => math.min(20, 1 + (suLifetime / 25).floor());
  double levelPct() => math.min(100, ((suLifetime % 25) / 25 * 100)).toDouble();

  void openWhy() {
    whyOpen = true;
    _notify();
  }

  void closeWhy() {
    whyOpen = false;
    _notify();
  }

  // ---- plan -------------------------------------------------

  bool isSlotSwapped(String slotId) => swappedSlots.contains(slotId);

  void toggleSlotSwap(String slotId) {
    if (!swappedSlots.remove(slotId)) swappedSlots.add(slotId);
    _notify();
  }

  // ---- ask qamar (companion overlay) -------------------------------------------------

  void openChat() {
    chatOpen = true;
    treeOpen = false;
    chatState = ChatState.idle;
    if (chat.isEmpty) {
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr ? 'أنا معاك. قوللي اللي حصل وأنا أعدّل باقي اليوم.' : 'I’m here. Tell me what happened and I’ll adjust the rest of your day.',
        sub: isAr ? 'اكتب أو ادوس على القمر واحكي.' : 'Type, or tap the moon and speak.',
      ));
    }
    _notify();
  }

  void closeChat() {
    chatOpen = false;
    _notify();
  }

  void onChatDraftChanged(String v) {
    chatDraft = v;
    _notify();
  }

  void sendChat() {
    final v = chatDraft.trim();
    if (v.isNotEmpty) sendChatMsg(v);
  }

  /// Sends a message and answers it with the real assistant.
  ///
  /// There is no scripted fallback. If the gateway is not configured or the
  /// call fails, Qamar says so — a health app inventing a plausible-sounding
  /// reply is worse than one admitting it is not connected.
  Future<void> sendChatMsg(String text) async {
    chat.add(ChatTurn(who: ChatWho.u, text: text));
    lastUser = text;
    chatDraft = '';
    chatState = ChatState.thinking;
    _notify();

    // Armed by quick-logging: this message describes a meal, so it goes to the
    // analyser rather than the chat model, and comes back as something to
    // confirm instead of something to read.
    if (_loggingMeal) {
      _loggingMeal = false;
      await _analyseMeal(inputType: proposalInput, text: text);
      return;
    }

    final gateway = _ai;
    if (gateway == null) {
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'لسه مش متوصل بالمساعد. اتظبط الاتصال الأول وبعدين أقدر أرد عليك بجد.'
            : 'I am not connected to the assistant yet. Once that is set up I can answer you properly.',
        sub: isAr ? 'مفيش رد جاهز — مش هألّف' : 'No canned reply — I will not invent one',
      ));
      _notify();
      return;
    }

    try {
      final reply = await gateway.chatReply(message: text, lang: lang.code);
      if (_disposed) return;
      chatState = ChatState.idle;
      turn += 1;
      chat.add(ChatTurn(who: ChatWho.q, text: reply));
    } catch (e) {
      if (_disposed) return;
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'مقدرتش أوصل للمساعد دلوقتي. جرّب تاني بعد شوية.'
            : 'I could not reach the assistant just now. Try again in a moment.',
        sub: '$e'.length > 120 ? null : '$e',
      ));
    }
    _notify();
  }

  /// Live transcript while the user is speaking, so the words appear as they
  /// are said instead of arriving all at once.
  String heard = '';

  /// Set when dictation cannot run at all — no recogniser, or the microphone
  /// was refused. The UI offers typing instead of leaving a dead button.
  String? dictationError;

  /// Starts real dictation. Replaces a placeholder that waited 1.5 seconds and
  /// then inserted a scripted sentence.
  Future<void> tapOrbListen() async {
    if (chatState == ChatState.thinking) return;

    // Tapping again while listening submits what has been heard so far.
    if (chatState == ChatState.listening) {
      await _dictation?.stop();
      final said = heard.trim();
      chatState = ChatState.idle;
      heard = '';
      _notify();
      if (said.isNotEmpty) await sendChatMsg(said);
      return;
    }

    final dictation = _dictation;
    if (dictation == null) {
      dictationError = isAr
          ? 'التسجيل الصوتي مش متاح على الجهاز ده. اكتب وأنا أفهم.'
          : 'Dictation is not available on this device. Type instead and I will follow.';
      _notify();
      return;
    }

    final ok = await dictation.prepare(
      onError: (e) {
        dictationError = isAr
            ? 'مقدرتش أسمع: $e. جرّب تكتب.'
            : 'I could not listen: $e. Try typing.';
        chatState = ChatState.idle;
        _notify();
      },
    );
    if (!ok) {
      dictationError = isAr
          ? 'محتاج إذن الميكروفون عشان أسمعك.'
          : 'I need microphone permission to hear you.';
      _notify();
      return;
    }

    dictationError = null;
    heard = '';
    lastUser = '';
    chatState = ChatState.listening;
    _notify();

    await dictation.start(
      lang: lang.code,
      onResult: (text, isFinal) {
        if (_disposed) return;
        heard = text;
        _notify();
        if (isFinal) {
          chatState = ChatState.idle;
          final said = heard.trim();
          heard = '';
          _notify();
          if (said.isNotEmpty) sendChatMsg(said);
        }
      },
    );
  }

  void chatSuggestionTap(String label) => sendChatMsg(label);

  void chatActionTap() {
    chatOpen = false;
    screen = AppScreen.plan;
    _notify();
  }

  List<String> chatSuggestions() => isAr ? kChatSuggestionsAr : kChatSuggestionsEn;

  // ---- orb + tree -------------------------------------------------

  bool get orbVisible => const {
        AppScreen.today,
        AppScreen.plan,
        AppScreen.progress,
        AppScreen.you,
        AppScreen.wallet,
        AppScreen.subscription,
      }.contains(screen);

  void setOrbPosition(double x, double y, {required double maxX, required double maxY}) {
    orbX = x.clamp(4, maxX).toDouble();
    orbY = y.clamp(46, maxY).toDouble();
    _notify();
  }

  // ---- orb-as-explainer -------------------------------------------------

  /// The explainable value the orb is currently hovering over mid-drag.
  String? explainHoverId;

  /// The explanation currently on screen, snapshotted when the orb was
  /// dropped. Held as the object rather than an id so explanations built from
  /// live data survive the source widget scrolling away.
  Explanation? explainOpen;

  void setExplainHover(String? id) {
    if (explainHoverId == id) return;
    explainHoverId = id;
    _notify();
  }

  void openExplain(Explanation ex) {
    explainOpen = ex;
    explainHoverId = null;
    _notify();
  }

  void closeExplain() {
    explainOpen = null;
    _notify();
  }

  // ---- radial menu: hold, drag, release ---------------------------------

  /// True while the menu is being driven by a held finger. Tapping the orb
  /// still opens it in the old sticky way; holding lets the user sweep to a
  /// destination and release, without a second tap.
  bool treeHold = false;

  /// Node under the finger, and — once Log has been dwelt on — the input
  /// method under it.
  int? treeHoverNode;
  int? treeHoverSub;

  /// Index of the Log node while its input methods are fanned out.
  int? treeLogIndex;
  bool get treeLogExpanded => treeLogIndex != null;

  void openTreeHold() {
    treeOpen = true;
    treeHold = true;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    _notify();
  }

  void setTreeHover(int? node, int? sub) {
    if (treeHoverNode == node && treeHoverSub == sub) return;
    treeHoverNode = node;
    treeHoverSub = sub;
    _notify();
  }

  void expandTreeLog(int index) {
    treeLogIndex = index;
    _notify();
  }

  void endTreeHold() {
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    _notify();
  }

  /// How a meal is being logged from the orb.
  /// Logging happens where the user already is — the companion overlay, which
  /// floats over the current screen — never on a pushed page.
  ///
  ///  * speak — the moon starts listening straight away,
  ///  * type  — the conversation opens ready for typing,
  ///  * photo — the caller opens the camera first and hands the shot back
  ///    through [logPhotoTaken].
  void quickLog(QuickLog kind) {
    treeOpen = false;
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    openChat();

    if (kind == QuickLog.photo) return; // the caller hands the shot back

    // Whatever they say or type next is a meal, not a question.
    _loggingMeal = true;
    proposalInput = kind == QuickLog.voice ? 'voice' : 'text';
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: kind == QuickLog.voice
          ? (isAr ? 'أنا سامعك. أكلت إيه؟' : 'I am listening. What did you eat?')
          : (isAr ? 'اكتبلي أكلت إيه.' : 'Tell me what you ate.'),
      sub: isAr ? 'مفيش حاجة بتتسجل قبل ما تأكد.' : 'Nothing is saved until you confirm.',
    ));
    if (kind == QuickLog.voice) tapOrbListen();
  }

  /// Most recent meal photo, shown inside the conversation.
  String? lastMealPhotoPath;

  /// A meal photographed from the orb. The picture is sent to the assistant,
  /// which reads it and proposes items — all inside the conversation, with no
  /// analysing page and no confirm page.
  void logPhotoTaken(String path) {
    lastMealPhotoPath = path;
    _loggingMeal = false;
    proposalInput = 'photo';
    chat.add(ChatTurn(who: ChatWho.u, text: isAr ? 'صوّرت الوجبة دي' : 'I photographed this meal'));
    _notify();
    _analyseMeal(inputType: 'photo', imagePath: path);
  }

  void toggleTree() {
    treeOpen = !treeOpen;
    _notify();
  }

  void closeTree() {
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    treeOpen = false;
    _notify();
  }
}
