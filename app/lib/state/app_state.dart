import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/meal.dart';
import '../models/messages.dart';
import '../models/onboarding.dart';
import '../models/plan.dart';
import '../models/su_economy.dart';
import '../services/ai_gateway.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../services/dictation.dart';
import '../services/payments.dart';
import '../services/repositories.dart';
import '../models/billing.dart';
import '../widgets/explain.dart';
import '../models/profile.dart';
import '../models/water.dart';
import 'chat_replies.dart';

/// Qamar+ billing period.
enum PlusPlan { monthly, quarterly, annual }

/// How a meal gets logged straight from the orb, with no page in between.
enum QuickLog { voice, text, photo, scan }

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
    WaterRepository? waterRepo,
    WalletRepository? walletRepo,
    AiGateway? ai,
    BillingGateway? billing,
    Future<bool> Function(String url)? openCheckout,
    Dictation? dictation,
    Account? auth,
    String? userId,
  })  : _profileRepo = profileRepo,
        _mealRepo = mealRepo,
        _waterRepo = waterRepo,
        _walletRepo = walletRepo,
        _ai = ai,
        _billing = billing,
        _openCheckout = openCheckout,
        _dictation = dictation,
        _auth = auth,
        _userId = userId {
    _watchAccount();
    if (isBacked) hydrate();
  }

  final ProfileRepository? _profileRepo;
  final MealRepository? _mealRepo;
  final WaterRepository? _waterRepo;
  final WalletRepository? _walletRepo;

  /// The real assistant, when AI_GATEWAY_URL is configured. Null means the
  /// app tells the truth about being unconnected rather than pretending.
  final AiGateway? _ai;
  bool get hasAssistant => _ai != null;

  /// Paymob checkout. Null offline, where the paywall says so rather than
  /// pretending a card was charged.
  final BillingGateway? _billing;
  final Future<bool> Function(String url)? _openCheckout;
  bool get hasBilling => _billing != null;

  /// The device's speech recogniser. Null in tests and on platforms without
  /// one, where the UI falls back to typing.
  final Dictation? _dictation;

  /// Real account linking, when there is a Supabase session behind it. Null
  /// offline, where the account UI says so instead of failing silently.
  final Account? _auth;

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

      final water = await _waterRepo?.sipsForDay(uid, DateTime.now());
      if (water != null) {
        waterToday
          ..clear()
          ..addAll(water);
      }

      final bal = await _walletRepo?.balance(uid);
      if (bal != null) {
        suAvailable = bal.available;
        suLifetime = bal.lifetime;
      }

      await _refreshQuota();
      await _refreshPlus();
      await _refreshAffiliate();

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

  /// Glasses and bottles drunk today. One running millilitre total.
  final List<WaterSip> waterToday = [];

  WaterStatus get water =>
      WaterStatus(waterToday.fold<int>(0, (sum, s) => sum + s.ml));

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
  AiQuota aiQuota = AiQuota.empty;
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
    _authSub?.cancel();
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

  /// Thousands separators so 2,500 looks like a score, not a calorie leftover.
  String formatSu(int n) => NumberFormat.decimalPattern(isAr ? 'ar' : 'en').format(n);

  void setLang(AppLang l) {
    lang = l;
    _notify();
  }

  void restart() {
    screen = AppScreen.welcome;
    step = 0;
    msgs.clear();
    meals.clear();
    waterToday.clear();
    chat.clear();
    blocked = false;
    minor = false;
    swappedSlots.clear();
    explainHoverId = null;
    explainOpen = null;
    plusActive = false;
    plusUntil = null;
    plusNotice = null;
    plusPlan = PlusPlan.annual;
    plusPromoCode = '';
    plusQuote = null;
    plusFirstPurchase = true;
    affiliateWallet = AffiliateWallet.empty;
    affiliateNotice = null;
    improve = false;
    questDone = false;
    questNotice = null;
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    lastMealPhotoPath = null;
    scanPortionAssumed = false;
    scanNotice = null;
    scanBusy = false;
    awaitingLabelPhoto = false;
    scanned = false;
    scanReading = false;
    suAvailable = 0;
    suLifetime = 0;
    aiQuota = AiQuota.empty;
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
      // Shown immediately, confirmed by the server a moment later. The award
      // itself is a trigger on the first `targets` row (migration 0040), keyed
      // `onboarding:<uid>`, so saving the target is what earns it — not this
      // line. [_reconcileWallet] below replaces these numbers with the
      // database's, which is the only version that survives a restart.
      _credit(SuEconomy.onboarding, ar: 'إكمال التهيئة', en: 'Onboarding completed');
      _notify();

      if (isBacked) {
        final p = profile;
        final t = target();
        _push('save profile', (uid) => _profileRepo!.saveProfile(uid, p));
        _push('save target', (uid) async {
          await _profileRepo!.saveTarget(uid, t, inputs: p);
          await _reconcileWallet();
        });
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

  // ---- water ----------------------------------------------------------
  //
  // Two taps: a glass or a bottle. The card shows glasses, bottles, litres,
  // and litres left. Nothing goes through the assistant.

  void logWater(WaterUnit unit) {
    final sip = WaterSip(
      unit: unit,
      ml: Water.mlFor(unit),
      at: DateTime.now(),
    );
    waterToday.add(sip);
    _notify();
    if (!isBacked) return;
    final repo = _waterRepo;
    if (repo == null) return;
    _push('log water', (uid) async {
      final id = await repo.addSip(uid, sip);
      final i = waterToday.indexOf(sip);
      if (i >= 0) {
        waterToday[i] = sip.copyWith(id: id);
        _notify();
      }
    });
  }

  void undoWater() {
    if (waterToday.isEmpty) return;
    final last = waterToday.removeLast();
    _notify();
    final id = last.id;
    if (!isBacked || id == null) return;
    final repo = _waterRepo;
    if (repo == null) return;
    _push('undo water', (uid) => repo.removeSip(uid, id));
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
    scanPortionAssumed = false;
    _notify();
  }

  /// Asks the assistant to read a meal, and puts the answer up for
  /// confirmation. Never writes anything by itself.
  Future<void> _analyseMeal({required String inputType, String? text, String? imagePath}) async {
    final gateway = _ai;
    // Not a scan: clear the packet caveat so it cannot linger onto the next
    // proposal and label a typed meal as an assumed portion.
    scanPortionAssumed = false;
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
      await _pullQuota(gateway);
      chatState = ChatState.idle;

      if (result.items.isEmpty) {
        // An empty reading is a real answer — a name the graph does not carry,
        // or a photo too dark to trust. Saying so beats inventing a plate.
        final fallback = inputType == 'photo'
            ? (isAr
                ? 'مقدرتش أقرأ الوجبة من الصورة دي. جرّب صورة أوضح، أو احكيلي أكلت إيه.'
                : 'I could not read this meal. Try a clearer photo, or tell me what you ate.')
            : (isAr
                ? 'مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو صوّر الطبق من Qamar+.'
                : 'I could not match that food. Try a clearer name, or photograph the plate with Qamar+.');
        chat.add(ChatTurn(
          who: ChatWho.q,
          text: result.note ?? fallback,
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
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      _onQuotaHit(e);
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
      'scan' => isAr ? 'من العلبة' : 'off the packet',
      _ => isAr ? 'بالكتابة' : 'by text',
    };
    // Two separate ways a logged number can be softer than it looks: the food
    // itself was not identified confidently, or it was — off a printed panel,
    // even — but nobody knows how much of it was eaten. A scanned packet is
    // always high confidence and can still be a guess about the portion, and
    // the portion is the figure everything else multiplies.
    final anyLow = items.any((it) => it.def.conf != Confidence.high) ||
        items.any((it) => !it.def.portionMatched);
    final sub = isAr
        ? 'مسجّل $how${anyLow ? ' · تقدير' : ''}'
        : 'Logged $how${anyLow ? ' · estimate' : ''}';
    final meal = LoggedMeal(name: name, sub: sub, kcal: totals.kcal, p: totals.p, c: totals.c, f: totals.f);
    final drafted = items.map((it) => (def: it.def, qty: it.q)).toList();
    final raw = proposalRaw;

    final first = meals.isEmpty;
    meals.add(meal);
    final award = first ? SuEconomy.firstMeal : SuEconomy.mealLogged;
    _credit(award, ar: first ? 'أول وجبة' : 'تأكيد وجبة', en: first ? 'First meal logged' : 'Meal confirmed');
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: isAr ? 'اتسجّلت: ${totals.kcal} سعرة.' : 'Logged: ${totals.kcal} kcal.',
      sub: isAr ? '+${formatSu(award)} نقطة' : '+${formatSu(award)} Su',
    ));
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    lastMealPhotoPath = null;
    scanPortionAssumed = false;
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
        await repo.confirmMeal(uid, draftId: draftId, meal: meal, items: drafted);
        // The meal_logs insert is what fires the award. Read the balance the
        // database arrived at rather than trusting the optimistic figure —
        // `first` above is "first meal in this session's list", which is not
        // the same question as "first meal this account has ever logged".
        await _reconcileWallet();
      });
    }
  }

  // ---- quest / wallet -------------------------------------------------

  /// Non-null while the server is deciding, or when it said no.
  String? questNotice;

  /// Claims today's quest.
  ///
  /// Offline this is the old local award, because there is nothing to ask.
  /// Backed by a real project it is the server's decision entirely: the RPC
  /// checks a meal was logged today in Cairo and pays once per Cairo day. A
  /// second press, or a press on a second phone, returns `already_claimed` and
  /// changes nothing.
  Future<void> completeQuest() async {
    questNotice = null;

    if (!isBacked) {
      questDone = true;
      _credit(SuEconomy.dailyQuest, ar: 'مهمة اليوم', en: 'Primary daily quest');
      _notify();
      return;
    }

    final uid = _userId;
    if (uid == null) return;
    try {
      final res = await _walletRepo!.completeDailyQuest(uid);
      questDone = res.credited || res.reason == 'already_claimed';
      if (!res.credited) {
        questNotice = switch (res.reason) {
          'no_meal_today' => isAr
              ? 'سجّل وجبة النهارده الأول عشان تاخد المهمة.'
              : 'Log a meal today first to claim the quest.',
          'already_claimed' => isAr ? 'خدتها النهارده خلاص.' : 'Already claimed today.',
          _ => isAr ? 'مش قادر أكمّل المهمة دلوقتي.' : 'Could not complete the quest right now.',
        };
      }
      await _reconcileWallet();
    } catch (e) {
      syncError = 'quest: $e';
      questNotice = isAr ? 'مش قادر أكمّل المهمة دلوقتي.' : 'Could not complete the quest right now.';
      _notify();
    }
  }

  void replaceQuest() {
    questDone = false;
    questNotice = null;
    _notify();
  }

  void openWallet() {
    screen = AppScreen.wallet;
    treeOpen = false;
    _notify();
  }

  // ---- Qamar+ subscription --------------------------------------------

  /// Which tier the paywall has selected. Annual is preselected because it is
  /// the better-value option; nothing is charged until Paymob confirms.
  PlusPlan plusPlan = PlusPlan.annual;

  /// Entitlement. In production this is set only from a Paymob-verified
  /// payment — never decided on the client (spec_mvp.txt §29.1). Here it is
  /// local so the subscribed state is demoable.
  bool plusActive = false;

  /// Whether anything is allowed to be locked behind Qamar+.
  ///
  /// False until Paymob is live. Every gate below asks this first, so removing
  /// the paywall is one flag rather than a scatter of deletions — and putting
  /// it back is the same flag, with the billing code never having been torn
  /// out and rewritten from memory.
  bool get plusRequired => QamarConfig.billingEnabled;

  /// Whether the camera may be used at all.
  ///
  /// The product rule, in one place: **anything that opens the camera is
  /// Qamar+**. Photographing a meal, scanning a barcode, reading a nutrition
  /// label off the back of a packet — all of it. Typing and speaking a meal
  /// stay free forever, because they cost the food graph and not the model.
  ///
  /// While billing is off, plusRequired is false and nothing is locked, so
  /// this is open to everyone. That is not the rule changing; it is the rule
  /// having nothing to enforce yet. The day BILLING_ENABLED goes true, every
  /// camera entry point in the app closes behind the paywall at once, because
  /// they all ask this one getter.
  bool get cameraAllowed => !plusRequired || plusActive;

  /// Kept as the name the meal-logging paths already use.
  bool get photoLogAllowed => cameraAllowed;

  /// Scanning a barcode. Same gate, named for the thing it guards so a reader
  /// of quickScan() does not have to know it is really about the camera.
  bool get barcodeScanAllowed => cameraAllowed;

  /// Photographing the nutrition table on a packet.
  bool get labelScanAllowed => cameraAllowed;
  DateTime? plusUntil;

  /// Set when checkout cannot start, or while Paymob's page is open.
  /// Also set when a free-tier user tries to photograph a meal.
  String? plusNotice;

  /// Typed promo / affiliate code. The server stamps the price from this.
  String plusPromoCode = '';

  /// Last server (or local) quote for the selected plan. Display only.
  PlusQuote? plusQuote;
  bool plusFirstPurchase = true;
  int _plusQuoteGen = 0;

  /// Affiliate cash wallet (EGP we send the marketer). Not Su Points.
  AffiliateWallet affiliateWallet = AffiliateWallet.empty;
  String? affiliateNotice;

  PlusQuote get displayPlusQuote =>
      plusQuote ??
      PlusPricing.quote(plan: plusPlan.name, firstPurchase: plusFirstPurchase);

  /// Photographing a plate uses the vision model, so it is Qamar+. Typing and
  /// speaking a meal stay on the free tier and do not spend the daily AI cap.
  void refusePhotoLog() {
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    plusNotice = isAr
        ? 'تصوير الوجبة تحليل بالذكاء الاصطناعي، وده لـ Qamar+. الكتابة والصوت مجاناً ومش بيخصموا من استخدامات قمر.'
        : 'Photographing a meal uses the model, so it is Qamar+. Typing and speaking are free and do not spend Qamar uses.';
    go(AppScreen.subscription);
  }

  void openSubscription() {
    // Nothing to sell yet. Guarded here as well as in the UI so a stale
    // widget, a deep link, or a restored navigation state cannot land someone
    // on a checkout screen that cannot take money.
    if (!plusRequired) return;
    screen = AppScreen.subscription;
    treeOpen = false;
    plusNotice = null;
    _notify();
    refreshPlusQuote();
  }

  void selectPlusPlan(PlusPlan p) {
    plusPlan = p;
    plusNotice = null;
    plusQuote = PlusPricing.quote(
      plan: p.name,
      firstPurchase: plusFirstPurchase,
    );
    _notify();
    refreshPlusQuote();
  }

  void setPlusPromoCode(String code) {
    plusPromoCode = PlusPricing.normalizeCode(code);
    plusNotice = null;
    _notify();
    refreshPlusQuote();
  }

  Future<void> refreshPlusQuote() async {
    if (!plusRequired) return;
    final billing = _billing;
    final gen = ++_plusQuoteGen;
    if (billing == null) {
      plusQuote = PlusPricing.quote(
        plan: plusPlan.name,
        firstPurchase: plusFirstPurchase,
      );
      _notify();
      return;
    }
    try {
      final quoted = await billing.quote(
        plan: plusPlan.name,
        promoCode: plusPromoCode.isEmpty ? null : plusPromoCode,
      );
      if (gen != _plusQuoteGen) return;
      plusQuote = quoted;
      plusFirstPurchase = quoted.firstPurchase;
    } catch (_) {
      if (gen != _plusQuoteGen) return;
      plusQuote = PlusPricing.quote(
        plan: plusPlan.name,
        firstPurchase: plusFirstPurchase,
      );
    }
    _notify();
  }

  /// Opens Paymob's checkout for the selected plan. Qamar+ is not flipped
  /// here — Paymob tells the server, and the next entitlement read does.
  Future<void> startPlusPurchase() async {
    if (plusActive) {
      plusNotice = isAr
          ? 'اشتراكك شغال عن طريق Paymob. لو حابب تلغيه، راسل الدعم من الشاشة دي.'
          : 'Your subscription is billed through Paymob. To cancel, write to support from this screen.';
      _notify();
      return;
    }
    final billing = _billing;
    if (!isBacked || billing == null) {
      plusNotice = isAr
          ? 'الدفع في مصر عن طريق Paymob. اربط حسابك الأول، وبعدين نفتح صفحة الدفع بالجنيه المصري (فيزا، محفظة، أو Meeza).'
          : 'Egypt billing runs through Paymob. Link your account first, then we open checkout in EGP (card, wallet, or Meeza).';
      _notify();
      return;
    }

    plusNotice = isAr ? 'بنفتح صفحة Paymob…' : 'Opening Paymob…';
    _notify();
    try {
      final session = await billing.checkout(
        plan: plusPlan.name,
        promoCode: plusPromoCode.isEmpty ? null : plusPromoCode,
        email: _auth?.email,
        firstName: profile.name.isEmpty ? null : profile.name.split(' ').first,
      );
      final opener = _openCheckout ?? openPaymobCheckout;
      final opened = await opener(session.checkoutUrl);
      if (!opened) {
        plusNotice = isAr
            ? 'مقدرتش أفتح صفحة Paymob. جرّب تاني أو ادفع من متصفح.'
            : 'Could not open Paymob. Try again, or pay from a browser.';
        _notify();
        return;
      }
      plusNotice = isAr
          ? 'كمّل الدفع في Paymob. أول ما يتأكد التحويل، قمر+ هيتفعل لوحده — من غير ما التطبيق يقول إنه دُفع.'
          : 'Finish in Paymob. Qamar+ turns on when the payment is confirmed — the app does not mark you paid on its own.';
    } catch (e) {
      plusNotice = isAr
          ? 'Paymob مش جاهز يستقبل دفعات دلوقتي. لو المفاتيح لسه متعملت، دي الخطوة الجاية من دليل Paymob.'
          : 'Paymob cannot take a payment yet. If the keys are still missing, that is the next step in the Paymob guide.';
    }
    _notify();
  }

  Future<void> restorePlusPurchases() => _refreshPlus(announce: true);

  /// Called when Paymob sends the person back to the app.
  Future<void> onReturnedFromPaymob() async {
    await _refreshPlus(announce: true);
    await _refreshAffiliate();
    if (screen != AppScreen.subscription) go(AppScreen.subscription);
  }

  Future<void> _refreshPlus({bool announce = false}) async {
    // No billing function is deployed, so asking it would fail and the failure
    // would surface to the user as "could not read the subscription" — an
    // error about a product that is not on sale.
    if (!plusRequired) return;
    final billing = _billing;
    if (billing == null) return;
    try {
      final ent = await billing.entitlement();
      plusActive = ent.active;
      plusUntil = ent.periodEnd;
      plusFirstPurchase = ent.firstPurchase;
      if (announce) {
        plusNotice = plusActive
            ? (isAr ? 'قمر+ اشتغل. شكراً.' : 'Qamar+ is on. Thank you.')
            : (isAr
                ? 'لسه مفيش دفع متأكد من Paymob. لو خلصت دلوقتي، استنى لحظة وجرّب استرجاع الاشتراك.'
                : 'Paymob has not confirmed a payment yet. If you just finished, wait a moment and tap Restore.');
      }
      _notify();
      await refreshPlusQuote();
    } catch (e) {
      if (announce) {
        plusNotice = isAr
            ? 'مقدرتش أقرأ حالة الاشتراك دلوقتي.'
            : 'Could not read the subscription just now.';
        _notify();
      }
    }
  }

  Future<void> _refreshAffiliate() async {
    final billing = _billing;
    if (billing == null || !isBacked) return;
    try {
      affiliateWallet = await billing.affiliate();
      _notify();
    } catch (_) {
      // The paywall still works without the affiliate card.
    }
  }

  Future<void> requestAffiliatePayout() async {
    final billing = _billing;
    if (billing == null || !isBacked) {
      affiliateNotice = isAr
          ? 'اربط حسابك الأول عشان نقدر نحوللك العمولة.'
          : 'Link your account first so we can send the commission.';
      _notify();
      return;
    }
    if (!affiliateWallet.canRedeem) {
      affiliateNotice = isAr
          ? 'أقل تحويل ٥٠ ج.م. لما محفظة العمولة توصل للمبلغ ده، نقدر نبعتهالك.'
          : 'The smallest payout is EGP 50. When the affiliate wallet reaches that, we can send it.';
      _notify();
      return;
    }
    try {
      affiliateWallet = await billing.requestAffiliatePayout();
      affiliateNotice = isAr
          ? 'طلب التحويل اتسجل. هنبعتهالك بالجنيه من طرفنا — مش نقاط Su.'
          : 'Payout requested. We will send the EGP from our end — this is not Su Points.';
    } catch (_) {
      affiliateNotice = isAr
          ? 'مقدرتش أسجّل طلب التحويل دلوقتي.'
          : 'Could not request that payout just now.';
    }
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

  /// Remaining Qamar uses today, from the last gateway response or /quota.
  Future<void> _pullQuota(AiGateway gateway) async {
    if (gateway is HttpAiGateway && gateway.lastQuota != null) {
      aiQuota = gateway.lastQuota!;
      return;
    }
    try {
      aiQuota = await gateway.quotaStatus();
    } catch (_) {}
  }

  Future<void> _refreshQuota() async {
    final gateway = _ai;
    if (gateway == null) return;
    try {
      aiQuota = await gateway.quotaStatus();
      _notify();
    } catch (_) {
      // A missing counter is not worth blocking Today. The next AI call
      // will 429 if they are actually out.
    }
  }

  void _onQuotaHit(AiQuotaException e) {
    aiQuota = e.quota;
    chatState = ChatState.idle;
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: e.message,
      action: isAr ? 'افتح المحفظة' : 'Open the wallet',
      openWallet: true,
    ));
    _notify();
  }

  void redeem(SpendItemDef item) {
    final done = item.once && isRedeemed(item.id);
    final afford = suAvailable >= item.price && !done;
    if (!afford) return;
    suAvailable -= item.price;
    if (item.once) redeemed.add(item.id);
    if (item.grantsAiUses > 0) {
      aiQuota = aiQuota.withExtra(item.grantsAiUses);
    }
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? item.nameAr : item.nameEn, amount: -item.price, when: isAr ? 'دلوقتي' : 'Just now'));
    _notify();

    // The database is the authority on the balance: the RPC re-checks the
    // price and refuses if the points are not really there.
    if (isBacked) {
      final key = item.once
          ? '${_userId}_redeem_${item.id}'
          : '${_userId}_redeem_${item.id}_${DateTime.now().millisecondsSinceEpoch}';
      _push('redeem', (uid) => _walletRepo!.redeem(uid, item: item, idempotencyKey: key));
    }
  }

  /// Every entry here is written when the thing it describes actually
  /// happens — see [_credit]. Nothing is reconstructed from the balance.
  List<LedgerEntry> ledger() => serverLedger.isNotEmpty ? serverLedger : ledgerExtra;

  /// Shows points the moment they are earned, so the screen does not wait on a
  /// round trip.
  ///
  /// This is a display, not a decision. Nothing here reaches the database —
  /// `SupabaseWalletRepository.credit` throws on purpose — and every call site
  /// that is backed by a real project follows the write with
  /// [_reconcileWallet]. Until that landed, these two integers were the *only*
  /// record of a meal award anywhere, and they were gone by the next launch.
  void _credit(int amount, {required String ar, required String en}) {
    suAvailable += amount;
    suLifetime += amount;
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? ar : en, amount: amount, when: isAr ? 'دلوقتي' : 'Just now'));
  }

  /// Replaces the optimistic balance and ledger with the database's.
  ///
  /// Called after any write that earns points. It is deliberately not a full
  /// [_hydrate]: that re-reads meals, water, weights, quota, Plus and
  /// affiliate state, which is a lot of network for a 100-point award, and it
  /// would stamp on whatever the user is typing right now.
  Future<void> _reconcileWallet() async {
    final uid = _userId;
    final repo = _walletRepo;
    if (uid == null || repo == null) return;
    try {
      final bal = await repo.balance(uid);
      suAvailable = bal.available;
      suLifetime = bal.lifetime;

      final entries = await repo.ledger(uid);
      serverLedger
        ..clear()
        ..addAll(entries);
      // The optimistic rows have been superseded by real ones; keeping them
      // would show every award twice.
      ledgerExtra.clear();
      _notify();
    } catch (e) {
      // The award is safe in the database either way — this only means the
      // screen keeps the optimistic number until the next hydrate. Not worth
      // an error banner.
      syncError = 'wallet: $e';
      _notify();
    }
  }

  // ---- account -------------------------------------------------
  //
  // Email only, and it genuinely works. Apple and Google need native setup
  // this project does not have yet, so their buttons are absent rather than
  // present and inert.

  bool authOpen = false;

  /// True when the user is attaching an email to the guest account they have
  /// been using; false when they are signing in to an existing account on a
  /// new device.
  bool authLinking = true;

  /// Whether the six-digit code has been sent and is now being waited for.
  bool authCodeSent = false;
  bool authBusy = false;
  String authEmail = '';
  String authCode = '';
  String? authError;
  String? authDone;

  bool get hasAccount => _auth?.isAnonymous == false;
  String? get accountEmail => _auth?.email;

  /// The provider whose browser tab is currently open, if any.
  OAuthChoice? authProvider;

  StreamSubscription<void>? _authSub;

  /// Watches for the identity changing under us. An OAuth flow finishes in a
  /// browser tab, not in the app, so nothing else tells the UI it worked.
  void _watchAccount() {
    final auth = _auth;
    if (auth == null) return;
    _authSub = auth.changes.listen((_) {
      if (_disposed) return;
      if (!auth.isAnonymous) {
        authProvider = null;
        authBusy = false;
        authError = null;
        authDone = isAr
            ? 'تمام، حسابك اتربط.'
            : 'Done — your account is linked.';
        _notify();
        // A provider sign-in on a new device brings its own rows with it.
        hydrate();
      } else {
        _notify();
      }
    });
  }

  /// Starts a one-tap sign-in. The browser opens; the result arrives through
  /// the deep link that brings the user back, handled in [_watchAccount].
  Future<void> signInWith(OAuthChoice provider) async {
    final auth = _auth;
    if (auth == null) {
      authError = isAr
          ? 'الحسابات محتاجة اتصال بالسيرفر، والتطبيق شغال أوفلاين دلوقتي.'
          : 'Accounts need a server connection, and the app is running offline.';
      _notify();
      return;
    }
    authProvider = provider;
    authBusy = true;
    authError = null;
    _notify();
    try {
      await auth.startOAuth(provider);
      // Deliberately still busy: the browser tab is open and the flow is not
      // finished until the user comes back. _watchAccount clears it.
    } catch (e) {
      if (_disposed) return;
      authProvider = null;
      authBusy = false;
      authError = _oauthMessage(provider, e);
      _notify();
    }
  }

  /// A provider that is not configured in the Supabase dashboard fails with a
  /// flat 400. Saying which provider and what is missing is the difference
  /// between a bug report and a five-minute fix.
  String _oauthMessage(OAuthChoice provider, Object e) {
    final name = switch (provider) {
      OAuthChoice.google => 'Google',
      OAuthChoice.apple => 'Apple',
      OAuthChoice.facebook => 'Facebook',
    };
    final raw = '$e';
    if (raw.contains('not enabled') || raw.contains('Unsupported provider') || raw.contains('400')) {
      return isAr
          ? 'الدخول بـ $name لسه مش مفعّل على السيرفر.'
          : 'Signing in with $name is not switched on yet on the server.';
    }
    if (raw.contains('identity_already_exists') || raw.contains('already linked')) {
      return isAr
          ? 'الحساب ده مربوط بـ $name قبل كده. ادخل بيه على طول.'
          : 'That $name account is already linked. Sign in with it directly.';
    }
    return isAr
        ? 'مقدرتش أكمّل الدخول بـ $name. جرّب تاني أو استخدم الإيميل.'
        : 'I could not finish signing in with $name. Try again, or use email.';
  }

  void openLinkAccount() {
    authOpen = true;
    authLinking = true;
    _resetAuthFields();
  }

  void openSignIn() {
    authOpen = true;
    authLinking = false;
    _resetAuthFields();
  }

  void closeAuth() {
    authOpen = false;
    _notify();
  }

  void _resetAuthFields() {
    authCodeSent = false;
    authBusy = false;
    authProvider = null;
    authCode = '';
    authError = null;
    authDone = null;
    _notify();
  }

  void onAuthEmailChanged(String v) {
    authEmail = v.trim();
    authError = null;
    _notify();
  }

  void onAuthCodeChanged(String v) {
    authCode = v.trim();
    authError = null;
    _notify();
  }

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');
  bool get authEmailValid => _emailPattern.hasMatch(authEmail);

  Future<void> sendAuthCode() async {
    final auth = _auth;
    if (auth == null) {
      authError = isAr
          ? 'الحسابات محتاجة اتصال بالسيرفر، والتطبيق شغال أوفلاين دلوقتي.'
          : 'Accounts need a server connection, and the app is running offline.';
      _notify();
      return;
    }
    if (!authEmailValid) {
      authError = isAr ? 'الإيميل ده مش مظبوط.' : 'That email does not look right.';
      _notify();
      return;
    }
    authBusy = true;
    authError = null;
    _notify();
    try {
      authLinking ? await auth.startLink(authEmail) : await auth.startSignIn(authEmail);
      if (_disposed) return;
      authCodeSent = true;
    } catch (e) {
      if (_disposed) return;
      authError = _authMessage(e);
    }
    authBusy = false;
    _notify();
  }

  Future<void> verifyAuthCode() async {
    final auth = _auth;
    if (auth == null) return;
    if (authCode.length < 6) {
      authError = isAr ? 'الكود ٦ أرقام.' : 'The code is six digits.';
      _notify();
      return;
    }
    authBusy = true;
    authError = null;
    _notify();
    try {
      authLinking
          ? await auth.confirmLink(email: authEmail, token: authCode)
          : await auth.confirmSignIn(email: authEmail, token: authCode);
      if (_disposed) return;
      authDone = isAr ? 'تمام، الحساب اتربط بـ $authEmail.' : 'Done — your account is linked to $authEmail.';
      authBusy = false;
      _notify();
      // Signing in on a new device brings a different set of rows with it.
      if (!authLinking) await hydrate();
    } catch (e) {
      if (_disposed) return;
      authError = _authMessage(e);
      authBusy = false;
      _notify();
    }
  }

  /// Turns a Supabase error into something a person can act on. The raw
  /// message is kept when it is not one we recognise — hiding it would make a
  /// misconfigured project look like a broken app.
  String _authMessage(Object e) {
    final raw = '$e';
    if (raw.contains('already been registered') || raw.contains('already registered')) {
      return isAr
          ? 'الإيميل ده متسجل قبل كده. ادخل بيه من "عندي حساب".'
          : 'That email is already registered. Use “I already have an account” to sign in with it.';
    }
    if (raw.contains('Token has expired') || raw.contains('expired')) {
      return isAr ? 'الكود خلصت مدته. اطلب واحد جديد.' : 'That code has expired. Ask for a new one.';
    }
    if (raw.contains('Invalid token') || raw.contains('invalid')) {
      return isAr ? 'الكود غلط. راجع الأرقام.' : 'That code is not right. Check the digits.';
    }
    if (raw.contains('rate limit') || raw.contains('Too many')) {
      return isAr ? 'طلبات كتير على بعض. استنى شوية.' : 'Too many attempts. Wait a minute and try again.';
    }
    return raw;
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

  int level() => SuEconomy.levelFor(suLifetime);
  double levelPct() => SuEconomy.levelPctFor(suLifetime);

  void openWhy() {
    whyOpen = true;
    _notify();
  }

  void closeWhy() {
    whyOpen = false;
    _notify();
  }

  // ---- plan -------------------------------------------------
  //
  // The day's meals are generated for this person, from their target and
  // their exclusions. There is no default plan to fall back on: a fixed menu
  // shown to everyone is not a plan, it is a picture of one, and someone who
  // cannot eat what is on it has no way to tell that it was never about them.

  /// The generated day, or null before one exists.
  DayPlan? plan;

  /// The date [plan] was built for, so a day rolling over is noticed.
  String? planDate;

  bool planLoading = false;
  String? planError;

  bool get hasPlan => plan != null && plan!.slots.isNotEmpty;

  /// Each slot's meal, with the user's swaps applied.
  List<PlanMeal> planMeals() => [
        for (final (base, alt) in plan?.slots ?? const <(PlanMeal, PlanMeal)>[])
          isSlotSwapped(base.id) ? alt : base,
      ];

  /// True when the slot actually has somewhere else to go. A meal whose
  /// alternative came back identical gets no swap button rather than a button
  /// that appears to do nothing.
  bool slotHasAlternative(String slotId) {
    for (final (base, alt) in plan?.slots ?? const <(PlanMeal, PlanMeal)>[]) {
      if (base.id == slotId) return base.nameEn != alt.nameEn || base.nameAr != alt.nameAr;
    }
    return false;
  }

  /// The meal to put in front of the user right now, or null with no plan.
  ///
  /// Chosen by the clock rather than by a fixed index: the Today screen used
  /// to show lunch at every hour of the day, including at ten at night.
  PlanMeal? nextMeal() {
    final meals = planMeals();
    if (meals.isEmpty) return null;

    final hour = DateTime.now().hour;
    final wanted = hour < 11
        ? 'breakfast'
        : hour < 17
            ? 'lunch'
            : 'dinner';
    for (final m in meals) {
      if (m.id == wanted) return m;
    }
    return meals.first;
  }

  /// What today's quest actually asks for.
  ///
  /// It used to be two fixed strings — "Log lunch before 4pm" and "Logging
  /// early lets me adjust dinner" — shown to every user at every hour,
  /// including at ten at night, and including to someone whose plan has no
  /// lunch in it. That is the app deciding something Qamar should decide.
  ///
  /// Nothing new is generated here and no AI use is spent. The plan Qamar
  /// already wrote names the meals and explains them in its own words; this
  /// picks the slot that is due — the arithmetic — and quotes it.
  ///
  /// With no plan yet, it states the server's rule plainly rather than
  /// inventing a personal-sounding one: `qamar_complete_daily_quest` pays when
  /// a meal has been logged today in Cairo, and that is the whole condition.
  ({String titleAr, String titleEn, String bodyAr, String bodyEn}) questCard() {
    final m = nextMeal();
    if (m == null) {
      return (
        titleAr: 'سجّل وجبة النهارده',
        titleEn: 'Log a meal today',
        bodyAr: 'أول ما تسجّل وجبة، المهمة تتحسب.',
        bodyEn: 'The quest counts as soon as one meal is logged.',
      );
    }
    return (
      titleAr: 'سجّل ${m.slotAr}: ${m.nameAr}',
      titleEn: 'Log ${m.slotEn.toLowerCase()}: ${m.nameEn}',
      bodyAr: m.noteAr,
      bodyEn: m.noteEn,
    );
  }

  bool isSlotSwapped(String slotId) => swappedSlots.contains(slotId);

  void toggleSlotSwap(String slotId) {
    if (!swappedSlots.remove(slotId)) swappedSlots.add(slotId);
    _notify();
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  void _installPlan(DayPlan built) {
    plan = built;
    planDate = built.date;
    planError = null;
    // A rewritten menu is not the old one; carrying swaps would apply
    // yesterday's (or the previous dish's) choice to meals that are not there.
    swappedSlots.clear();
  }

  /// Builds today's plan. Safe to call on every visit to the Plan screen:
  /// it returns immediately if today's plan is already in hand.
  ///
  /// [instruction] is Qamar speaking as the nutritionist — a rebuild of the
  /// written menu, not a comment on it. The Plan and Today screens then show
  /// whatever comes back.
  Future<void> ensurePlan({bool force = false, String? instruction}) async {
    final today = _today();
    final note = instruction?.trim();
    if (!force && (note == null || note.isEmpty) && planDate == today && hasPlan) return;
    if (planLoading) return;

    final gateway = _ai;
    if (gateway == null) {
      planError = isAr
          ? 'الخطة بتتكتب لك إنت بالذات، وده محتاج اتصال بالمساعد.'
          : 'The plan is written for you specifically, which needs a connection to the assistant.';
      _notify();
      return;
    }

    planLoading = true;
    planError = null;
    _notify();
    try {
      final built = await gateway.generatePlan(
        date: today,
        lang: lang.code,
        force: force,
        instruction: (note == null || note.isEmpty) ? null : note,
      );
      if (_disposed) return;
      await _pullQuota(gateway);
      _installPlan(built);
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      aiQuota = e.quota;
      planError = e.message;
    } catch (e) {
      if (_disposed) return;
      planError = _planMessage(e);
    }
    planLoading = false;
    _notify();
  }

  /// The gateway refuses to guess, and its refusals are actionable — say what
  /// they mean rather than showing a raw HTTP status.
  String _planMessage(Object e) {
    final raw = '$e';
    if (raw.contains('409') || raw.contains('no target')) {
      return isAr
          ? 'محتاج أعرف هدفك الأول. كمّل الأسئلة وهعملك الخطة.'
          : 'I need your target first. Finish the questions and I will build the plan.';
    }
    if (raw.contains('503') || raw.contains('no grounded guidance')) {
      return isAr
          ? 'مفيش مصادر موثوقة متسجلة لسه، ومش هألّف خطة من دماغي.'
          : 'There is no trusted guidance loaded yet, and I will not invent a plan.';
    }
    if (raw.contains('403') || raw.contains('not eligible')) {
      return isAr ? 'الحساب ده مش مؤهل للخطط.' : 'This account is not eligible for plans.';
    }
    if (raw.contains('429') || raw.toLowerCase().contains('quota')) {
      return isAr
          ? 'خلصت استخدامات قمر النهارده. افتح المحفظة وصرف نقاط Su على استخدام زيادة.'
          : 'That’s today’s Qamar uses. Open the wallet and spend Su Points on another use.';
    }
    return isAr
        ? 'مقدرتش أعمل الخطة دلوقتي. جرّب تاني بعد شوية.'
        : 'I could not build the plan just now. Try again in a moment.';
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
    _refreshQuota();
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
      final result = await gateway.chatReply(
        message: text,
        lang: lang.code,
        date: _today(),
        currentPlan: plan == null ? null : planToWire(plan!),
        swappedSlots: swappedSlots.toList(),
      );
      if (_disposed) return;

      var menuMoved = false;
      if (result.plan != null) {
        _installPlan(result.plan!);
        menuMoved = true;
      } else if (result.rebuildInstruction != null && result.rebuildInstruction!.trim().isNotEmpty) {
        while (planLoading && !_disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        if (_disposed) return;
        await ensurePlan(force: true, instruction: result.rebuildInstruction);
        menuMoved = hasPlan;
      }

      if (_disposed) return;
      await _pullQuota(gateway);
      chatState = ChatState.idle;
      turn += 1;
      final action = result.action ??
          (menuMoved ? (isAr ? 'شوفي الخطة' : 'See the plan') : null);
      chat.add(ChatTurn(who: ChatWho.q, text: result.reply, action: action));
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      _onQuotaHit(e);
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
    final toWallet = chat.isNotEmpty && chat.last.openWallet;
    chatOpen = false;
    screen = toWallet ? AppScreen.wallet : AppScreen.plan;
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
    if (kind == QuickLog.photo && !photoLogAllowed) {
      refusePhotoLog();
      return;
    }
    if (kind == QuickLog.scan && !labelScanAllowed) {
      refuseCameraFeature(
        ar: 'قراءة جدول القيم الغذائية بتستخدم الكاميرا والموديل، وده لـ Qamar+.',
        en: 'Reading a nutrition panel uses the camera and the model, so it is Qamar+.',
      );
      return;
    }
    treeOpen = false;
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    openChat();

    // Both hand the shot back: the caller opens the camera, then calls
    // logPhotoTaken or scanLabelPhoto with the file.
    if (kind == QuickLog.photo || kind == QuickLog.scan) return;

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
  /// analysing page and no confirm page. Qamar+ only: vision spends a daily use.
  void logPhotoTaken(String path) {
    if (!photoLogAllowed) {
      refusePhotoLog();
      return;
    }
    lastMealPhotoPath = path;
    _loggingMeal = false;
    proposalInput = 'photo';
    chat.add(ChatTurn(who: ChatWho.u, text: isAr ? 'صوّرت الوجبة دي' : 'I photographed this meal'));
    _notify();
    _analyseMeal(inputType: 'photo', imagePath: path);
  }

  // ---- scanning a packet ------------------------------------------------
  //
  // Two ways in, one way out. A barcode is looked up; a nutrition panel is
  // photographed and read. Both come back in the same shape and both end as an
  // ordinary proposal, so confirming a scanned packet writes the same meal_logs
  // row as typing one — which is what makes it count towards the day, the
  // micronutrient gaps and the Su award, instead of being a separate feature
  // with its own half of the app.
  //
  // Nothing is written until the user confirms. That rule does not bend for
  // scanning: a misread panel costs a tap.

  /// The barcode whose lookup just failed, so a panel photographed next is
  /// filed under it. Null at every other moment.
  String? _pendingBarcode;

  /// Set when Qamar had to guess how much of the packet was eaten. The sheet
  /// turns this into a question rather than printing the number as though the
  /// packet had said so.
  bool scanPortionAssumed = false;

  /// The last thing a scan said that was not a proposal — a packet nobody has
  /// catalogued, or a panel too blurry to trust.
  String? scanNotice;

  bool scanBusy = false;

  /// True when the next useful thing is a photograph of the nutrition panel:
  /// the barcode was not in any catalogue, or the panel that was photographed
  /// could not be read and is worth another try.
  bool awaitingLabelPhoto = false;

  /// Says the camera or the picker itself failed, without pretending the scan
  /// found nothing — those are different, and only one of them is worth
  /// retrying with a better photo.
  void reportScanProblem(String detail) {
    scanNotice = isAr
        ? 'مقدرتش أفتح الكاميرا.'
        : 'I could not open the camera.';
    syncError = 'scan: $detail';
    _notify();
  }

  /// Reads the nutrition panel on a packet.
  ///
  /// [barcode] is passed automatically when this follows a failed lookup; the
  /// panel then becomes the catalogue entry for that code and the next person
  /// to scan it pays nothing.
  Future<void> scanLabelPhoto(String path, {String? barcode}) async {
    if (!labelScanAllowed) {
      refuseCameraFeature(
        ar: 'قراءة جدول القيم الغذائية بتستخدم الكاميرا والموديل، وده لـ Qamar+.',
        en: 'Reading a nutrition panel uses the camera and the model, so it is Qamar+.',
      );
      return;
    }
    await _scan(
      inputLabel: isAr ? 'صوّرت جدول القيم الغذائية' : 'I photographed the nutrition panel',
      run: (gateway) => gateway.scanLabel(
        imagePath: path,
        lang: lang.code,
        date: _today(),
        barcode: barcode ?? _pendingBarcode,
      ),
    );
  }

  /// Looks a packet up by the code on it.
  Future<void> scanPacketBarcode(String code) async {
    if (!barcodeScanAllowed) {
      refuseCameraFeature(
        ar: 'مسح الباركود بيستخدم الكاميرا، وده لـ Qamar+.',
        en: 'Scanning a barcode uses the camera, so it is Qamar+.',
      );
      return;
    }
    final digits = code.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    await _scan(
      inputLabel: isAr ? 'مسحت الباركود ده' : 'I scanned this barcode',
      run: (gateway) => gateway.scanBarcode(
        barcode: digits,
        lang: lang.code,
        date: _today(),
      ),
      barcode: digits,
    );
  }

  Future<void> _scan({
    required String inputLabel,
    required Future<ScanResult> Function(AiGateway gateway) run,
    String? barcode,
  }) async {
    final gateway = _ai;
    if (gateway == null) {
      scanNotice = isAr
          ? 'المسح محتاج اتصال بالمساعد.'
          : 'Scanning needs a connection to the assistant.';
      _notify();
      return;
    }

    openChat();
    scanNotice = null;
    scanPortionAssumed = false;
    awaitingLabelPhoto = false;
    scanBusy = true;
    chatState = ChatState.thinking;
    chat.add(ChatTurn(who: ChatWho.u, text: inputLabel));
    _notify();

    try {
      final res = await run(gateway);
      if (_disposed) return;
      await _pullQuota(gateway);
      chatState = ChatState.idle;

      if (!res.found) {
        // A packet nobody has catalogued, or a panel that could not be
        // trusted. Both are real answers with no numbers attached, and the
        // reply already says what to do instead.
        // A barcode miss remembers the code so the panel photographed next is
        // filed under it. A rejected panel keeps whatever code was already
        // pending — the packet has not changed just because the photo was bad.
        _pendingBarcode = res.problem == null ? (barcode ?? res.barcode) : _pendingBarcode;
        // Either way the next useful move is the same: photograph the panel.
        awaitingLabelPhoto = true;
        scanNotice = res.reply;
        proposal = null;
        proposalQty = [];
        chat.add(ChatTurn(who: ChatWho.q, text: res.reply));
        scanBusy = false;
        _notify();
        return;
      }

      _pendingBarcode = null;
      awaitingLabelPhoto = false;
      proposalInput = 'scan';
      proposalRaw = res.barcode;
      scanPortionAssumed = res.portionAssumed;
      _loggingMeal = false;

      final name = res.displayName;
      final portion = res.portionLabel ?? '${res.grams} g';
      proposal = MealAnalysis([
        ConfirmItemDef(
          ar: name,
          en: name,
          portionAr: portion,
          portionEn: portion,
          // The figures were transcribed off the printed panel or read from a
          // catalogue entry, not estimated from a photograph of a plate.
          conf: Confidence.high,
          kcal: res.kcal,
          p: res.proteinG,
          c: res.carbsG,
          f: res.fatG,
          grams: res.grams.toDouble(),
          portionMatched: !res.portionAssumed,
        ),
      ]);
      proposalQty = [1];

      chat.add(ChatTurn(
        who: ChatWho.q,
        text: res.reply,
        sub: _scanSub(res),
      ));

      // Qamar may have moved the rest of the day to make room. The gateway has
      // already saved that menu and already checked it against this person's
      // allergies, so the app installs it rather than asking for it again.
      if (res.plan != null) {
        _installPlan(res.plan!);
      } else if (res.rebuildInstruction != null && res.rebuildInstruction!.trim().isNotEmpty) {
        unawaited(ensurePlan(force: true, instruction: res.rebuildInstruction));
      }
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      _onQuotaHit(e);
    } catch (e) {
      if (_disposed) return;
      chatState = ChatState.idle;
      scanNotice = isAr
          ? 'مقدرتش أوصل للمساعد عشان أقرأ العلبة. جرّب تاني بعد شوية.'
          : 'I could not reach the assistant to read the packet. Try again in a moment.';
      chat.add(ChatTurn(who: ChatWho.q, text: scanNotice!, sub: '$e'.length > 120 ? null : '$e'));
    }
    scanBusy = false;
    _notify();
  }

  /// The line under Qamar's reply: where the numbers came from, and what is
  /// still a guess. Both are things somebody might want to check.
  String? _scanSub(ScanResult res) {
    final parts = <String>[];
    if (res.portionAssumed) {
      parts.add(isAr
          ? 'الكمية تقدير — العلبة مكتوبش عليها وزن'
          : 'portion assumed — the packet gave no weight');
    }
    if (res.basis == 'per_serving') {
      parts.add(isAr ? 'الجدول للحصة، حوّلته' : 'panel was per serving, converted');
    }
    if (res.energyFromKj) {
      parts.add(isAr ? 'الطاقة محوّلة من كيلوجول' : 'energy converted from kJ');
    }
    if (res.remainingKcal != null) {
      parts.add(isAr
          ? 'باقي ${res.remainingKcal} سعرة النهارده'
          : '${res.remainingKcal} kcal left today');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Says why a camera feature is closed, without pretending it is broken.
  void refuseCameraFeature({required String ar, required String en}) {
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    plusNotice = isAr ? ar : en;
    go(AppScreen.subscription);
  }

  void dismissScanNotice() {
    scanNotice = null;
    awaitingLabelPhoto = false;
    _notify();
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
