import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import '../models/meal.dart';
import '../models/messages.dart';
import '../models/onboarding.dart';
import '../widgets/explain.dart';
import '../models/profile.dart';
import 'chat_replies.dart';

/// Qamar+ billing period.
enum PlusPlan { monthly, annual }

/// How a meal gets logged straight from the orb, with no page in between.
enum QuickLog { voice, text, photo }

enum AppScreen { welcome, scan, onboard, today, log, analyzing, confirm, plan, progress, you, wallet, subscription }

enum ChatState { idle, listening, thinking }

enum WalletTab { spend, history }

/// Single app-wide store — the Dart counterpart of the prototype's one
/// `Component extends DCLogic { state = {...} }`. Screens read it via
/// `context.watch<AppState>()` and call its methods the way the prototype's
/// markup called `{{ handler }}`.
class AppState extends ChangeNotifier {
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
  String mealDraft = '';

  final List<ChatTurn> chat = [];
  String chatDraft = '';
  final List<int> qty = [1, 2, 1];

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
    qty
      ..clear()
      ..addAll([1, 2, 1]);
    scanned = false;
    scanReading = false;
    suAvailable = 0;
    suLifetime = 0;
    redeemed.clear();
    ledgerExtra.clear();
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

  void capture() {
    scanReading = true;
    scanCameraError = null;
    _notify();
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (_disposed) return;
      scanReading = false;
      scanned = true;
      screen = AppScreen.onboard;
      step = 0;
      msgs.clear();
      profile = profile.copyWith(age: 31, height: 174, weight: 86, fat: 29);
      _notify();
      Future.delayed(const Duration(milliseconds: 140), () => askStep(0));
    });
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
        final p = profile;
        _pushQ(
          'أخدت الأرقام من تقرير InBody: ${iso('${p.age}')} سنة · ${iso('${p.height}')} سم · ${iso('${p.weight}')} كجم · دهون ${iso('${p.fat}')}٪. لو في حاجة غلط اكتبهالي.',
          'I took your numbers from the InBody report: ${p.age} yrs · ${p.height} cm · ${p.weight} kg · ${p.fat}% body fat. Type a correction if anything is off.',
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
      suAvailable += 20;
      suLifetime += 20;
      _notify();
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

  List<({ConfirmItemDef def, int q})> confirmItemsWithQty() =>
      List.generate(kMockConfirmItems.length, (i) => (def: kMockConfirmItems[i], q: qty[i]));

  Totals confirmTotals() {
    var k = 0, p = 0, c = 0, f = 0;
    for (final it in confirmItemsWithQty()) {
      k += it.def.kcal * it.q;
      p += it.def.p * it.q;
      c += it.def.c * it.q;
      f += it.def.f * it.q;
    }
    return Totals(kcal: k, p: p, c: c, f: f);
  }

  void incQty(int i) {
    qty[i] = math.min(6, qty[i] + 1);
    _notify();
  }

  void decQty(int i) {
    qty[i] = math.max(0, qty[i] - 1);
    _notify();
  }

  void onMealDraftChanged(String v) {
    mealDraft = v;
    _notify();
  }

  void presetMealDraftExample() {
    mealDraft = isAr ? 'كشري وسط + دقة' : 'medium koshary + daqqa';
    _notify();
  }

  void startAnalyze() {
    screen = AppScreen.analyzing;
    _notify();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (!_disposed && screen == AppScreen.analyzing) {
        screen = AppScreen.confirm;
        _notify();
      }
    });
  }

  void confirmMeal() {
    final totals = confirmTotals();
    final name = isAr ? 'كشري + دقة' : 'Koshary + daqqa';
    final sub = isAr ? 'مسجّل بالكتابة · تقدير' : 'Logged by text · estimate';
    meals.add(LoggedMeal(name: name, sub: sub, kcal: totals.kcal, p: totals.p, c: totals.c, f: totals.f));
    screen = AppScreen.today;
    suAvailable += 10;
    suLifetime += 10;
    qty
      ..clear()
      ..addAll([1, 2, 1]);
    _notify();
  }

  // ---- quest / wallet -------------------------------------------------

  void completeQuest() {
    questDone = true;
    suAvailable += 5;
    suLifetime += 5;
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

  void redeem(SpendItemDef item) {
    final done = isRedeemed(item.id);
    final afford = suAvailable >= item.price && !done;
    if (!afford) return;
    suAvailable -= item.price;
    redeemed.add(item.id);
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? item.nameAr : item.nameEn, amount: -item.price, when: isAr ? 'دلوقتي' : 'Just now'));
    _notify();
  }

  List<LedgerEntry> ledger() => [
        ...ledgerExtra,
        if (meals.isNotEmpty) LedgerEntry(label: isAr ? 'تأكيد أول وجبة' : 'First meal confirmed', amount: 10, when: isAr ? 'النهاردة' : 'Today'),
        if (suLifetime >= 20) LedgerEntry(label: isAr ? 'إكمال التهيئة' : 'Onboarding completed', amount: 20, when: isAr ? 'النهاردة' : 'Today'),
        if (questDone) LedgerEntry(label: isAr ? 'مهمة اليوم' : 'Primary daily quest', amount: 5, when: isAr ? 'النهاردة' : 'Today'),
      ];

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

  void sendChatMsg(String text) {
    final list = isAr ? kChatRepliesAr : kChatRepliesEn;
    chat.add(ChatTurn(who: ChatWho.u, text: text));
    lastUser = text;
    chatDraft = '';
    chatState = ChatState.thinking;
    _notify();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (_disposed) return;
      final r = list[turn % list.length];
      chatState = ChatState.idle;
      turn += 1;
      chat.add(ChatTurn(who: ChatWho.q, text: r.d, sub: r.r, action: r.a.isEmpty ? null : r.a));
      _notify();
    });
  }

  void tapOrbListen() {
    if (chatState == ChatState.thinking) return;
    final prompts = isAr ? kChatPromptsAr : kChatPromptsEn;
    chatState = ChatState.listening;
    lastUser = '';
    _notify();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_disposed) return;
      final p = prompts[turn % prompts.length];
      sendChatMsg(p);
    });
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
        AppScreen.log,
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
  void quickLog(QuickLog kind) {
    treeOpen = false;
    treeHold = false;
    treeHoverNode = null;
    treeHoverSub = null;
    treeLogIndex = null;
    if (kind == QuickLog.text) presetMealDraftExample();
    startAnalyze();
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
