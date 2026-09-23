import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:intl/intl.dart';

import '../l10n/trial_words.dart';
import '../l10n/strings.dart';
import '../l10n/words.dart';
import '../models/days.dart';
import '../models/dishes.dart';
import '../models/meal.dart';
import '../models/messages.dart';
import '../models/nudge.dart';
import '../models/onboarding.dart';
import '../models/plan.dart';
import '../models/problem.dart';
import '../models/quest.dart';
import '../models/streak.dart';
import '../models/su_economy.dart';
import '../services/ai_gateway.dart';
import '../services/analytics.dart';
import '../services/auth_service.dart';
import '../services/device_prefs.dart';
import '../services/dictation.dart';
import '../services/nudger.dart';
import '../services/photos.dart';
import '../services/settings_link.dart' as settings_link;
import '../services/sharer.dart';
import '../services/config.dart';
import '../services/payments.dart';
import '../services/repositories.dart';
import '../models/activity.dart';
import '../models/billing.dart';
import '../models/basket.dart';
import '../models/pending_write.dart';
import '../models/invitation.dart';
import '../widgets/explain.dart';
import '../models/profile.dart';
import '../models/ramadan.dart';
import '../models/reply.dart';
import '../models/review.dart';
import '../models/water.dart';
import 'chat_replies.dart';

/// Qamar+ billing period. One plan; annual and family wait on retention.
enum PlusPlan { monthly }

/// A billing moment Today can carry: the free week or the paid month in its
/// last 48 hours. See [AppState.billingMoment].
enum BillingMoment { none, trialEnding, membershipEnding }

/// How a meal gets logged straight from the orb, with no page in between.
enum QuickLog { voice, text, photo, repeat, activity }

/// The Log node's third level: the ring shows kinds of movement, or recent
/// meals to repeat.
enum TreeSub { activity, repeat }

/// The orb's whole vocabulary. Tap opens the tree (or comes back to Today),
/// hold talks to Qamar, dragging it onto a number explains that number.
enum OrbGesture { tap, hold, explain }

/// The three places the orb can rest in its band at the bottom of the
/// screen (O1), start-relative: the start is the left in English and the
/// right in Arabic.
enum OrbStop { start, centre, end }

enum AppScreen { welcome, scan, onboard, today, plan, progress, you, wallet, subscription, ramadan }

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
    InvitationRepository? invitationRepo,
    ActivityRepository? activityRepo,
    AiGateway? ai,
    BillingGateway? billing,
    Future<bool> Function(String url)? openCheckout,
    GroceryPartner? grocery,
    Dictation? dictation,
    Account? auth,
    String? userId,
    DevicePrefs? prefs,
    Nudger? nudger,
    Sharer? sharer,
    Analytics? analytics,
    DateTime Function()? clock,
    Future<bool> Function()? openSettings,
  })  : _profileRepo = profileRepo,
        _mealRepo = mealRepo,
        _waterRepo = waterRepo,
        _walletRepo = walletRepo,
        _invitationRepo = invitationRepo,
        _activityRepo = activityRepo,
        _ai = ai,
        _billing = billing,
        _openCheckout = openCheckout,
        _grocery = grocery ??
            const GroceryPartner(url: QamarConfig.groceryPartnerUrl, name: QamarConfig.groceryPartnerName, ref: QamarConfig.groceryAffiliateId),
        _dictation = dictation,
        _auth = auth,
        _userId = userId,
        _prefs = prefs,
        _nudger = nudger,
        _sharer = sharer,
        _analytics = analytics,
        _openSettings = openSettings ?? settings_link.openAppSettings,
        _clock = clock ?? DateTime.now {
    _watchAccount();
    _watchNudger();
    _devicePrefsLoaded = _loadDevicePrefs();
    if (isBacked) hydrate();
  }

  /// Completes once this phone's own choices have been read. Anything that
  /// merges a server value with a remembered one waits for it, so the phone's
  /// answer is read before it can be overwritten.
  late final Future<void> _devicePrefsLoaded;

  /// The phone's notification schedule. Null in tests and where there is
  /// none; then nudges exist only as the orb's pulse.
  final Nudger? _nudger;
  StreamSubscription<String>? _nudgeSub;

  /// The share sheet. Null in tests and where there is none.
  final Sharer? _sharer;

  /// The referral loop's server side. Null offline; then invitations are
  /// not offered, rather than offered and lost.
  final InvitationRepository? _invitationRepo;

  /// Movement logged by hand. Null offline; the day still shows it.
  final ActivityRepository? _activityRepo;

  /// Product analytics. Null in tests and in any build without a key; and
  /// even when present, silent until the person consents (see [setImprove]).
  final Analytics? _analytics;

  /// Injectable so the meal-time logic can be tested at a chosen hour.
  final DateTime Function() _clock;

  /// Opens Qamar's page in the phone's Settings (services/settings_link.dart).
  final Future<bool> Function() _openSettings;

  /// The app's idea of now — the injected clock, so screens and state agree.
  DateTime clockNow() => _clock();

  /// This phone's own choices. Null in tests and wherever there is no store;
  /// then nothing is remembered between launches, and nothing pretends to be.
  final DevicePrefs? _prefs;
  static const _kOrbTutorialDone = 'orb_tutorial_done';

  /// The gestures this phone has seen made on the orb, by name.
  static const _kOrbGestures = 'orb_gestures_learned';
  static const _kEasternDigits = 'eastern_digits';
  static const _kShowScore = 'show_score';
  static const _kNudgesPerDay = 'nudges_per_day';
  static const _kNudgesAllowed = 'nudges_allowed';
  static const _kNudgePromptDone = 'nudge_prompt_done';
  static const _kFirstDay = 'first_day';
  static const _kReviewNumbers = 'review_numbers';
  static const _kImprove = 'improve_consent';
  static const _kAdherence = 'adherence_consent';
  static const _kRamadanAsked = 'ramadan_asked';
  static const _kHoldCoachSeen = 'hold_coach_seen';
  static const _kWeekCardSeen = 'week_card_seen';
  static const _kOrbStop = 'orb_stop';

  Future<void> _loadDevicePrefs() async {
    final p = _prefs;
    if (p == null) return;
    try {
      final done = await p.getBool(_kOrbTutorialDone);
      final digits = await p.getBool(_kEasternDigits);
      final score = await p.getBool(_kShowScore);
      final perDay = int.tryParse(await p.getString(_kNudgesPerDay) ?? '');
      final allowed = await p.getBool(_kNudgesAllowed);
      final promptDone = await p.getBool(_kNudgePromptDone);
      final first = DateTime.tryParse(await p.getString(_kFirstDay) ?? '');
      final reviewNumbers = await p.getBool(_kReviewNumbers);
      final consent = await p.getBool(_kImprove);
      final adherence = await p.getBool(_kAdherence);
      if (adherence != null) adherenceShare = adherence;
      final asked = await p.getString(_kRamadanAsked);
      final weekSeen = await p.getString(_kWeekCardSeen);
      final invite = await p.getString(_kPendingInvite);
      final proCode = await p.getString(_kPendingProCode);
      final proWho = await p.getString(_kProName);
      final lockDay = await p.getString(_kLockOfferDay);
      final stop = await p.getString(_kOrbStop);
      final stale = await p.getString(_kPlanStaleDays);
      if (_disposed) return;
      if (stale != null && stale.trim().isNotEmpty) _planStaleDays.addAll(stale.split(',').where((d) => d.trim().isNotEmpty));
      // A code from an earlier launch is still waiting to be redeemed.
      if (invite != null && invite.trim().isNotEmpty) pendingInvitationCode ??= invite.trim();
      if (proCode != null && proCode.trim().isNotEmpty) pendingProCode ??= proCode.trim();
      if (proWho != null && proWho.trim().isNotEmpty) proName ??= proWho.trim();
      if (lockDay != null && lockDay.trim().isNotEmpty) _lockOfferDay = lockDay.trim();
      if (asked != null) ramadanAskedFor = asked;
      // Where the person left the orb resting last time (O1).
      for (final s in OrbStop.values) {
        if (s.name == stop) orbStop = s;
      }
      if (weekSeen != null) _weekCardSeenDay = weekSeen;
      if (reviewNumbers != null) reviewShowNumbers = reviewNumbers;
      if (consent != null) {
        // Answered before on this phone: a yes sends what waited, a no drops it.
        improve = consent;
        improveAnswered = true;
        _syncAnalytics().ignore();
      }
      if (done == true) orbTutorialDismissed = true;
      for (final name in (await p.getString(_kOrbGestures) ?? '').split(',')) {
        for (final g in OrbGesture.values) {
          if (g.name == name) gesturesLearned.add(g);
        }
      }
      if (await p.getBool(_kHoldCoachSeen) == true) holdCoachSeen = true;
      if (digits != null) easternDigits = digits;
      if (score != null) showScore = score;
      if (perDay != null) nudgesPerDay = perDay.clamp(0, NudgeSchedule.maxPerDay);
      if (allowed != null) nudgesAllowed = allowed;
      if (promptDone == true) nudgePromptDone = true;
      // The fourteen-day window of push nudges starts on the first day this
      // phone or this account knew the app, whichever is earlier: the phone
      // remembers its own, and hydrate brings the account's from the server,
      // so a reinstall that signs back in does not restart the window.
      final now = _clock();
      _takeFirstDay(first ?? DateTime(now.year, now.month, now.day));
      _notify();
      _rescheduleNudges();
    } catch (_) {
      // A preference store that will not answer is a default, not an error.
    }
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

  // ---- shop this plan ----------------------------------------------------------
  //
  // Blueprint: "the plan sends every user to a grocery basket, and the
  // commission on that basket is the second income line". One signed
  // partner, by configuration; the basket is today's portions; the link
  // carries Qamar's reference. Absent a partner, absent from the app.

  final GroceryPartner _grocery;
  GroceryPartner get groceryPartner => _grocery;

  GroceryBasket get basket => GroceryBasket.fromMeals(planMeals());

  bool get canShopPlan => _grocery.enabled && hasPlan && !basket.isEmpty;

  String? shopNotice;

  Future<void> shopThisPlan() async {
    if (!canShopPlan) return;
    final b = basket;
    _track('basket_opened', {'items': b.count, 'partner': _grocery.name});
    final opener = _openCheckout ?? openExternalUrl;
    final ok = await opener(b.link(_grocery, ar: isAr).toString());
    if (_disposed) return;
    shopNotice = ok ? null : (isAr ? 'مقدرتش أفتح ${_grocery.name}. جرّب تاني.' : 'Could not open ${_grocery.name}. Try again.');
    _notify();
  }
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

  // ---- the offline logging queue ----------------------------------------------
  //
  // A meal, a glass or a walk is on the screen the instant it is tapped; the
  // server's copy follows. When that write fails — the metro, a lift, a bad
  // 3G day — the entry is kept on the phone and replayed when the app comes
  // back to the foreground, when the next write goes through, or on the next
  // start. The payload is everything the repository needs, so nothing on
  // screen has to survive for the replay to work.

  final List<PendingWrite> pendingWrites = [];
  bool _draining = false;

  /// After this many failed replays the write is dropped and the failure
  /// shown: a row the server refuses six times is not a signal problem.
  static const pendingMaxAttempts = 6;

  String _pendingKey(String uid) => 'pending_writes_$uid';

  void _savePending(String uid) {
    _prefs?.setString(_pendingKey(uid), PendingWrite.encode(pendingWrites)).catchError((_) {});
  }

  /// A write that must land. [write] does only the repository call(s), so a
  /// replay never duplicates a row that did land; [after] is the wallet or
  /// streak re-read that follows a success and is allowed to fail quietly.
  Future<void> _pushDurable(
    PendingWrite w,
    Future<void> Function(String userId) write, {
    Future<void> Function(String userId)? after,
  }) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await write(uid);
    } catch (_) {
      pendingWrites.add(w);
      _savePending(uid);
      syncError = isAr ? 'محفوظ على الموبايل، وهيتزامن لما النت يرجع.' : 'Saved on the phone; it syncs when the connection is back.';
      _notify();
      return;
    }
    if (syncError != null) {
      syncError = null;
      _notify();
    }
    if (after != null) {
      try {
        await after(uid);
      } catch (_) {
        // The write landed; a re-read that did not is the next hydrate's job.
      }
    }
    await drainPending();
  }

  /// Replays what is queued, oldest first, stopping at the first failure so
  /// order is kept. Safe to call any time.
  Future<void> drainPending() async {
    final uid = _userId;
    if (uid == null || _draining || pendingWrites.isEmpty) return;
    _draining = true;
    try {
      while (pendingWrites.isNotEmpty && !_disposed) {
        final w = pendingWrites.first;
        try {
          await _replay(uid, w);
          pendingWrites.removeAt(0);
          _savePending(uid);
        } catch (e) {
          final next = w.copyWith(attempts: w.attempts + 1);
          if (next.attempts >= pendingMaxAttempts) {
            pendingWrites.removeAt(0);
            syncError = '${w.kind.name}: $e';
          } else {
            pendingWrites[0] = next;
          }
          _savePending(uid);
          break;
        }
      }
      if (pendingWrites.isEmpty && syncError != null && !syncError!.contains(':')) syncError = null;
      _notify();
    } finally {
      _draining = false;
    }
  }

  Future<void> _replay(String uid, PendingWrite w) async {
    switch (w.kind) {
      case PendingKind.meal:
        final repo = _mealRepo;
        if (repo == null) return;
        final meal = LoggedMeal.fromJson((w.payload['meal'] as Map).cast<String, dynamic>());
        final items = [
          for (final raw in (w.payload['items'] as List? ?? const []))
            if (raw is Map)
              (def: ConfirmItemDef.fromJson((raw['def'] as Map).cast<String, dynamic>()), qty: (raw['qty'] as num?)?.round() ?? 1),
        ];
        final draftId = await repo.saveDraft(
          uid,
          MealAnalysisDraft(inputType: (w.payload['input'] ?? 'text') as String, items: items, rawText: w.payload['raw'] as String?),
        );
        await repo.confirmMeal(uid, draftId: draftId, meal: meal, items: items);
        try {
          await _refreshStreak(uid);
          await _refreshWallet(uid);
        } catch (_) {}
      case PendingKind.water:
        final repo = _waterRepo;
        if (repo == null) return;
        await repo.addSip(uid, WaterSip.fromJson(w.payload));
        try {
          await _refreshWallet(uid);
        } catch (_) {}
      case PendingKind.activity:
        final repo = _activityRepo;
        if (repo == null) return;
        await repo.add(uid, ActivityLog.fromJson(w.payload));
        try {
          await _refreshWallet(uid);
        } catch (_) {}
    }
  }

  /// The ledger is the wallet. Read after anything that earns — a meal, a
  /// glass, the quest, onboarding — so the phone's optimistic number and the
  /// server's agree within a second, and a point never has to vanish on the
  /// next start.
  Future<void> _refreshWallet(String uid) async {
    final repo = _walletRepo;
    if (repo == null) return;
    final bal = await repo.balance(uid);
    if (_disposed) return;
    suAvailable = bal.available;
    suLifetime = bal.lifetime;
    final entries = await repo.ledger(uid);
    if (_disposed) return;
    serverLedger
      ..clear()
      ..addAll(entries);
    // What one more question costs, as the server will charge it (0066).
    try {
      final price = await repo.questionPrice();
      if (_disposed) return;
      if (price != null && price > 0) questionPrice = price;
    } catch (_) {
      // The last price read stands; the server charges its own anyway.
    }
    // The write that earned may also have met the day's quest.
    await _refreshQuest(uid);
  }

  /// Pulls the server's copy over the local defaults on start.
  Future<void> hydrate() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      // Whatever was logged without a signal goes up before today is read
      // back, so it is part of what comes back.
      pendingWrites
        ..clear()
        ..addAll(PendingWrite.decode(await _prefs?.getString(_pendingKey(uid))));
      await drainPending();

      final saved = await _profileRepo?.loadProfile(uid);
      if (saved != null) profile = saved;

      // Day 0 as the server has it — the metrics' day 0 as well. Merged only
      // after the phone's own first day has been read, so the earlier wins.
      try {
        final day0 = await _profileRepo?.accountDay0(uid);
        await _devicePrefsLoaded;
        if (day0 != null && _takeFirstDay(day0)) _rescheduleNudges();
      } catch (_) {
        // The phone's own first day stands until the server answers.
      }

      try {
        final consent = await _profileRepo?.loadConsent(uid, ConsentType.improve);
        if (consent != null && (consent != improve || !improveAnswered)) {
          improve = consent;
          improveAnswered = true;
          _prefs?.setBool(_kImprove, consent).catchError((_) {});
          _syncAnalytics().ignore();
        }
        final sharing = await _profileRepo?.loadConsent(uid, ConsentType.adherence);
        if (sharing != null && sharing != adherenceShare) {
          adherenceShare = sharing;
          _prefs?.setBool(_kAdherence, sharing).catchError((_) {});
        }
      } catch (_) {
        // The phone's own record stands until the server answers.
      }

      final today = await _mealRepo?.mealsForDay(uid, DateTime.now());
      if (today != null) {
        meals
          ..clear()
          ..addAll(today);
      }

      final recent = await _mealRepo?.recentMeals(uid);
      if (recent != null) {
        recentMeals
          ..clear()
          ..addAll(recent);
      }

      final acts = await _activityRepo?.forDay(uid, DateTime.now());
      if (acts != null) {
        activitiesToday
          ..clear()
          ..addAll(acts);
      }

      final water = await _waterRepo?.sipsForDay(uid, DateTime.now());
      if (water != null) {
        waterToday
          ..clear()
          ..addAll(water);
      }

      await _refreshWallet(uid);

      await _refreshQuota();
      await _refreshPlus();
      await _refreshAffiliate();
      await _refreshInvitations(uid);
      await _refreshSeason();

      // Two months, not one week: the chart reads seven days, the streak
      // reads as far back as the run goes.
      final history = await _mealRepo?.dailyTotals(uid, days: 60);
      if (history != null) {
        dayHistory
          ..clear()
          ..addAll(history);
      }
      await _refreshStreak(uid);
      await _refreshNightNote(uid);
      final times = await _mealRepo?.mealTimes(uid);
      if (times != null) mealTimes = times;

      final weights = await _mealRepo?.weightHistory(uid);
      if (weights != null) {
        weightHistory
          ..clear()
          ..addAll(weights);
      }

      _notify();
      _rescheduleNudges();
      await _redeemPendingInvitation();
      await _redeemPendingProCode();
    } catch (e) {
      syncError = 'load: $e';
      _notify();
    }
  }

  AppLang lang = AppLang.ar;
  /// The screen on show. Every change of screen goes through the setter, so
  /// the way back is always known (see [back]).
  AppScreen get screen => _screenNow;
  set screen(AppScreen s) {
    if (s == _screenNow) return;
    _recordTrail(to: s);
    _screenNow = s;
  }

  AppScreen _screenNow = AppScreen.welcome;

  // ---- the way back: one rule (seat 2) ---------------------------------------
  //
  // Every screen but the two roots — the welcome screen and Today — has one
  // back control, in the same place (the top start corner) with the same
  // arrow, and it returns to the screen the person came from. The phone's own
  // back does the same, after closing whatever sheet is open. The orb, where it
  // shows, is the way home to Today.

  /// The roots: nothing to go back to from here.
  static const rootScreens = {AppScreen.welcome, AppScreen.today};

  /// The screens the person came through to reach this one, most recent last.
  /// Reaching a root clears it; going back to a screen already on it cuts it
  /// there, so it never loops.
  final List<AppScreen> _trail = [];

  void _recordTrail({required AppScreen to}) {
    if (rootScreens.contains(to)) {
      _trail.clear();
      return;
    }
    final at = _trail.indexOf(to);
    if (at >= 0) {
      _trail.removeRange(at, _trail.length);
      return;
    }
    _trail.add(_screenNow);
  }

  /// Every screen but the roots has a way back.
  bool get canGoBack => !rootScreens.contains(screen);

  /// Where [back] would go from here.
  AppScreen get backTarget => _trail.isNotEmpty ? _trail.last : _parentOf(screen);

  static AppScreen _parentOf(AppScreen s) => switch (s) {
        AppScreen.onboard || AppScreen.scan => AppScreen.welcome,
        _ => AppScreen.today,
      };

  /// The screen's back control: to the screen the person came from.
  void back() {
    if (!canGoBack) return;
    final from = screen;
    final to = _trail.isNotEmpty ? _trail.removeLast() : _parentOf(from);
    if (from == AppScreen.scan) scanReading = false;
    // Leaving the consultation part-way keeps its answers: coming back to it
    // carries on where it was, so a slip of the thumb costs nothing.
    if (from == AppScreen.onboard && msgs.any((m) => m.kind == ObKind.u)) consultationPaused = true;
    _screenNow = to;
    _collapseTree();
    _track('back', {'from': from.name, 'to': to.name});
    _notify();
    _screen(to);
  }

  /// The consultation was left part-way with the back control; starting it
  /// again resumes it rather than beginning at the first question.
  bool consultationPaused = false;

  /// Whether the phone's back has something to do in the app: a sheet or an
  /// overlay to close, or a screen to go back from. At a root with nothing
  /// open it is the system's (leaving the app).
  bool get handlesSystemBack =>
      explainOpen != null || whyOpen || authOpen || pendingActivity != null || chatOpen || treeOpen || canGoBack;

  /// The phone's back: the topmost sheet or overlay first, then [back].
  void systemBack() {
    if (explainOpen != null) return closeExplain();
    if (pendingActivity != null) return cancelActivity();
    if (authOpen) return closeAuth();
    if (whyOpen) return closeWhy();
    if (chatOpen) return closeChat();
    if (treeOpen) return closeTree();
    back();
  }
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

  WaterStatus get water => WaterStatus(
        waterToday.fold<int>(0, (sum, s) => sum + s.ml),
        goalMl: fasting ? HydrationWindows.goalMl : Water.goalMl,
      );

  /// Days that actually have logged meals behind them, from the backend.
  /// Empty offline and empty for a new user — the Progress screen says so
  /// rather than drawing a week that never happened.
  final List<DayTotals> dayHistory = [];

  /// Recorded weigh-ins, oldest first.
  final List<WeightReading> weightHistory = [];

  /// The server's streak, when it has answered. Freezes only exist here —
  /// the local count in [streak] never fills a day in on its own.
  Streak? serverStreak;

  /// The wallet ledger as the database has it. Authoritative when present;
  /// [ledgerExtra] covers the offline case.
  final List<LedgerEntry> serverLedger = [];

  final List<ChatTurn> chat = [];
  String chatDraft = '';

  ChatState chatState = ChatState.idle;
  String lastUser = '';
  int turn = 0;
  bool chatOpen = false;

  /// Where the orb rests (O1): one of three stops in the band at the bottom
  /// of the screen — start, centre, end — chosen by where the person lets go
  /// of it, and kept on the phone. Start-relative, so the layout mirrors in
  /// Arabic. The end stop by default.
  OrbStop orbStop = OrbStop.end;

  /// True while the orb is off the band: held under a finger, or placed at
  /// [orbStart]/[orbY] by [setOrbPosition]. Letting go ([settleOrb]) puts it
  /// back at a stop. It never rests on the page's content.
  bool orbHeld = false;

  /// Where a held orb is, measured from the start edge of the screen — the
  /// left in English, the right in Arabic — so the layout mirrors with the
  /// language (O1).
  double orbStart = 290;
  double orbY = 620;

  bool treeOpen = false;
  int suAvailable = 0;
  int suLifetime = 0;

  /// Today's counters. [aiQuota] is the question bucket the conversation shows;
  /// [photoQuota] is the photo bucket the Log ring shows.
  AiQuota aiQuota = AiQuota.empty;
  AiQuota photoQuota = AiQuota.emptyPhoto;
  /// Meal slots the user has swapped to their alternative, keyed by slot id
  /// ('breakfast' | 'lunch' | 'dinner'). Previously a single bool, which meant
  /// every meal's swap button drove the same flag and only lunch ever changed.
  final Set<String> swappedSlots = {};
  bool blocked = false;
  bool minor = false;
  bool improve = false;

  /// The service-improvement question has been answered — yes or no, in the
  /// consultation, on the You screen, earlier on this phone or on the
  /// account. Until it has, events wait on the phone (see [_track]).
  bool improveAnswered = false;

  /// The service-improvement consent: asked in the consultation, changeable
  /// on the You screen, recorded on the account, and the one switch that
  /// turns analytics on or off. Nothing leaves the phone without it. The
  /// first answer is recorded whichever way it goes, so a "no" is on the
  /// account as a no rather than as silence.
  Future<void> setImprove(bool on) async {
    final changed = improve != on;
    final firstAnswer = !improveAnswered;
    improve = on;
    improveAnswered = true;
    _notify();
    _prefs?.setBool(_kImprove, on).catchError((_) {});
    if ((changed || firstAnswer) && isBacked && _profileRepo != null) {
      _push('save consent', (uid) => _profileRepo.saveConsent(uid, ConsentType.improve, granted: on, version: QamarConfig.consentVersion));
    }
    await _syncAnalytics(consentEvent: changed && on);
  }

  // ---- sharing adherence with a nutritionist --------------------------------
  //
  // Blueprint: "enter a nutritionist's code; consent to share adherence". The
  // professional whose code is on the subscription sees the week as numbers
  // — days logged, days near the target, the average — and nothing else.
  // Off until said yes to; withdrawable; recorded like the other consents.

  bool adherenceShare = false;

  Future<void> setAdherenceShare(bool on) async {
    final changed = adherenceShare != on;
    adherenceShare = on;
    _notify();
    _prefs?.setBool(_kAdherence, on).catchError((_) {});
    if (changed) _track('adherence_consent', {'granted': on});
    if (changed && isBacked && _profileRepo != null) {
      _push('save consent', (uid) => _profileRepo.saveConsent(uid, ConsentType.adherence, granted: on, version: QamarConfig.consentVersion));
    }
  }

  /// The professional's side: clients who said yes, with this week's numbers.
  /// Empty for anyone without clients, so the card simply does not appear.
  List<ProClient> proClients = const [];

  Future<void> _syncAnalytics({bool consentEvent = false}) async {
    final a = _analytics;
    if (a == null) return;
    if (improve) {
      await a.enable(_userId);
      if (_disposed) return;
      if (!improve) {
        // A "no" arrived while the sink was starting: it stops again.
        await a.disable();
        return;
      }
      _analyticsOn = true;
      // The yes is the first event; what waited for it follows, in order.
      if (consentEvent) _track('consent_granted', {'version': QamarConfig.consentVersion});
      final waiting = List.of(_held);
      _held.clear();
      for (final e in waiting) {
        a.track(e.name, e.props).ignore();
      }
    } else {
      _analyticsOn = false;
      if (improveAnswered) _held.clear();
      await a.disable();
    }
  }

  // ---- analytics ---------------------------------------------------------
  //
  // The blueprint's kill metrics and the events that explain them. Every
  // event carries the language, the tier and whether the account is backed,
  // and nothing else about the person: no name, no body, no food, no photo.
  //
  // Nothing is sent before a yes. But the funnel starts before the question
  // is asked — the app opens, Start is pressed, the first answers are given —
  // so until the question has been answered, events wait on the phone, in
  // memory: sent in order on a yes (marked pre_consent), thrown away on a
  // no, and never held again once the answer is no.

  /// The sink has been switched on and not off since.
  bool _analyticsOn = false;

  /// Events waiting for the answer, oldest first.
  final List<({String name, Map<String, Object> props})> _held = [];

  /// Room for the walk from app open to the consent question with plenty to
  /// spare. Past it the newest are dropped, so the funnel's first events are
  /// never the ones pushed out.
  static const heldEventCap = 50;

  /// How many events are waiting on the phone for the answer.
  int get heldEvents => _held.length;

  void _track(String event, [Map<String, Object> props = const {}]) {
    final a = _analytics;
    if (a == null) return;
    final all = <String, Object>{...props, 'lang': lang.code, 'plus': plusActive, 'backed': isBacked};
    if (improve && _analyticsOn) {
      a.track(event, all).ignore();
      return;
    }
    // Not answered yet, or a yes still switching the sink on: wait. A no
    // that has been given drops the event where it stands.
    if ((improve || !improveAnswered) && _held.length < heldEventCap) {
      _held.add((name: event, props: improveAnswered ? all : {...all, 'pre_consent': true}));
    }
  }

  void _screen(AppScreen s) {
    final a = _analytics;
    if (a == null || !improve) return;
    a.screen(s.name).ignore();
  }

  /// When the last nudge was tapped, so a meal logged soon after counts as
  /// prompted — the distinction the day-30 habit metric rests on.
  DateTime? _nudgeTappedAt;

  bool get _nudgedRecently {
    final t = _nudgeTappedAt;
    return t != null && _clock().difference(t) < const Duration(minutes: 30);
  }

  /// What started the log in progress, captured when it starts: by the
  /// time it is confirmed, the orb's waiting question has gone (O6). Every
  /// way into a log sets it; the log's reading takes it along
  /// ([_proposalStart]); an abandoned log drops it.
  ({String prompt, bool orbWaiting})? _logStart;

  /// A push tapped in the last half hour wins; then a log that began from
  /// the orb's waiting question; then nothing. Whether a question was
  /// waiting is recorded whatever the path — a log from the tree while the
  /// orb pulses is the habit itself, and this is how that is told apart.
  ({String prompt, bool orbWaiting}) _logStartNow({bool fromWaitingQuestion = false}) => (
        prompt: _nudgedRecently
            ? LogPrompt.push
            : fromWaitingQuestion
                ? LogPrompt.inApp
                : LogPrompt.none,
        orbWaiting: waitingNudge != null,
      );

  /// Takes the captured start for a log being read now, or captures it.
  ({String prompt, bool orbWaiting}) _takeLogStart() {
    final start = _logStart ?? _logStartNow();
    _logStart = null;
    return start;
  }
  WalletTab walletTab = WalletTab.spend;
  bool whyOpen = false;
  final List<String> redeemed = [];
  final List<LedgerEntry> ledgerExtra = [];

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _nudgeSub?.cancel();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- language / strings -------------------------------------------------

  QStrings get t => QStrings.of(lang);
  bool get isAr => lang == AppLang.ar;

  /// Which digits Arabic draws: ٠١٢ (Eastern Arabic, the default Egypt reads
  /// on the street) or 012. Static Arabic copy keeps whatever digits it was
  /// written with; this governs every number the app computes.
  bool easternDigits = true;

  void setEasternDigits(bool on) {
    easternDigits = on;
    _notify();
    _prefs?.setBool(_kEasternDigits, on).catchError((_) {});
  }

  static const _western = '0123456789';
  static const _eastern = '٠١٢٣٤٥٦٧٨٩';

  /// [x] with its digits drawn the way this phone asked for, in Arabic only.
  String digits(String x) {
    if (!isAr || !easternDigits) return x;
    final out = StringBuffer();
    for (final ch in x.split('')) {
      final i = _western.indexOf(ch);
      out.write(i >= 0 ? _eastern[i] : ch);
    }
    return out.toString();
  }

  /// Wraps mixed number/word fragments in Unicode bidi isolates, exactly
  /// like the prototype's `iso()` — keeps "٨٢ كجم" reading correctly in RTL.
  /// Every computed number on an Arabic screen passes through here, so it is
  /// also where the digit preference is applied.
  ///
  /// What the isolate holds, and what it does not (measured, and pinned in
  /// iso_direction_test):
  ///  * One number is kept whole, and the Arabic around it cannot move it.
  ///  * Several Arabic-Indic numbers in one isolate still take the bidi
  ///    rules for Arabic numbers. Joined by a lone "/", ":", "." or ",", no
  ///    spaces ("١/٩", "٢.٠"), they read left to right. Joined by anything
  ///    else (spaces, " / ", "-", "·") they read right to left, the first
  ///    number on the right. So the macros' "٣٤ / ١٤٨ جم" is read consumed
  ///    first, as meant, but a date or a version comes out backwards
  ///    ("٢٠٢٦-٠٨-١٣" with the day first), and a code needs marks of its own
  ///    (WhySheet.inOrder).
  ///  * With Western digits chosen, the numbers are a Latin run and read
  ///    left to right: "34 / 148", consumed first in that order too.
  String iso(String x) => '\u2066${digits(x)}\u2069';

  /// Thousands separators so 2,500 looks like a score, not a calorie leftover.
  /// Formatted in English and re-drawn, because intl's 'ar' data does not
  /// reliably use Eastern digits across versions; the Arabic thousands mark
  /// (٬) goes with the Eastern digits.
  String formatSu(int n) {
    final western = NumberFormat.decimalPattern('en').format(n);
    if (!isAr || !easternDigits) return western;
    return digits(western).replaceAll(',', '٬');
  }

  // ---- nudges: the loop's trigger -------------------------------------
  //
  // Two questions a day at this person's meal times, in Qamar's voice, and
  // only for the first fourteen days on the phone. The person can lower the
  // count to zero and never raise it above two. Permission is asked once,
  // after the plan is on screen, with the reason stated (see PlanScreen).
  // In the app the same question is the orb's slow pulse; holding it hears it.

  int nudgesPerDay = NudgeSchedule.maxPerDay;

  /// The OS said yes. False until asked, and false if the person refused.
  bool nudgesAllowed = false;

  /// The Plan-screen card has been answered, one way or the other.
  bool nudgePromptDone = false;

  /// The first day this phone or this account knew the app, whichever is
  /// earlier (see [_takeFirstDay]); the push window counts from here.
  DateTime? firstDay;

  /// Moves [firstDay] earlier, never later, and remembers it on the phone.
  /// True when it moved.
  bool _takeFirstDay(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final current = firstDay;
    if (current != null && !day.isBefore(current)) return false;
    firstDay = day;
    _prefs?.setString(_kFirstDay, day.toIso8601String()).catchError((_) {});
    return true;
  }

  /// When this person eats. Typical hours until their own logs say otherwise.
  MealTimes mealTimes = MealTimes.typical;

  bool get nudgePromptDue => hasPlan && !nudgePromptDone && nudgesPerDay > 0;

  /// Meals eaten today, by slot — the questions the day no longer needs.
  Set<MealSlot> get slotsLoggedToday => {
        for (final m in meals)
          if (m.at != null) slotForHour(m.at!.hour, fasting: fasting),
      };

  /// The question the orb is holding right now, or null.
  Nudge? get waitingNudge => NudgeSchedule.waiting(
        perDay: nudgesPerDay,
        times: nudgeTimes,
        now: _clock(),
        loggedToday: slotsLoggedToday,
        fasting: fasting,
      );

  /// The person said yes on the Plan screen: ask the OS, then schedule.
  Future<void> allowNudges() async {
    _track('nudges_allowed', {'per_day': nudgesPerDay});
    nudgePromptDone = true;
    _prefs?.setBool(_kNudgePromptDone, true).catchError((_) {});
    _notify();
    final granted = await (_nudger?.requestPermission() ?? Future.value(false));
    if (_disposed) return;
    nudgesAllowed = granted;
    _prefs?.setBool(_kNudgesAllowed, granted).catchError((_) {});
    _notify();
    await _rescheduleNudges();
  }

  /// "No, thanks" is zero a day, not a nag later.
  void declineNudges() {
    _track('nudges_declined');
    nudgePromptDone = true;
    nudgesPerDay = 0;
    _prefs?.setBool(_kNudgePromptDone, true).catchError((_) {});
    _prefs?.setString(_kNudgesPerDay, '0').catchError((_) {});
    _notify();
    _rescheduleNudges();
  }

  /// 0, 1 or 2. Anything higher is two: the ceiling is the blueprint's, not
  /// the person's to raise. Turning them back on from zero asks the OS if it
  /// never said yes.
  Future<void> setNudgesPerDay(int n) async {
    nudgesPerDay = n.clamp(0, NudgeSchedule.maxPerDay);
    _prefs?.setString(_kNudgesPerDay, '$nudgesPerDay').catchError((_) {});
    if (nudgesPerDay > 0 && !nudgesAllowed) {
      nudgePromptDone = true;
      _prefs?.setBool(_kNudgePromptDone, true).catchError((_) {});
      final granted = await (_nudger?.requestPermission() ?? Future.value(false));
      if (_disposed) return;
      nudgesAllowed = granted;
      _prefs?.setBool(_kNudgesAllowed, granted).catchError((_) {});
    }
    _notify();
    await _rescheduleNudges();
  }

  /// Rebuilds the phone's schedule from the day as it is now. Called when
  /// anything it depends on changes: a meal logged, the allowance, the
  /// language, the learned meal times, the first load.
  Future<void> _rescheduleNudges() async {
    final n = _nudger;
    if (n == null) return;
    try {
      if (!nudgesAllowed) {
        await n.replaceAll(const [], ar: isAr);
        return;
      }
      // The whole rest of the fourteen-day window, each day decided on its
      // own: the phone fires only what is already scheduled, so this is what
      // someone who stops opening the app still hears.
      final list = <Nudge>[
        if (nudgesPerDay > 0)
          ...NudgeSchedule.build(
            perDay: nudgesPerDay,
            times: nudgeTimes,
            now: _clock(),
            loggedToday: slotsLoggedToday,
            firstDay: firstDay,
            fasting: fasting,
            fastingOn: _fastingOn,
            timesOn: _nudgeTimesOn,
          ),
      ];
      // The free week's one reminder, 48 hours before it ends. It is not a
      // meal question, so the person's zero-a-day does not silence it; the
      // OS permission does.
      final trial = NudgeSchedule.trialReminder(trialEnd: plusIsTrial ? plusUntil : null, now: _clock());
      if (trial != null) list.add(trial);
      // The paid month's, the same way and for the same reason: nothing
      // renews on its own, so this is the only word a member gets.
      final renewal = NudgeSchedule.membershipReminder(periodEnd: plusActive && !plusIsTrial ? plusUntil : null, now: _clock());
      if (renewal != null) list.add(renewal);
      await n.replaceAll(list, ar: isAr);
    } catch (_) {
      // A schedule that could not be written is a missing nudge, not an error
      // the person needs to see.
    }
  }

  void _watchNudger() {
    final n = _nudger;
    if (n == null) return;
    _nudgeSub = n.taps.listen((p) {
      if (!_disposed) _onNudgeTap(p);
    });
    n.takeLaunchPayload().then((p) {
      if (p != null && !_disposed) _onNudgeTap(p);
    }).catchError((_) {});
  }

  /// A tapped question opens the conversation with that question and
  /// listens — voice is the default input, and the meal is what they say.
  void _onNudgeTap(String payload) {
    if (payload == Nudge.trialPayload) {
      _track('trial_reminder_tapped');
      go(AppScreen.subscription);
      return;
    }
    if (payload == Nudge.membershipPayload) {
      _track('membership_reminder_tapped');
      go(AppScreen.subscription);
      return;
    }
    if (!payload.startsWith('nudge:')) return;
    final slot = MealSlot.values.asNameMap()[payload.substring(6)] ?? MealSlot.lunch;
    _nudgeTappedAt = _clock();
    _track('nudge_tapped', {'slot': slot.name});
    _collapseTree();
    if (_logUnderWay) {
      // A log already under way is picked up where it was, with its start.
      openChat();
      return;
    }
    _logStart = _logStartNow();
    _askNudgeQuestion(Nudge(slot: slot, at: _clock(), dayIndex: 0));
    openChat();
    _armMealLog();
    proposalInput = 'voice';
    tapOrbListen();
  }

  /// The meal question already asked in this conversation, by day and meal.
  /// Each is asked once: held again after the talk has moved past it, the
  /// orb opens the conversation, not a log.
  ({DateTime day, MealSlot slot})? _askedQuestion;

  ({DateTime day, MealSlot slot}) _questionKey(Nudge n) {
    final now = _clock();
    return (day: DateTime(now.year, now.month, now.day), slot: n.slot);
  }

  /// Whether the orb pulses: a meal's question is waiting and holding the orb
  /// would ask it. Each question is asked once per conversation; once the
  /// talk has moved past it, the hold opens the conversation instead, so the
  /// pulse stops rather than promise a question the hold will not ask. After
  /// the fortnight of pushes the pulse is the only prompt left, and a pulse
  /// that leads nowhere teaches people to ignore it.
  bool get orbSpeaking {
    final n = waitingNudge;
    if (n == null) return false;
    return _askedQuestion != _questionKey(n) || _asking(n);
  }

  /// Whether Qamar's last line is this meal question.
  bool _asking(Nudge n) => chat.isNotEmpty && chat.last.who == ChatWho.q && chat.last.text == n.text(ar: isAr);

  /// Qamar asks the meal question as its newest line — on a fresh thread or
  /// after whatever was said before — unless it already is the last one. A
  /// meal log is only ever armed on a question the person can see.
  void _askNudgeQuestion(Nudge n) {
    _askedQuestion = _questionKey(n);
    if (_asking(n)) return;
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: n.text(ar: isAr),
      sub: isAr ? 'صوّرها أو قول لي.' : 'Photograph it or tell me.',
    ));
  }

  // ---- the three gestures, taught by doing -----------------------------

  /// Gestures this phone has seen the person make on the orb. The Today
  /// screen shows a three-line card until all three are ticked (or the card
  /// is dismissed); ticks come from the real gestures, never from a tap on
  /// "next".
  final Set<OrbGesture> gesturesLearned = {};
  bool orbTutorialDismissed = false;

  bool get orbTutorialDone => orbTutorialDismissed || gesturesLearned.length == OrbGesture.values.length;

  // ---- the hold, named where it is done (O1) --------------------------------
  //
  // Hold is the one gesture people have to learn, and it is the logging path.
  // The tutorial card on Today stays until the first hold; if the tree has
  // been opened and closed twice with no hold, a one-time mark above the orb
  // names it, in the card's words (HoldCopy).

  /// Times an open tree closed while the hold was still unlearned.
  int treeClosesWithoutHold = 0;

  /// The mark has been dismissed, or made unnecessary by a hold. Remembered
  /// on the phone: it is one-time.
  bool holdCoachSeen = false;

  /// The three-gesture card keeps Today's slot until the first hold.
  bool get holdTutorialDue => !orbTutorialDone && !gesturesLearned.contains(OrbGesture.hold);

  bool get holdCoachDue =>
      !holdCoachSeen &&
      !gesturesLearned.contains(OrbGesture.hold) &&
      treeClosesWithoutHold >= 2 &&
      screen == AppScreen.today &&
      !treeOpen &&
      !chatOpen;

  void dismissHoldCoach() {
    holdCoachSeen = true;
    _prefs?.setBool(_kHoldCoachSeen, true).catchError((_) {});
    _track('hold_coach_dismissed');
    _notify();
  }

  void _learn(OrbGesture g) {
    if (g == OrbGesture.hold && !holdCoachSeen) {
      // Learned by doing: the mark is no longer needed, now or ever.
      holdCoachSeen = true;
      _prefs?.setBool(_kHoldCoachSeen, true).catchError((_) {});
    }
    // Recorded whether or not the tutorial card is still showing, and kept
    // across launches: Me's ticks and the tree's "tap the moon" line read it.
    if (gesturesLearned.contains(g)) return;
    gesturesLearned.add(g);
    _prefs?.setString(_kOrbGestures, gesturesLearned.map((x) => x.name).join(',')).catchError((_) {});
    _track('orb_gesture_first', {'gesture': g.name});
    if (gesturesLearned.length == OrbGesture.values.length) {
      _prefs?.setBool(_kOrbTutorialDone, true).catchError((_) {});
    }
    _notify();
  }

  void dismissOrbTutorial() {
    orbTutorialDismissed = true;
    _notify();
    _prefs?.setBool(_kOrbTutorialDone, true).catchError((_) {});
  }

  void setLang(AppLang l) {
    lang = l;
    _notify();
    _rescheduleNudges();
  }

  void restart() {
    screen = AppScreen.welcome;
    consultationPaused = false;
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
    plusIsEarned = false;
    earnedMonth = EarnedMonth.none;
    earnedMonthJustGranted = false;
    adherenceShare = false;
    proClients = const [];
    plusUntil = null;
    plusTrialEligible = false;
    plusIsTrial = false;
    plusNotice = null;
    plusPlan = PlusPlan.monthly;
    plusPromoCode = '';
    plusQuote = null;
    plusFirstPurchase = true;
    affiliateWallet = AffiliateWallet.empty;
    affiliateNotice = null;
    proName = null;
    proNotice = null;
    _prefs?.setString(_kProName, '').catchError((_) {});
    if (improve) setImprove(false).ignore();
    // Whatever was waiting for an answer belonged to the session that ended,
    // and so did what the welcome has already counted.
    _held.clear();
    _welcomeTracked.clear();
    _startRecorded = false;
    revealDish = null;
    revealDishFacts = null;
    quest = null;
    _questSkippedDay = null;
    _questReadAt = null;
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    // The conversation is gone, and every log begun in it with it.
    _proposalStart = null;
    _abandonLog();
    _askedQuestion = null;
    lastMealPhotoPath = null;
    chatPhotoPath = null;
    scanned = false;
    scanReading = false;
    suAvailable = 0;
    suLifetime = 0;
    aiQuota = AiQuota.empty;
    photoQuota = AiQuota.emptyPhoto;
    redeemed.clear();
    ledgerExtra.clear();
    serverLedger.clear();
    dayHistory.clear();
    weightHistory.clear();
    serverStreak = null;
    walletTab = WalletTab.spend;
    whyOpen = false;
    _notify();
  }

  void go(AppScreen s) {
    screen = s;
    _collapseTree();
    _notify();
    _screen(s);
  }

  // ---- welcome / scan -------------------------------------------------

  void openScan() {
    scanPhotoPath = null;
    scanProblem = null;
    screen = AppScreen.scan;
    scanReading = false;
    _notify();
    // The report is the other way into the consultation, so it is a Start too.
    _recordStart('scan');
    ensureDishFacts();
  }

  bool _startRecorded = false;

  /// Pressing Start — the chat or the report — is the denominator of intake
  /// completion ("users who reach the plan reveal / users who press Start").
  /// It is written to the account at the tap, before any answer, because the
  /// first question is where people leave: a denominator that began at the
  /// first saved answer began after that. Once per session here; the server
  /// keeps the first one ever.
  void _recordStart(String via) {
    _track('intake_started', {'via': via});
    if (_startRecorded) return;
    _startRecorded = true;
    if (isBacked && _profileRepo != null) {
      _push('record start', (uid) => _profileRepo.recordIntakeStart(uid, via: via));
    }
  }

  void backToWelcome() {
    screen = AppScreen.welcome;
    scanReading = false;
    _notify();
  }

  void startOnboarding() {
    if (consultationPaused) {
      // Left part-way with the back control: carry on where it was.
      consultationPaused = false;
      screen = AppScreen.onboard;
      _notify();
      _screen(AppScreen.onboard);
      return;
    }
    consultationPaused = false;
    screen = AppScreen.onboard;
    step = 0;
    msgs.clear();
    scanned = false;
    _notify();
    _screen(AppScreen.onboard);
    _recordStart('chat');
    ensureDishFacts();
    // No beat before the first question: it is on screen with its chips from
    // the first frame, so the conversation never opens empty.
    askStep(0);
  }

  /// Absolute path of the photo the user just took of their InBody report,
  /// once the camera returns one. Null while the screen is still a preview.
  String? scanPhotoPath;

  /// Set when the camera could not be opened at all (no camera, permission
  /// refused, unsupported platform) so the screen can say so, with the way
  /// on, instead of looking broken (O10).
  Problem? scanProblem;

  void setScanPhoto(String? path) {
    scanPhotoPath = path;
    scanProblem = null;
    _notify();
  }

  void setScanProblem(Problem? problem) {
    scanProblem = problem;
    _notify();
  }

  // ---- the camera, when it will not open (O10) ------------------------------

  /// Whether this phone can be taken straight to Qamar's page in Settings.
  bool get canOpenAppSettings => settings_link.canOpenAppSettings;

  void openAppSettings() {
    _track('app_settings_opened', const {});
    _openSettings().catchError((_) => false);
  }

  /// The camera would not open for [e]. Said plainly, never as the
  /// exception, with [instead] — the way on that keeps what the person was
  /// doing. A refused camera is a permission, not an error: on an iPhone it
  /// also offers Settings, and elsewhere it says where to allow it.
  Problem cameraProblem(Object e, {required ProblemAction instead}) {
    final refused = e is PlatformException && (e.code == 'camera_access_denied' || e.code == 'camera_access_restricted');
    if (!refused) {
      return Problem(
        what: isAr ? 'الكاميرا مفتحتش.' : 'The camera didn’t open.',
        why: isAr ? 'قمر مقدرش يستخدم كاميرا الموبايل ده.' : 'Qamar couldn’t use this phone’s camera.',
        action: instead,
      );
    }
    final settings = canOpenAppSettings ? ProblemAction(isAr ? 'افتح الإعدادات' : 'Open Settings', openAppSettings) : null;
    return Problem(
      what: isAr ? 'الكاميرا مقفولة لقمر.' : 'The camera is off for Qamar.',
      why: settings != null
          ? (isAr ? 'افتحها من الإعدادات، أو كمّل من غيرها.' : 'Allow it in Settings, or carry on without it.')
          : (isAr ? 'اسمح لقمر بالكاميرا من إعدادات الموبايل، أو كمّل من غيرها.' : 'Allow the camera for Qamar in your phone’s Settings, or carry on without it.'),
      action: settings ?? instead,
      secondary: settings == null ? null : instead,
      kind: ProblemKind.permission,
    );
  }

  /// A problem in the tree, shown in place of the ring: Photo was chosen and
  /// the camera would not open. Closing the tree clears it.
  Problem? treeProblem;

  /// Photo was chosen in the tree and the camera would not open: the tree
  /// says so, and "Type it instead" keeps the meal being logged.
  void cameraFailedInTree(Object e) {
    treeProblem = cameraProblem(e, instead: ProblemAction(isAr ? 'اكتبها بدل كده' : 'Type it instead', () => quickLog(QuickLog.text)));
    _track('camera_failed', {'where': 'tree', 'refused': treeProblem!.kind == ProblemKind.permission});
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
    scanProblem = null;
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
    consultationPaused = false;
    screen = AppScreen.onboard;
    step = 0;
    msgs.clear();
    // When the report could not be read, say why before asking — otherwise the
    // user has photographed something and been silently ignored.
    if (!scanned && read.note != null && read.note!.isNotEmpty) {
      msgs.add(ObMessage.q(ar: read.note!, en: read.note!));
    }
    _notify();
    askStep(0);
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
    if (step < kOnboardingSteps.length) _track('intake_step', {'step': kOnboardingSteps[step].id});
    step += 1;
    _notify();
    // Persist once per answered step rather than on every stepper notch, so a
    // half-finished onboarding survives the app being closed without turning
    // each wheel tick into a request.
    if (isBacked) _saveProfile();
    askStep(step);
  }

  /// The step whose question is on screen. An input renders only once its
  /// own question has been asked (see [questionShown]).
  int? _askedStep;

  /// The current step's question has been asked and Qamar is not mid-reply:
  /// the chips, wheels and buttons for it may show. Never before.
  bool get questionShown => _askedStep == step && !typing;

  void askStep(int i) {
    if (i >= kOnboardingSteps.length) {
      _askedStep = null;
      generalGuidance ? _finishGeneralGuidance() : calcTarget();
      return;
    }
    final st = kOnboardingSteps[i];
    // On the general-guidance route the target's own questions are not asked.
    if (generalGuidance && kGeneralGuidanceSkips.contains(st.id)) {
      step = i + 1;
      askStep(step);
      return;
    }
    if (i == 0) {
      _pushQ(st.ask(true, general: generalGuidance), st.ask(false, general: generalGuidance));
      _askedStep = 0;
      _notify();
      return;
    }
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
      _askedStep = i;
      _pushQ(st.ask(true, general: generalGuidance), st.ask(false, general: generalGuidance));
    });
  }

  /// A safety answer rules out a calorie target and a plan: those are for a
  /// qualified professional. It does not rule out Qamar — the person still
  /// logs what they eat, sees what is in it, and asks general questions.
  bool get generalGuidance => profile.safety != SafetyAnswer.none;

  /// What the Plan screen says on the general-guidance route, in place of a
  /// plan and a button that could only be refused.
  String get generalGuidancePlanNote => isAr
      ? 'الخطة بتتبني على هدف سعرات، وقمر مش بيحط هدف في حالتك — ده للأخصائي. تقدر تسجل أكلك وتعرف فيه إيه، وتسأل أي سؤال عام.'
      : 'A plan is built around a calorie target, and Qamar doesn’t set one in your case — that’s for a professional. You can still log what you eat, see what’s in it, and ask anything general.';

  /// The safety answer, from a chip or from free text. Anything but "none"
  /// says why there will be no target, and the conversation goes on without
  /// the target's questions — the date of birth (the 18+ gate) is still asked.
  void _answerSafety(SafetyAnswer answer, {String? ar, String? en}) {
    profile = profile.copyWith(safety: answer);
    _notify();
    void next() {
      if (answer != SafetyAnswer.none) {
        _pushQ(
          'شكراً إنك قلتلي. في الحالة دي مش هحسبلك هدف سعرات ولا خطة — الأنسب متابعة مع أخصائي. بس قمر معاك: تعرف إيه اللي في أكلك وتسأل أي سؤال عام. كام سؤال كمان وندخل.',
          'Thank you for telling me. In this case I won’t calculate a calorie target or a plan — a qualified professional is the right route. Qamar is still with you: see what’s in your meals and ask anything general. A few more questions and we’re in.',
        );
      }
      advance();
    }
    if (ar != null && en != null) {
      answerStep(ar, en, next);
    } else {
      next();
    }
  }

  /// The end of the conversation on the general-guidance route: no target
  /// card, and a plain way in.
  void _finishGeneralGuidance() {
    typing = true;
    _notify();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (_disposed) return;
      typing = false;
      msgs.addAll([
        const ObMessage.q(
          ar: 'كده خلصنا. مفيش هدف سعرات في حالتك — ده للأخصائي. جوه التطبيق: سجّل أكلك وأنا أقولك فيه إيه، واسألني أي سؤال عام.',
          en: 'That’s everything. There’s no calorie target in your case — that’s for a professional. Inside: log what you eat and I’ll tell you what’s in it, and ask me anything general.',
        ),
        const ObMessage.save(),
      ]);
      _track('intake_completed', {'route': 'general_guidance'});
      _credit(SuEconomy.onboarding, ar: 'إكمال التهيئة', en: 'Onboarding completed');
      _notify();
      if (isBacked && _walletRepo != null) {
        _push('onboarding bonus', (uid) async {
          await _walletRepo.grantOnboarding(uid);
          await _refreshWallet(uid);
          _notify();
        });
      }
      if (isBacked) _saveProfile();
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
    if (st.id == 'consent') {
      // Three different answers, not one "next": the optional yes turns
      // analytics on, the required-only answer is a recorded no, and "tell
      // me more" is a question — it gets an answer and the chips stay.
      switch (o.value) {
        case 'more':
          answerStep(o.ar, o.en, _explainConsent);
        case 'yes_improve':
          answerStep(o.ar, o.en, () {
            setImprove(true).ignore();
            advance();
          });
        default:
          answerStep(o.ar, o.en, () {
            setImprove(false).ignore();
            advance();
          });
      }
      return;
    }
    if (st.id == 'safety') {
      _answerSafety(SafetyAnswer.fromValue(o.value), ar: o.ar, en: o.en);
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
    // An answer never comes before its question (O7): while Qamar is still
    // typing the next question, what was typed waits in the box.
    if (currentStep != null && !questionShown) return;
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

  /// "Tell me more" at the consent question: what each choice covers, in
  /// plain words, and then the same two choices again. It never advances.
  void _explainConsent() => qamarSay(
        'باختصار: بحسبلك هدف سعرات تقريبي وأقترح أكل مصري في حدوده، ومش بشخّص ولا بوصف علاج — وده اللي لازم أعالج بياناتك عشانه. التحسين اختيار منفصل: لو وافقت، بنشوف إزاي التطبيق بيتستخدم (أنهي خطوات وأنهي زراير)، من غير أكلك ولا وزنك ولا اسمك، وتقدر تقفله من «حسابي» في أي وقت. اختار من تحت.',
        'In short: I estimate a calorie target and suggest Egyptian meals inside it; I don’t diagnose or prescribe — that is what your data is processed for. Helping improve Qamar is separate: if you agree, we see how the app is used (which steps, which buttons), never your food, your weight or your name, and you can turn it off in Me at any time. Pick one below.',
      );

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
          setImprove(true).ignore();
          advance();
          return;
        }
        // A plain "yes" agrees to what is required; the optional part needs
        // its own clear yes, so this is recorded as a no to it.
        if (has(['موافق', 'اوافق', 'أوافق', 'تمام', 'ماشي', 'اكيد', 'أكيد', 'يلا', 'agree', 'yes', 'ok', 'sure', 'fine'])) {
          setImprove(false).ignore();
          advance();
          return;
        }
        if (has(['اعرف', 'أعرف', 'ليه', 'معلومات', 'more', 'why', 'tell'])) {
          _explainConsent();
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
        if (has(['حامل', 'حمل', 'pregnan'])) {
          _answerSafety(SafetyAnswer.pregnant);
          return;
        }
        if (has(['رضاعة', 'برضع', 'برضّع', 'مرضعة', 'breastfeed', 'nursing'])) {
          _answerSafety(SafetyAnswer.breastfeeding);
          return;
        }
        if (has(['مزمن', 'سكر', 'ضغط', 'قلب', 'كلى', 'chronic', 'diabet', 'blood pressure', 'kidney', 'heart'])) {
          _answerSafety(SafetyAnswer.chronic);
          return;
        }
        if (has(['ولا واحدة', 'مفيش', 'لا', 'none', 'no', 'nope'])) {
          _answerSafety(SafetyAnswer.none);
          return;
        }
        unclear();
        return;
    }
  }

  // ---- the first moment of value (O5) --------------------------------------
  //
  // Before the calorie card, one real Egyptian dish for the next meal: picked
  // against the new target, the goal and the exclusions, costed as a share of
  // the day, and labelled as an estimate. The numbers are the food graph's —
  // live when the account is backed and the graph answers, shipped with the
  // app otherwise (models/dishes.dart).

  /// The dish shown at the reveal, its numbers and the meal it is for.
  EgyptianDish? revealDish;
  DishFacts? revealDishFacts;
  MealSlot revealSlot = MealSlot.lunch;

  /// The live graph's per-100 g numbers for the shipped dishes' parts, once
  /// fetched. Empty offline, and whenever the graph has not answered.
  final Map<String, Per100> _liveDishFacts = {};
  bool _dishFactsAsked = false;

  /// Asks the graph for the dishes' numbers, once, so the reveal can prefer
  /// them. Safe to call often; a failure leaves the shipped numbers in place.
  Future<void> ensureDishFacts() async {
    final repo = _mealRepo;
    final uid = _userId;
    if (_dishFactsAsked || repo == null || uid == null) return;
    _dishFactsAsked = true;
    try {
      _liveDishFacts.addAll(await repo.graphPer100({for (final d in kEgyptianDishes) ...d.slugs}));
    } catch (_) {
      // The shipped numbers stand.
    }
  }

  /// Any shipped dish's numbers, the live graph's when it has answered for
  /// every part (O5): the welcome's dishes read the same numbers as the
  /// reveal.
  DishFacts dishFactsFor(EgyptianDish dish) => dish.facts(live: _liveDishFacts);

  /// The welcome's dishes are open: ask the graph for their numbers, once.
  /// Only the dishes' slugs are sent, nothing about the person.
  void openWelcomeDishes() {
    // Once a session, and a dish once each: these come before Start, and the
    // pre-consent buffer keeps only the earliest 50, so a burst of taps must
    // never push intake_started out of it.
    if (_welcomeTracked.add('opened')) _track('welcome_dishes_opened');
    ensureDishFacts().then((_) => _notify());
  }

  /// Welcome events already tracked this session: 'opened' and dish ids.
  final Set<String> _welcomeTracked = {};

  /// A dish chosen on the welcome, before any question (O5). The event names
  /// no food, as at the reveal.
  void welcomeDishShown(EgyptianDish dish) {
    if (!_welcomeTracked.add('dish:${dish.id}')) return;
    _track('dish_shown', {'placement': 'welcome', 'live': dishFactsFor(dish).live});
  }

  EgyptianDish? _pickRevealDish() {
    final slot = slotForHour(_clock().hour, fasting: fasting);
    final dish = pickDish(
      targetKcal: target().kcal,
      goal: profile.goal,
      exclusions: profile.prefs,
      slot: slot,
      live: _liveDishFacts,
    );
    revealSlot = slot;
    revealDish = dish;
    revealDishFacts = dish?.facts(live: _liveDishFacts);
    return dish;
  }

  void calcTarget() {
    typing = true;
    _notify();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (_disposed) return;
      if (_pickRevealDish() == null) {
        _revealTarget();
        return;
      }
      // The dish first; Qamar goes on typing towards the numbers.
      msgs.addAll(const [
        ObMessage.q(
          ar: 'قبل الأرقام، حاجة تاكلها — من الأكل المصري، على قد اللي قلته:',
          en: 'Before the numbers, something to eat — Egyptian food, sized to what you told me:',
        ),
        ObMessage.dish(),
      ]);
      _track('dish_shown', {'placement': 'intake', 'live': revealDishFacts!.live});
      _notify();
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!_disposed) _revealTarget();
      });
    });
  }

  void _revealTarget() {
    typing = false;
    msgs.addAll([
      // Only what can be changed afterwards is said to be changeable: what to
      // avoid, in Me (saveAvoid). The target's own answers cannot be, yet.
      const ObMessage.q(
        ar: 'حسبتلك الهدف على أساس اللي قلته. دي تقديرات. واللي بتتجنبه في الأكل تقدر تغيّره من «حسابي» في أي وقت.',
        en: 'I calculated your target from what you told me. These are estimates. What you avoid in food can be changed in Me at any time.',
      ),
      const ObMessage.target(),
      const ObMessage.save(),
    ]);
    _track('intake_completed', {'route': 'target'});
    _offerTrialAfterReveal();
    // Shown at once; paid by the server (qamar_grant_onboarding, once per
    // account), and the wallet is re-read so the two numbers agree.
    _credit(SuEconomy.onboarding, ar: 'إكمال التهيئة', en: 'Onboarding completed');
    _notify();
    if (isBacked && _walletRepo != null) {
      _push('onboarding bonus', (uid) async {
        await _walletRepo.grantOnboarding(uid);
        await _refreshWallet(uid);
        _notify();
      });
    }

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
  }

  void dismissSave() {
    msgs.removeWhere((m) => m.kind == ObKind.save);
    _notify();
  }

  /// "Link account" on the save card: the account sheet opens, to link one
  /// now. The card has done its job either way; Me keeps the same link.
  void linkFromSaveCard() {
    _track('save_link_opened');
    openLinkAccount();
    dismissSave();
  }

  // ---- what to avoid, after the consultation (gap 4) ----------------------
  //
  // The consultation asks once what Qamar must never suggest. A new allergy,
  // or meat given up, has to be recordable afterwards, or every plan keeps
  // suggesting it: Me asks the same question, with the same choices. What is
  // chosen is the account's, which the dish picker, the conversation and
  // every plan read.

  /// The consultation's own question and choices for what to avoid.
  static OnboardingStep get avoidStep => kOnboardingSteps.firstWhere((s) => s.id == 'food');

  /// What the last change said, shown on Me; null before one.
  String? avoidNotice;
  bool avoidBusy = false;

  static const _kPlanStaleDays = 'plan_stale_days';

  /// Days whose plan may have been written before something new was to be
  /// avoided: today's, and tomorrow's, which the night job may already have
  /// written. The next writing of such a day's plan is a new one. Kept on
  /// the phone, so a restart does not bring the old plan back.
  final Set<String> _planStaleDays = {};

  void _savePlanStaleDays() => _prefs?.setString(_kPlanStaleDays, _planStaleDays.join(',')).catchError((_) {});

  /// Saves [chosen] as what to avoid. The account's copy is saved first: if
  /// that fails, nothing changes, and the notice says so. Anything newly
  /// avoided also rewrites a plan already written for today.
  Future<bool> saveAvoid(Iterable<String> chosen) async {
    final picked = chosen.toSet();
    final next = [
      for (final o in avoidStep.options)
        if (o.value != 'none' && picked.contains(o.value)) o.value as String,
    ];
    final before = profile.prefs;
    final added = [for (final v in next) if (!before.contains(v)) v];
    final removed = [for (final v in before) if (!next.contains(v)) v];
    if (added.isEmpty && removed.isEmpty) {
      avoidNotice = isAr ? 'مفيش حاجة اتغيرت.' : 'Nothing changed.';
      _notify();
      return true;
    }
    final updated = profile.copyWith(prefs: next);
    final repo = _profileRepo;
    final uid = _userId;
    if (isBacked && repo != null && uid != null) {
      avoidBusy = true;
      avoidNotice = null;
      _notify();
      try {
        await repo.saveProfile(uid, updated);
      } catch (_) {
        if (_disposed) return false;
        avoidBusy = false;
        avoidNotice = isAr
            ? 'مقدرتش أحفظ دلوقتي، فمفيش حاجة اتغيرت. جرّب تاني وانت متوصل.'
            : 'I couldn’t save that just now, so nothing changed. Try again with a connection.';
        _notify();
        return false;
      }
      if (_disposed) return true;
    }
    profile = profile.copyWith(prefs: next);
    // Counts only: what someone avoids can be health data.
    _track('avoid_updated', {'added': added.length, 'removed': removed.length});
    var planLine = '';
    if (added.isNotEmpty && !generalGuidance) {
      final today = _today();
      _planStaleDays
        ..add(today)
        ..add(Days.add(DateTime.now(), 1).toIso8601String().substring(0, 10));
      _savePlanStaleDays();
      if (hasPlan && planDate == today) {
        await ensurePlan(force: true);
        if (_disposed) return true;
        planLine = !_planStaleDays.contains(today)
            ? (isAr ? ' وخطة النهارده اتكتبت من جديد على كده.' : ' Today’s plan has been written again to match.')
            : (isAr
                ? ' خطة النهارده اتكتبت قبل التغيير ومقدرتش أكتبها تاني دلوقتي، فراجعها قبل ما تطبخ.'
                : ' Today’s plan was written before this and couldn’t be written again just now, so check it before you cook.');
      }
    }
    avoidBusy = false;
    avoidNotice = added.isNotEmpty
        ? (isAr ? 'اتحفظ. الاقتراحات والخطط هتمشي على كده من دلوقتي.$planLine' : 'Saved. Suggestions and plans follow this from now on.$planLine')
        : (isAr ? 'اتحفظ.' : 'Saved.');
    _notify();
    return true;
  }

  // ---- the free week, offered after the reveal (O12) ------------------------
  //
  // The blueprint's 7:30: after the plan reveal, never before it, the trial
  // as a gift with its rules stated — "7 days of the full Qamar. No card,
  // nothing renews." — Start or Not now. Not now leaves it waiting in Me.
  // Offered only where it can actually start: a backed account, billing
  // configured, and a trial the server says is still unused. Never while an
  // invitation code or a nutritionist's code waits to be redeemed: the
  // account's one trial is that code's fortnight, and Start would spend it on
  // seven days.

  /// The trial the reveal can offer: never used, not already on Qamar+, and
  /// no invitation or nutritionist's code waiting to bring its own fortnight.
  bool get trialWaiting => plusTrialEligible && !plusActive && !invitationWaiting && !proCodeWaiting;

  /// The offer's length, as the organic trial the server starts (0043).
  static const trialOfferDays = 7;

  bool get _canOfferTrial => trialWaiting && isBacked && hasBilling;

  void _offerTrialAfterReveal() {
    if (!_canOfferTrial) return;
    msgs.add(const ObMessage.trialOffer());
    _track('trial_offer_shown', {'placement': 'onboarding'});
  }

  Future<void> acceptTrialOffer() async {
    msgs.removeWhere((m) => m.kind == ObKind.trialOffer);
    _notify();
    await startPlusTrial(placement: 'onboarding');
    if (_disposed) return;
    _pushQ(
      plusIsTrial
          ? 'أسبوعك مع قمر كامل بدأ. من غير بطاقة، ومفيش حاجة بتتجدد لوحدها — هقولك قبل ما يخلص بيومين.'
          : 'مقدرتش أبدأ الأسبوع المجاني دلوقتي. مستنيك في «حسابي» وقت ما تحب.',
      plusIsTrial
          ? 'Your week of the full Qamar has started. No card, and nothing renews on its own — I’ll tell you two days before it ends.'
          : 'I couldn’t start the free week just now. It waits for you in Me whenever you want it.',
    );
  }

  void declineTrialOffer() {
    msgs.removeWhere((m) => m.kind == ObKind.trialOffer);
    _track('trial_offer_declined', {'placement': 'onboarding'});
    // The price appears once in the consultation, here, as the blueprint
    // places it — against a nutritionist, not against apps. "About one
    // visit", not "less than one": a visit costs EGP 350–800 and a video
    // consultation starts at 300, so 500 is in their range, not below it.
    final price = displayPlusQuote.listPounds;
    _pushQ(
      'موجود في «حسابي» وقت ما تحب. وبعده، قمر+ بـ${formatEgp(price, ar: true, eastern: easternDigits)} في الشهر — في حدود تمن كشف واحد عند أخصائي تغذية.',
      'It’s waiting in Me whenever you want it. After it, Qamar+ is ${formatEgp(price, ar: false)} a month — about one nutritionist visit.',
    );
  }

  // ---- the free week, offered once more on the lock card (O12) --------------
  //
  // Not now leaves the week waiting in Me. The first time the night's plan is
  // locked on Today — the blueprint's fourth wall, where the person can see
  // the sentence about tomorrow and not the plan behind it — the link under
  // it offers the week once more, for that day only. After that day it is the
  // wall's own link again, and the week still waits in Me.

  static const _kLockOfferDay = 'trial_lock_offer_day';

  /// The Cairo day the lock card offered the week, or null before it has.
  String? _lockOfferDay;

  /// The lock card carries the week today: the plan behind the night note is
  /// locked, the week can actually start, and the card has not offered it on
  /// an earlier day.
  bool get lockCardTrialOffer =>
      nightPlanLocked &&
      (nightNote?.planKcal ?? 0) > 0 &&
      _canOfferTrial &&
      (_lockOfferDay == null || _lockOfferDay == _dayKey());

  /// Called once the lock card has been drawn with the offer on it: the day
  /// is kept, so the offer is the first locked card's only, and it is counted
  /// once.
  void recordLockCardOffer() {
    if (!lockCardTrialOffer || _lockOfferDay != null) return;
    _lockOfferDay = _dayKey();
    _prefs?.setString(_kLockOfferDay, _lockOfferDay!).catchError((_) {});
    _track('trial_offer_shown', {'placement': 'lock_card'});
  }

  /// Start pressed on the lock card: the week begins, and the plan it opened
  /// is shown.
  Future<void> acceptLockCardTrial() async {
    await startPlusTrial(placement: 'lock_card');
    if (_disposed) return;
    if (plusIsTrial) go(AppScreen.plan);
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
    _track('water_logged', {'unit': unit.name});
    if (!isBacked) return;
    final repo = _waterRepo;
    if (repo == null) return;
    _pushDurable(
      PendingWrite(kind: PendingKind.water, payload: sip.toJson(), at: _clock()),
      (uid) async {
        final id = await repo.addSip(uid, sip);
        final i = waterToday.indexOf(sip);
        if (i >= 0) {
          waterToday[i] = sip.copyWith(id: id);
          _notify();
        }
      },
      // A glass earns on the server (half rate on Lite, first eight a day).
      after: (uid) async {
        await _refreshWallet(uid);
        _notify();
      },
    );
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

  /// Where in [chat] the meal question the next message answers sits. What
  /// is said or typed next is read as a meal only while that question is
  /// still Qamar's last line, so nothing is read as a meal unless a meal
  /// question is on screen. Every way into a log asks its question and arms
  /// this; the next message, or an abandoned log, disarms it.
  int? _mealAskAt;

  bool get _loggingMeal => _mealAskAt != null && _mealAskAt == chat.length - 1;

  /// Whether what is typed or said next is a meal to log, not a question: the
  /// composer then shows a meal, not "Ask Qamar…", since a meal read spends no
  /// question.
  bool get loggingMeal => _loggingMeal;

  /// Arms the log on the question just put on screen.
  void _armMealLog() => _mealAskAt = chat.length - 1;

  /// The start of the log whose reading is up for confirmation. A reading
  /// takes its log's start with it when it begins ([_analyseMeal]), so
  /// closing the conversation mid-read, or starting another log before this
  /// one is confirmed, cannot change what started this one.
  ({String prompt, bool orbWaiting})? _proposalStart;

  /// Meal readings still on their way.
  int _mealReads = 0;

  /// A log already under way: a reading to confirm, or one still being read.
  bool get _logUnderWay => proposal != null || _mealReads > 0;

  /// A log the conversation closed on, with nothing still coming: it is
  /// disarmed, and the next one captures its own start.
  void _abandonLog() {
    _logStart = null;
    _mealAskAt = null;
  }

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
    // A log that was abandoned leaves no start behind for the next one.
    _proposalStart = null;
    _logStart = null;
    discardPhoto(lastMealPhotoPath);
    lastMealPhotoPath = null;
    _notify();
  }

  /// Asks the assistant to read a meal, and puts the answer up for
  /// confirmation. Never writes anything by itself.
  Future<void> _analyseMeal({required String inputType, String? text, String? imagePath}) async {
    final gateway = _ai;
    proposalInput = inputType;
    proposalRaw = text;
    // The reading belongs to the log that began it and takes that log's
    // start with it: a conversation closed while it runs, or another log
    // begun before it is confirmed, leaves this one's start as it was.
    final start = _takeLogStart();

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
      _track('meal_read_failed', {'source': inputType, 'reason': 'offline'});
      return;
    }

    chatState = ChatState.thinking;
    _notify();
    // The verdict's latency, as the person feels it: from asking to seeing.
    final verdict = Stopwatch()..start();
    _mealReads++;
    try {
      final result = await gateway.analyzeMeal(
        inputType: inputType,
        text: text,
        imagePath: imagePath,
        lang: lang.code,
      );
      if (_disposed) return;
      final ms = verdict.elapsedMilliseconds;
      await _pullQuota(gateway);
      chatState = ChatState.idle;
      _track('meal_read', {'source': inputType, 'items': result.items.length, 'ms': ms});

      if (result.items.isEmpty) {
        // An empty reading is a real answer — a name the graph does not carry,
        // or a photo too dark to trust. Saying so beats inventing a plate.
        // For words, the app's own line: it knows whether today's photos are
        // left, and the gateway's note for this case says a photo needs
        // Qamar+, which the free tier's three a day make untrue.
        final text = inputType == 'photo'
            ? (result.note ??
                (isAr
                    ? 'مقدرتش أقرأ الوجبة من الصورة دي. جرّب صورة أوضح، أو احكيلي أكلت إيه.'
                    : 'I could not read this meal. Try a clearer photo, or tell me what you ate.'))
            : notFoundReply;
        chat.add(ChatTurn(who: ChatWho.q, text: text));
        proposal = null;
        proposalQty = [];
      } else {
        proposal = result;
        _proposalStart = start;
        proposalQty = List.filled(result.items.length, 1);
        chat.add(ChatTurn(
          who: ChatWho.q,
          text: isAr ? 'شايف كده. ظبّط الكميات وأكّد.' : 'Here is what I see. Adjust the amounts and confirm.',
          sub: result.note,
        ));
      }
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      _track('meal_read_failed', {'source': inputType, 'reason': 'quota'});
      _onQuotaHit(e, mealLog: true);
    } catch (e) {
      if (_disposed) return;
      _track('meal_read_failed', {'source': inputType, 'reason': 'error'});
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'مقدرتش أوصل للمساعد عشان أقرأ الوجبة. جرّب تاني بعد شوية.'
            : 'I could not reach the assistant to read the meal. Try again in a moment.',
        sub: _failedWhy(e),
      ));
    } finally {
      _mealReads--;
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
    // What started this log, as its reading took it when it began.
    final start = _proposalStart ?? _logStartNow();
    _proposalStart = null;
    final meal = LoggedMeal(
      name: name,
      sub: sub,
      kcal: totals.kcal,
      p: totals.p,
      c: totals.c,
      f: totals.f,
      at: _clock(),
      prompt: start.prompt,
      orbWaiting: start.orbWaiting,
    );
    final drafted = items.map((it) => (def: it.def, qty: it.q)).toList();
    final raw = proposalRaw;

    final first = meals.isEmpty;
    meals.add(meal);
    final award = first ? SuEconomy.firstMeal : SuEconomy.mealLogged;
    _credit(award, ar: first ? 'أول وجبة' : 'تأكيد وجبة', en: first ? 'First meal logged' : 'Meal confirmed');
    _track('meal_logged', {
      'source': proposalInput,
      'first': first,
      'items': items.length,
      'nudged': start.prompt == LogPrompt.push,
      'prompt': start.prompt,
      'orb_waiting': start.orbWaiting,
    });
    _nudgeTappedAt = null;
    chat.add(ChatTurn(
      who: ChatWho.q,
      // What this meal does to the day, in words that change with the day
      // (O3). Under it, the meal's own receipt ("Logged by voice ·
      // estimate"). The points are the wallet's to show, not Qamar's to say:
      // the credit shows only as the orb's passing receipt (O9).
      text: replyFor(meal, dayNumbers(), ar: isAr, iso: iso),
      sub: meal.sub,
    ));
    proposal = null;
    proposalQty = [];
    proposalRaw = null;
    // The verdict is in and acted on; the picture has no further use here.
    discardPhoto(lastMealPhotoPath);
    lastMealPhotoPath = null;
    _notify();
    _rescheduleNudges();

    // The schema keeps the draft the user confirmed as well as the log, so a
    // correction stays traceable back to what was proposed.
    if (isBacked) {
      final repo = _mealRepo!;
      final input = proposalInput;
      _pushDurable(
        PendingWrite(
          kind: PendingKind.meal,
          payload: {
            'meal': meal.toJson(),
            'items': [for (final it in drafted) {'def': it.def.toJson(), 'qty': it.qty}],
            'input': input,
            'raw': raw,
          },
          at: _clock(),
        ),
        (uid) async {
          final draftId = await repo.saveDraft(
            uid,
            MealAnalysisDraft(inputType: input, items: drafted, rawText: raw),
          );
          await repo.confirmMeal(uid, draftId: draftId, meal: meal, items: drafted);
        },
        after: (uid) async {
          await _refreshStreak(uid);
          // The insert earned points on the server; show the server's number.
          await _refreshWallet(uid);
          _notify();
        },
      );
    }
  }

  // ---- quest / wallet -------------------------------------------------

  /// Today's quest, as the server chose it from what the day lacks (O2), or
  /// null: offline, before the server has answered, or on a day with no real
  /// gap. The server pays it from the meal or glass that satisfies it; the
  /// phone never credits it and has nothing to tap that would.
  DayQuest? quest;

  /// The day the person put the quest away ("not today"), so it is gone at
  /// once, before the server has been told.
  String? _questSkippedDay;

  DateTime? _questReadAt;

  /// Today on the app's clock, as a key.
  String _dayKey() => _clock().toIso8601String().substring(0, 10);

  /// Whether the quest wants Today's slot: a real one, not put away, not
  /// past its time, not on a fasting day or the general-guidance route, and
  /// only while the score is shown.
  bool get questDue {
    final q = quest;
    // No quest on a fasting day (0063): it would pay for eating in daylight.
    // None on the general-guidance route either (0068): a quest reads the
    // day against a target and a plan, and there is deliberately neither.
    if (q == null || !showScore || fasting || generalGuidance || _questSkippedDay == _dayKey()) return false;
    return q.done || q.expiresAt.isAfter(_clock());
  }

  Future<void> _refreshQuest(String uid) async {
    final repo = _walletRepo;
    if (repo == null) return;
    try {
      final q = await repo.todayQuest(uid);
      if (_disposed) return;
      quest = q;
      _questReadAt = _clock();
    } catch (_) {
      // The card stays as it last was; the server still pays what is met.
    }
  }

  /// Reads today's quest again when Today is shown: the one held may have
  /// expired (the next gap is then chosen), or the day may have turned. At
  /// most every ten minutes otherwise.
  Future<void> refreshQuest() async {
    final uid = _userId;
    if (!isBacked || uid == null) return;
    final read = _questReadAt;
    final q = quest;
    final stale = read == null ||
        _clock().difference(read) > const Duration(minutes: 10) ||
        (q != null && !q.done && !q.expiresAt.isAfter(_clock())) ||
        DateTime(read.year, read.month, read.day) != DateTime(_clock().year, _clock().month, _clock().day);
    if (!stale) return;
    await _refreshQuest(uid);
    _notify();
  }

  /// "Not today": the quest is put away until tomorrow. Nothing is paid.
  void skipQuest() {
    if (quest == null) return;
    _questSkippedDay = _dayKey();
    _track('quest_skipped', {'kind': quest!.kind.wire});
    _notify();
    final repo = _walletRepo;
    if (isBacked && repo != null) {
      _push('skip quest', (uid) => repo.skipQuest(uid));
    }
  }

  void openWallet() {
    screen = AppScreen.wallet;
    _collapseTree();
    _notify();
    _screen(AppScreen.wallet);
  }

  // ---- Qamar+ subscription --------------------------------------------

  /// The plan the paywall sells. There is one; nothing is charged until
  /// Paymob confirms.
  PlusPlan plusPlan = PlusPlan.monthly;

  /// Entitlement. In production this is set only from a Paymob-verified
  /// payment — never decided on the client (spec_mvp.txt §29.1). Here it is
  /// local so the subscribed state is demoable.
  bool plusActive = false;
  DateTime? plusUntil;

  /// The free week: offered once, before any payment. [plusIsTrial] while
  /// it is the reason Qamar+ is on.
  bool plusTrialEligible = false;
  bool plusIsTrial = false;

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

  // ---- invitations (the referral loop) ----------------------------------
  //
  // Blueprint: a member earns three named invitations a quarter and sends
  // one from Me; the friend gets a fortnight of Qamar+ and the sender's name
  // from the first moment; when the friend pays month one, the sender gets
  // 1,000 Su and the friend 2,000 — all on the server (0049). Scarce and
  // numbered so the loop runs on the sender's standing, never on a discount.

  InvitationBook invitations = InvitationBook.empty;
  String? invitationNotice;
  bool invitationBusy = false;

  /// Whoever invited this person, once their code is accepted.
  String? invitedBy;

  int get invitationsLeft => invitations.left;

  // ---- Ramadan mode ---------------------------------------------------
  //
  // Blueprint: "Ramadan mode free for everyone → suhoor and iftar plans,
  // hydration windows → 30-day Ramadan log: 500 points → Eid report: what
  // changed in 30 days → keep the plan going? standard price." The mode
  // shows itself a week before the first fast (a seventh node on the tree)
  // and stays a week after Eid for the report. The switch lives on the
  // profile so the server's night job writes a fasting day.

  /// The season in view. The built-in estimate until the server, which
  /// carries the operator's post-sighting correction, answers.
  Season season = Season.ramadan1448;

  /// Which season the "fasting this year?" question was answered for.
  String? ramadanAskedFor;

  SeasonPhase get seasonPhase => season.phase(_clock());

  bool get seasonVisible => seasonPhase != SeasonPhase.none;

  bool get fasting => profile.fasting == FastingMode.ramadan && seasonPhase == SeasonPhase.during;

  /// The question is asked once per season, on Today, while it is coming
  /// or on.
  bool get fastingPromptDue =>
      (seasonPhase == SeasonPhase.before || seasonPhase == SeasonPhase.during) && ramadanAskedFor != season.key;

  Future<void> _refreshSeason() async {
    try {
      final s = await _profileRepo?.currentSeason();
      if (s != null) season = s;
    } catch (_) {
      // The estimate stands.
    }
  }

  /// The person's answer to "fasting this Ramadan?", now or from the
  /// seventh node later. Turning it on rewrites today's plan as iftar and
  /// suhoor and moves the questions to those hours. A rewrite that cannot
  /// happen now (the plan's daily cap, no connection) leaves the plan from
  /// before on screen, and says so: on the Plan screen above it, and where
  /// the answer was given ([fastingNotYet]).
  Future<void> setFasting(bool on) async {
    ramadanAskedFor = season.key;
    _prefs?.setString(_kRamadanAsked, season.key).catchError((_) {});
    final mode = on ? FastingMode.ramadan : FastingMode.none;
    final changed = profile.fasting != mode;
    profile = profile.copyWith(fasting: mode);
    _notify();
    _track('fasting_set', {'on': on, 'season': season.key});
    if (isBacked && _profileRepo != null) {
      _push('save fasting', (uid) => _profileRepo.saveFastingMode(uid, mode));
    }
    _rescheduleNudges();
    // A plan asked for today is a different day now: rewrite it.
    if (changed && planDate != null) {
      if (_planMissed != null && hasPlan) {
        // The last answer could not rewrite the plan, so the plan on screen
        // was written for this one: nothing to rewrite, nothing to say.
        _planMissed = null;
        planProblem = null;
        _notify();
        return;
      }
      // Until a plan is written for the answer, a refusal says so (see
      // [_notYetLine]).
      _planMissed = mode;
      await ensurePlan(force: true);
    }
  }

  /// The answer to "fasting?" that the plan on screen was not rewritten
  /// for: set while a switch waits on its rewrite, cleared when a plan is
  /// written.
  FastingMode? _planMissed;

  /// A refusal's first line while the plan on screen is from before a
  /// fasting switch; null otherwise. "Today's plan", not "the plan below":
  /// it is also said on Today, on the Ramadan screen and in the
  /// conversation, where no plan is below it.
  String? get _notYetLine {
    if (_planMissed == null || !hasPlan) return null;
    return _planMissed == FastingMode.ramadan
        ? (isAr ? 'خطة النهارده لسه مش خطة الصيام.' : 'Today’s plan isn’t your fasting plan yet.')
        : (isAr ? 'خطة النهارده لسه خطة الصيام.' : 'Today’s plan is still your fasting plan.');
  }

  /// A refused rewrite, said first as what it left undone when the plan on
  /// screen is from before a fasting switch: then why, with the same way on
  /// the refusal offered. Any other refusal is returned as it is.
  Problem _behindFasting(Problem refused) {
    final notYet = _notYetLine;
    if (notYet == null) return refused;
    if (refused.kind == ProblemKind.limit) return _planWall(refused.what, notYet: notYet);
    return Problem(
      what: notYet,
      why: [refused.what, if (refused.why != null) refused.why!].join(' '),
      action: refused.action,
      secondary: refused.secondary,
      kind: refused.kind,
    );
  }

  /// The same refusal where the answer was given (Today's slot, the Ramadan
  /// screen): one line, and the Plan card's way on. A way on that is only
  /// the way back to Today does nothing from there, so the line says when
  /// instead. Null unless the plan on screen is from before a fasting
  /// switch and its card is up.
  ({String line, ProblemAction? action})? get fastingNotYet {
    final p = planProblem;
    final line = _notYetLine;
    if (p == null || line == null) return null;
    if (!p.action.wayBack) return (line: line, action: p.action);
    final when = p.kind == ProblemKind.limit ? (isAr ? 'تقدر تتكتب تاني من بكرة.' : 'It can be written again from tomorrow.') : null;
    return (line: when == null ? line : '$line $when', action: null);
  }

  void dismissFastingPrompt() {
    ramadanAskedFor = season.key;
    _prefs?.setString(_kRamadanAsked, season.key).catchError((_) {});
    _notify();
  }

  /// Iftar (sunset) and suhoor's end (dawn) for today, on the phone's clock.
  int get iftarMinutes => SunTimes.sunset(_clock());
  int get fajrMinutes => SunTimes.fajr(_clock());

  HydrationWindows get hydrationWindows => HydrationWindows(iftarMin: iftarMinutes, fajrMin: fajrMinutes);

  /// Meal times for the questions: the sun's on a fasting day, the learned
  /// ones otherwise. Suhoor's question comes an hour before dawn, when the
  /// meal is on the table.
  MealTimes get nudgeTimes => _nudgeTimesOn(_clock());

  /// A fasting day is a day of the season's month with the switch on. Asked
  /// per day because the phone's schedule runs two weeks ahead, and the
  /// first or last fast can fall inside it.
  bool _fastingOn(DateTime day) => profile.fasting == FastingMode.ramadan && season.phase(day) == SeasonPhase.during;

  /// That day's question times: that day's sun while fasting, the learned
  /// meal times otherwise.
  MealTimes _nudgeTimesOn(DateTime day) => _fastingOn(day)
      ? mealTimes.withRamadan(iftar: SunTimes.sunset(day), suhoor: (SunTimes.fajr(day) - 60).clamp(0, 24 * 60 - 1))
      : mealTimes;

  /// Days of the month with a meal logged, from the history already loaded.
  int get seasonDaysLogged {
    final byDay = <String, DayTotals>{};
    for (final d in dayHistory) {
      byDay[d.day.toIso8601String().substring(0, 10)] = d;
    }
    final todayKey = _clock().toIso8601String().substring(0, 10);
    if (meals.isNotEmpty) byDay[todayKey] = DayTotals(day: _clock(), kcal: consumed().kcal, meals: meals.length);
    return byDay.values.where((d) {
      final day = DateTime(d.day.year, d.day.month, d.day.day);
      return d.meals > 0 && !day.isBefore(season.startsOn) && !day.isAfter(season.endsOn);
    }).length;
  }

  EidReport eidReport() => EidReport.build(
        season: season,
        history: dayHistory,
        weights: weightHistory,
        targetKcal: target().kcal,
        iso: iso,
      );

  Future<void> shareEidReport() async {
    final s = _sharer;
    if (s == null) return;
    await s.shareText(eidReport().text(ar: isAr, site: QamarConfig.site));
    _track('eid_report_shared');
  }

  Future<void> _refreshInvitations(String uid) async {
    final repo = _invitationRepo;
    if (repo == null) return;
    try {
      invitations = await repo.mine(uid);
    } catch (_) {
      // The card shows what it last knew.
    }
  }

  /// Issues the next numbered invitation to [name] and hands the message to
  /// the share sheet. Every refusal is a sentence on the card, never a crash.
  Future<void> issueInvitation(String name) async {
    invitationNotice = null;
    final repo = _invitationRepo;
    final uid = _userId;
    if (!plusActive) {
      invitationNotice = isAr ? 'الدعوات لأعضاء قمر+.' : 'Invitations are for Qamar+ members.';
      _notify();
      return;
    }
    if (repo == null || uid == null) {
      invitationNotice = isAr ? 'اربط حسابك الأول عشان تبعت دعوات.' : 'Link your account first to send invitations.';
      _notify();
      return;
    }
    final n = name.trim();
    if (n.isEmpty) {
      invitationNotice = isAr ? 'الدعوة بتحمل اسم. اكتب اسم صاحبك.' : 'An invitation carries a name. Write your friend’s name.';
      _notify();
      return;
    }
    if (invitationsLeft <= 0) {
      invitationNotice = isAr
          ? 'خلصت دعوات الربع ده. التلاتة الجايين مع الربع الجاي.'
          : 'This quarter’s invitations are used. The next three come with the next quarter.';
      _notify();
      return;
    }
    invitationBusy = true;
    _notify();
    try {
      final inv = await repo.issue(uid, name: n);
      invitations = invitations.plus(inv);
      _track('invitation_sent', {'number': inv.number});
      await shareInvitation(inv);
    } catch (e) {
      invitationNotice = e is InvitationException
          ? e.message
          : (isAr ? 'مقدرتش أعمل الدعوة دلوقتي. جرّب تاني بعد شوية.' : 'Could not create the invitation just now. Try again in a moment.');
    }
    invitationBusy = false;
    _notify();
  }

  /// The message, to the sheet: the friend's name, the sender's, the code,
  /// the link.
  Future<void> shareInvitation(Invitation inv) async {
    final s = _sharer;
    if (s == null) return;
    await s.shareText(inv.message(
      ar: isAr,
      sender: profile.name,
      senderGets: suAmount(SuEconomy.invitationSender),
      friendGets: suAmount(SuEconomy.invitationFriend),
    ));
  }

  /// The friend's side: a code typed on the welcome screen. The sender's
  /// name is the first thing they see, and the fortnight starts if a trial
  /// is still open to them.
  // ---- invitation links ---------------------------------------------------------
  //
  // The shared message carries dr-qamar.com/i/<code>; the app also answers
  // qamar://i/<code>. Opened before there is an account, the code waits on
  // the phone and is redeemed the moment the app is connected.

  static const _kPendingInvite = 'pending_invitation';

  /// A code that arrived by link before the account existed.
  String? pendingInvitationCode;

  /// An invitation code is waiting on this phone to be redeemed. While it
  /// waits, the free week is not offered: starting it would spend the one
  /// trial an account gets, and with it the invitation's fortnight and the
  /// inviter's credit.
  bool get invitationWaiting => pendingInvitationCode?.trim().isNotEmpty ?? false;

  Future<void> acceptInvitationLink(String code) async {
    final c = code.trim();
    if (c.isEmpty) return;
    _track('invitation_link_opened');
    // The code waits on the phone until the server has answered it.
    pendingInvitationCode = c;
    _prefs?.setString(_kPendingInvite, c).catchError((_) {});
    if (isBacked && _invitationRepo != null) {
      await _redeemPendingInvitation();
      return;
    }
    invitationNotice = isAr ? 'وصلتك دعوة. هتتفعّل أول ما تدخل.' : 'You have an invitation. It is redeemed the moment you are in.';
    _notify();
  }

  /// Redeems the waiting code. It is cleared only once the server has
  /// answered it — redeemed, or refused (a code that is not there, already
  /// used, or the person's own can never succeed). A redeem that could not
  /// reach the server keeps it, and the next connected start tries again.
  Future<void> _redeemPendingInvitation() async {
    var code = pendingInvitationCode;
    if (code == null || code.trim().isEmpty) {
      try {
        code = await _prefs?.getString(_kPendingInvite);
      } catch (_) {
        code = null;
      }
    }
    if (code == null || code.trim().isEmpty || _invitationRepo == null) return;
    pendingInvitationCode = code.trim();
    final answered = await redeemInvitation(code);
    if (_disposed) return;
    if (!answered) {
      invitationNotice = isAr
          ? 'مقدرتش أفعّل الدعوة دلوقتي. هي محفوظة على الموبايل، وهجرّب تاني أول ما تفتح التطبيق وانت متوصل.'
          : 'I could not redeem your invitation just now. It is kept on this phone, and I will try again the next time you open the app with a connection.';
      _notify();
      return;
    }
    pendingInvitationCode = null;
    _prefs?.setString(_kPendingInvite, '').catchError((_) {});
    _notify();
  }

  /// Redeems [code]. True once the server has answered it — redeemed, or
  /// refused — and false when it could not be asked, so a waiting code can
  /// be kept for another try.
  Future<bool> redeemInvitation(String code) async {
    invitationNotice = null;
    final repo = _invitationRepo;
    final uid = _userId;
    if (code.trim().isEmpty) return false;
    if (repo == null || uid == null) {
      invitationNotice = isAr
          ? 'الدعوة بتتفعّل لما التطبيق يبقى متوصل بحسابك.'
          : 'An invitation is redeemed once the app is connected to your account.';
      _notify();
      return false;
    }
    invitationBusy = true;
    _notify();
    var answered = false;
    try {
      final r = await repo.redeem(uid, code: code.trim());
      answered = true;
      invitedBy = r.inviterName.trim().isEmpty ? null : r.inviterName.trim();
      final who = invitedBy ?? (isAr ? 'صاحبك' : 'A friend');
      invitationNotice = r.trialDays > 0
          ? (isAr
              ? '$who عزمك. ${Counted.day.of(r.trialDays, ar: true, iso: iso)} قمر+ عليك من دلوقتي.'
              : '$who invited you. ${Counted.day.of(r.trialDays, ar: false, iso: iso)} of Qamar+ ${r.trialDays == 1 ? 'is' : 'are'} yours from now.')
          : (isAr ? '$who عزمك. أهلاً بيك.' : '$who invited you. Welcome.');
      _track('invitation_redeemed', {'trial_days': r.trialDays});
      await _refreshPlus();
    } catch (e) {
      answered = answered || (e is InvitationException && e.refused);
      invitationNotice = e is InvitationException
          ? e.message
          : (isAr ? 'مقدرتش أفعّل الدعوة دلوقتي. جرّب تاني بعد شوية.' : 'Could not redeem the invitation just now. Try again in a moment.');
    }
    invitationBusy = false;
    _notify();
    return answered;
  }

  // ---- a nutritionist's code (O12) -------------------------------------------
  //
  // The blueprint's referred client: "Pro code → client installs, 14-day
  // trial". A code arrives by link (qamar://p/<code>, dr-qamar.com/p/<code>)
  // or is typed in Me. The server (qamar_redeem_pro_code, 0069) puts the
  // professional on the account, so their share attaches to the first payment
  // with no code typed at checkout, and starts the fortnight while the
  // account's one trial is unused — only for a code the operator has
  // confirmed as a professional's. It waits on the phone exactly as an
  // invitation does: cleared only once the server has answered it, and while
  // it waits the seven-day week is not offered, because Start would spend the
  // one trial that the code's fortnight is.

  static const _kPendingProCode = 'pending_pro_code';
  static const _kProName = 'pro_code_name';

  /// A nutritionist's code waiting on this phone to be redeemed.
  String? pendingProCode;

  bool get proCodeWaiting => pendingProCode?.trim().isNotEmpty ?? false;

  /// The professional whose code is on this account, as the server named
  /// them; null until a code has been redeemed here.
  String? proName;

  String? proNotice;
  bool proBusy = false;

  /// A code from a link. Kept on the phone until the server has answered it.
  Future<void> acceptProLink(String code) => _takeProCode(code, via: 'link');

  /// A code typed in Me. The same path as a link.
  Future<void> enterProCode(String code) => _takeProCode(code, via: 'typed');

  Future<void> _takeProCode(String code, {required String via}) async {
    final c = PlusPricing.normalizeCode(code);
    if (c.isEmpty) return;
    _track('pro_code_received', {'via': via});
    pendingProCode = c;
    _prefs?.setString(_kPendingProCode, c).catchError((_) {});
    if (isBacked && _invitationRepo != null) {
      await _redeemPendingProCode();
      return;
    }
    proNotice = isAr
        ? 'الكود محفوظ على الموبايل، وهيتفعّل أول ما التطبيق يتوصل بحسابك.'
        : 'The code is kept on this phone, and is used the moment the app is connected to your account.';
    _notify();
  }

  Future<void> _redeemPendingProCode() async {
    var code = pendingProCode;
    if (code == null || code.trim().isEmpty) {
      try {
        code = await _prefs?.getString(_kPendingProCode);
      } catch (_) {
        code = null;
      }
    }
    if (code == null || code.trim().isEmpty || _invitationRepo == null) return;
    pendingProCode = code.trim();
    final answered = await redeemProCode(code);
    if (_disposed) return;
    if (!answered) {
      proNotice = isAr
          ? 'مقدرتش أستخدم الكود دلوقتي. هو محفوظ على الموبايل، وهجرّب تاني أول ما تفتح التطبيق وانت متوصل.'
          : 'I could not use the code just now. It is kept on this phone, and I will try again the next time you open the app with a connection.';
      _notify();
      return;
    }
    pendingProCode = null;
    _prefs?.setString(_kPendingProCode, '').catchError((_) {});
    _notify();
  }

  /// The server's refusals, in the person's language. Each is final for the
  /// code (0069), so the waiting code is cleared on any of them.
  String _proRefusal(String serverMessage) {
    switch (serverMessage) {
      case 'no nutritionist with that code':
        return isAr ? 'مفيش أخصائي بالكود ده. اتأكد من الحروف.' : 'No nutritionist has that code. Check the letters.';
      case 'that is your own code':
        return isAr ? 'ده الكود بتاعك إنت.' : 'That is your own code.';
      case "that code is not a nutritionist's":
        return isAr
            ? 'الكود ده مش لأخصائي. لو صاحبك اللي اداهولك، اكتبه لما تشترك.'
            : 'That code is not a nutritionist’s. If a friend gave it to you, enter it when you subscribe.';
      case "another nutritionist's code is already on this account":
        return isAr
            ? 'فيه كود أخصائي تاني على حسابك. لو عايز تغيّره، كلّم الدعم.'
            : 'Another nutritionist’s code is already on your account. To change it, write to support.';
      default:
        return isAr ? 'مقدرتش أستخدم الكود ده.' : 'I could not use that code.';
    }
  }

  /// Redeems [code]. True once the server has answered it — redeemed, or
  /// refused — and false when it could not be asked, so a waiting code is
  /// kept for another try.
  Future<bool> redeemProCode(String code) async {
    proNotice = null;
    final repo = _invitationRepo;
    final uid = _userId;
    if (code.trim().isEmpty) return false;
    if (repo == null || uid == null) {
      proNotice = isAr
          ? 'الكود بيتفعّل لما التطبيق يبقى متوصل بحسابك.'
          : 'A nutritionist’s code is used once the app is connected to your account.';
      _notify();
      return false;
    }
    proBusy = true;
    _notify();
    var answered = false;
    try {
      final r = await repo.redeemPro(uid, code: code.trim());
      answered = true;
      final name = r.professionalName.trim();
      proName = name.isEmpty ? (isAr ? 'أخصائيك' : 'Your nutritionist') : name;
      _prefs?.setString(_kProName, proName!).catchError((_) {});
      proNotice = r.trialDays > 0
          ? (isAr
              ? TrialWords.proRedeemed(proName!, r.trialDays, ar: true, iso: iso)
              : TrialWords.proRedeemed(proName!, r.trialDays, ar: false, iso: iso))
          : (isAr
              ? 'كود $proName على حسابك. لما تشترك، بياخد نصيبه والسعر زي ما هو.'
              : '$proName’s code is on your account. When you subscribe they get their share, at the same price.');
      _track('pro_code_redeemed', {'trial_days': r.trialDays});
      await _refreshPlus();
    } catch (e) {
      final refused = e is InvitationException && e.refused;
      answered = answered || refused;
      proNotice = refused
          ? _proRefusal(e.message)
          : (isAr ? 'مقدرتش أستخدم الكود دلوقتي. جرّب تاني بعد شوية.' : 'I could not use the code just now. Try again in a moment.');
    }
    proBusy = false;
    _notify();
    return answered;
  }
  String? affiliateNotice;

  PlusQuote get displayPlusQuote =>
      plusQuote ??
      PlusPricing.quote(plan: plusPlan.name, firstPurchase: plusFirstPurchase);

  void openSubscription() {
    screen = AppScreen.subscription;
    _collapseTree();
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
    if (plusPromoCode.isNotEmpty) _track('promo_entered');
    _notify();
    refreshPlusQuote();
  }

  Future<void> refreshPlusQuote() async {
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
    if (plusActive && !plusIsTrial) {
      // There is nothing to cancel: a payment only extends the month.
      final until = plusUntil?.toLocal();
      final when = until == null ? '' : '${until.day}/${until.month}';
      plusNotice = isAr
          ? '${until == null ? 'شهرك شغال' : 'شهرك شغال لحد ${iso(when)}'}، ومفيش حاجة بتتجدد لوحدها. لما يخلص، تقدر تدفع الشهر اللي بعده من هنا.'
          : '${until == null ? 'Your month is on' : 'Your month runs until $when'}, and nothing renews on its own. When it ends, you can pay for the next one here.';
      _notify();
      return;
    }
    final billing = _billing;
    if (!isBacked || billing == null) {
      plusNotice = isAr
          ? 'الدفع بالجنيه عن طريق Paymob. اربط حسابك الأول، وبعدين نفتح صفحة الدفع.'
          : 'You pay in EGP through Paymob. Link your account first, then we open its checkout.';
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
      _track('checkout_opened', {'plan': plusPlan.name, 'promo': plusPromoCode.isNotEmpty});
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

  void _absorbEntitlement(PlusEntitlement ent) {
    plusActive = ent.active;
    plusUntil = ent.periodEnd;
    plusFirstPurchase = ent.firstPurchase;
    plusTrialEligible = ent.trialEligible;
    plusIsTrial = ent.isTrial;
    plusIsEarned = ent.isEarned;
    // The free week's reminder is scheduled the moment the trial starts and
    // withdrawn the moment it is over or paid for.
    _rescheduleNudges();
  }

  /// Qamar+ right now is the earned month, running after the paid one lapsed.
  bool plusIsEarned = false;

  /// True in the last 48 hours of the free week: the Today card carries the
  /// question the reminder asked.
  bool get trialEndingSoon {
    final end = plusUntil;
    if (!plusIsTrial || end == null) return false;
    final left = end.difference(_clock());
    return left > Duration.zero && left <= NudgeSchedule.trialLead;
  }

  /// "tomorrow" or "in N hours" until Qamar+ ends — the free week or the
  /// month — for the Today card.
  String trialEndsIn() {
    final end = plusUntil;
    if (end == null) return '';
    final hours = end.difference(_clock()).inHours;
    if (hours >= 24) return isAr ? 'بكرة' : 'tomorrow';
    final h = hours < 1 ? 1 : hours;
    return isAr ? 'خلال ${iso('$h')} ساعة' : 'in $h hour${h == 1 ? '' : 's'}';
  }


  /// True in the last 48 hours of a paid or earned month. Nothing renews on
  /// its own, so this and its push are the only word a member gets.
  bool get membershipEndingSoon {
    final end = plusUntil;
    if (!plusActive || plusIsTrial || end == null) return false;
    final left = end.difference(_clock());
    return left > Duration.zero && left <= NudgeSchedule.trialLead;
  }

  /// Which billing moment Today should carry now, if any: the free week or
  /// the month, in its last 48 hours. They cannot both be true — a trial is
  /// never running alongside a paid month. The Today slot (`todayFocus`)
  /// decides where it sits; this only says whether it is due.
  BillingMoment get billingMoment => trialEndingSoon
      ? BillingMoment.trialEnding
      : membershipEndingSoon
          ? BillingMoment.membershipEnding
          : BillingMoment.none;

  bool get billingMomentDue => billingMoment != BillingMoment.none;

  /// Tapping the billing card: the same place the push goes, counted.
  void openBillingMoment() {
    final m = billingMoment;
    _track('wall_tapped', {'wall': m == BillingMoment.membershipEnding ? 'membership_end' : 'trial_end'});
    go(AppScreen.subscription);
  }

  // ---- the earned month -----------------------------------------------------
  //
  // The blueprint's "earned-month promo (28/30 days), starts day 1", at 20
  // of 30 since 0058 (a reversal, so the rule rewards more than the people
  // who would never leave). The server counts the days, holds the threshold
  // in billing_config and grants the month; the phone reads where things
  // stand, asks for the grant the moment it is due, and shows the progress
  // while it is being earned — always in the server's numbers.

  EarnedMonth earnedMonth = EarnedMonth.none;

  /// The month landed during this session: a card on Today until dismissed.
  bool earnedMonthJustGranted = false;

  void dismissEarnedMonthCard() {
    earnedMonthJustGranted = false;
    _notify();
  }

  Future<void> _refreshEarnedMonth(BillingGateway billing) async {
    if (!isBacked) return;
    try {
      var status = await billing.earnedMonth();
      if (_disposed) return;
      if (status.eligible && !status.claimed) {
        final claim = await billing.claimEarnedMonth();
        if (_disposed) return;
        _absorbEntitlement(claim.entitlement);
        status = claim.earned;
        earnedMonthJustGranted = true;
        _track('earned_month_granted', {'logged_days': status.loggedDays});
        final until = plusUntil?.toLocal();
        final when = until == null ? '' : iso('${until.day}/${until.month}');
        plusNotice = isAr
            ? 'شهر علينا: سجّلت ${Counted.day.of(status.loggedDays, ar: true, iso: iso)} من أول ${iso('${status.windowDays}')}. قمر+ شغال لحد $when.'
            : 'A month on us: you logged ${status.loggedDays} of your first ${Counted.day.of(status.windowDays, ar: false, iso: iso)}. Qamar+ runs until $when.';
      }
      earnedMonth = status;
      _notify();
    } catch (_) {
      // The promo not being readable is not something the person needs told.
    }
  }

  /// Seven days of Qamar+, free, once. The server grants it — the phone only
  /// asks and reads back what it was given.
  Future<void> startPlusTrial({String? placement}) async {
    final billing = _billing;
    if (!isBacked || billing == null) {
      plusNotice = isAr
          ? 'الأسبوع المجاني محتاج حساب مربوط الأول، عشان يبقى مرة واحدة بس.'
          : 'The free week needs a linked account first, so it stays once only.';
      _notify();
      return;
    }
    if (!plusTrialEligible) {
      plusNotice = isAr ? 'الأسبوع المجاني اتستخدم على الحساب ده.' : 'The free week has already been used on this account.';
      _notify();
      return;
    }
    try {
      _absorbEntitlement(await billing.startTrial());
      if (plusActive) _track('trial_started', {if (placement != null) 'placement': placement});
      plusNotice = plusActive
          ? (isAr
              ? TrialWords.started(trialOfferDays, ar: true, iso: iso)
              : TrialWords.started(trialOfferDays, ar: false, iso: iso))
          : (isAr ? 'مقدرتش أبدأ الأسبوع المجاني دلوقتي.' : 'Could not start the free week just now.');
      _notify();
      await _refreshQuota();
    } catch (e) {
      plusTrialEligible = false;
      plusNotice = e is BillingException
          ? e.message
          : (isAr ? 'مقدرتش أبدأ الأسبوع المجاني دلوقتي.' : 'Could not start the free week just now.');
      _notify();
    }
  }

  /// Called when Paymob sends the person back to the app.
  Future<void> onReturnedFromPaymob() async {
    await _refreshPlus(announce: true);
    await _refreshAffiliate();
    if (screen != AppScreen.subscription) go(AppScreen.subscription);
  }

  Future<void> _refreshPlus({bool announce = false}) async {
    final billing = _billing;
    if (billing == null) return;
    try {
      final ent = await billing.entitlement();
      final was = plusActive;
      _absorbEntitlement(ent);
      if (announce && !was && plusActive) _track('plus_activated', {'provider': ent.isTrial ? 'trial' : 'paymob'});
      if (announce) {
        plusNotice = plusActive
            ? (isAr ? 'قمر+ اشتغل. شكراً.' : 'Qamar+ is on. Thank you.')
            : (isAr
                ? 'لسه مفيش دفع متأكد من Paymob. لو خلصت دلوقتي، استنى لحظة وجرّب استرجاع الاشتراك.'
                : 'Paymob has not confirmed a payment yet. If you just finished, wait a moment and tap Restore.');
      }
      _notify();
      await _refreshEarnedMonth(billing);
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
      if (affiliateWallet.code != null) {
        proClients = await billing.affiliateClients();
        _notify();
      }
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

  /// Files a bucket's counters where the screens read them.
  void _absorb(AiQuota q) {
    switch (q.bucket) {
      case 'photo':
        photoQuota = q;
      case 'plan':
        break; // the plan wall speaks through planProblem
      default:
        aiQuota = q;
    }
  }

  void _absorbAll(AiQuotas all) {
    aiQuota = all.chat;
    photoQuota = all.photo;
  }

  /// Today's counters, from the last gateway response or /quota.
  Future<void> _pullQuota(AiGateway gateway) async {
    if (gateway is HttpAiGateway && gateway.lastQuota != null) {
      _absorb(gateway.lastQuota!);
      return;
    }
    try {
      _absorbAll(await gateway.quotaStatus());
    } catch (_) {}
  }

  Future<void> _refreshQuota() async {
    final gateway = _ai;
    if (gateway == null) return;
    try {
      _absorbAll(await gateway.quotaStatus());
      _notify();
    } catch (_) {
      // A missing counter is not worth blocking Today. The next AI call
      // will 429 if they are actually out.
    }
  }

  /// The wall, in the conversation. Each bucket has its own way out and the
  /// button goes there: another photo is bought with Su in the wallet; the
  /// fourth question is Qamar+ first and, once a day when the balance covers
  /// it, that one question for Su (O13).
  ///
  /// Each wall also offers the way that keeps what the person was doing
  /// (O10): a meal photo past the limit can be typed instead, and words
  /// that hit the question limit can be logged as a meal, which never
  /// spends a question. [asked] is what was sent; [mealLog] says the wall
  /// came up while logging a meal.
  void _onQuotaHit(AiQuotaException e, {String? asked, bool mealLog = false}) {
    _track('quota_hit', {'bucket': e.quota.bucket});
    _absorb(e.quota);
    chatState = ChatState.idle;
    final words = asked?.trim() ?? '';
    final offerSu = e.quota.bucket != 'photo' && words.isNotEmpty && suQuestionOffered;
    if (offerSu) _track('question_wall_su_offered', {'price': questionPrice});
    final turn = _wallTurn(e, words: words, mealLog: mealLog, offerSu: offerSu);
    chat.add(turn);
    _questionWall = offerSu ? (turn: turn, e: e, words: words) : null;
    _notify();
  }

  /// The wall's turn in the conversation. Qamar+ comes first, every time
  /// (O13); under it, when [offerSu], this one question for Su; and the way
  /// that keeps what the person was doing ("Log it as a meal", O10).
  /// Whether the wall's person is a member, as the server said when it
  /// metered the use (the quota's plus) — the same answer the gateway's words
  /// were chosen by — and the phone's entitlement only when it did not say.
  /// A payment or a lapse the phone has not read yet cannot make the buttons
  /// disagree with the words.
  bool _memberAtWall(AiQuota q) => q.plus ?? plusActive;

  ChatTurn _wallTurn(AiQuotaException e, {required String words, required bool mealLog, required bool offerSu}) {
    final photo = e.quota.bucket == 'photo';
    // A member at their own question limit is not sold the Qamar+ they have:
    // the way on is the one that keeps what they were doing (O10), and the
    // gateway's words say to ask again in the morning.
    if (!photo && _memberAtWall(e.quota)) {
      final way = words.isEmpty
          ? ProblemAction(isAr ? 'رجوع للنهارده' : 'Back to Today', closeChat)
          : ProblemAction(isAr ? 'سجّلها كوجبة' : 'Log it as a meal', () => logTextAsMeal(words));
      return ChatTurn(
        who: ChatWho.q,
        text: e.message,
        problem: Problem(what: e.message, action: way, kind: ProblemKind.limit),
      );
    }
    // In Arabic the product is قمر+, as the Arabic paywall names it.
    final label = photo ? (isAr ? 'افتح المحفظة' : 'Open the wallet') : (isAr ? 'شوف قمر+' : 'See Qamar+');
    final ProblemAction? instead = photo
        ? (mealLog ? ProblemAction(isAr ? 'اكتبها بدل كده' : 'Type it instead', () => quickLog(QuickLog.text)) : null)
        : (words.isEmpty ? null : ProblemAction(isAr ? 'سجّلها كوجبة' : 'Log it as a meal', () => logTextAsMeal(words)));
    final ProblemAction? su = offerSu ? ProblemAction(suQuestionLabel, () => askWithSu(words)) : null;
    return ChatTurn(
      who: ChatWho.q,
      text: e.message,
      action: label,
      openWallet: photo,
      openPlus: !photo,
      problem: Problem(
        what: e.message,
        action: ProblemAction(label, () => _leaveChatForWall(photo: photo)),
        secondary: su ?? instead,
        also: su == null ? null : instead,
        kind: ProblemKind.limit,
      ),
    );
  }

  // ---- the fourth question, bought with Su (O13) ----------------------------
  //
  // The fourth question meets the Qamar+ wall first, every time. Under it,
  // once a Cairo day and only when the balance covers it, this one question
  // can be bought with Su. The server holds the price (su_economy_config,
  // 0066), the day's allowance and the balance; the phone offers, and asks the
  // question again once the purchase is in.

  /// What one more question costs, as the server last said (0066).
  int questionPrice = SuEconomy.extraQuestion;

  /// The day a question was bought here, so the offer goes at once.
  String? _questionBoughtDay;
  bool _buyingQuestion = false;

  /// The wall that offered the question, to take the offer off it once used.
  ({ChatTurn turn, AiQuotaException e, String words})? _questionWall;

  /// Whether the question wall offers this one question for Su: the free
  /// tier's question limit, not already bought today, the balance covering
  /// the price, and an account on the server that sells it.
  bool get suQuestionOffered =>
      isBacked &&
      _walletRepo != null &&
      !_memberAtWall(aiQuota) &&
      aiQuota.bucket == 'chat' &&
      aiQuota.exhausted &&
      aiQuota.extra == 0 &&
      _questionBoughtDay != _dayKey() &&
      suAvailable >= questionPrice;

  /// The offer's words, with the price the server charges.
  /// "Just this one": the button buys one question, not a membership.
  String get suQuestionLabel => isAr ? 'اسأل السؤال ده بس بـ${suAmount(questionPrice)}' : 'Ask just this one for ${suAmount(questionPrice)}';

  /// After a purchase whose answer was lost: if the server already holds the
  /// bought question, ask it; otherwise buy again with the same day's key,
  /// which the server answers with the first purchase if it happened (0067).
  Future<void> _retryBoughtQuestion(String words) async {
    await _refreshQuota();
    if (_disposed) return;
    if (aiQuota.bucket == 'chat' && aiQuota.extra > 0 && aiQuota.remaining > 0) {
      _questionBoughtDay = _dayKey();
      final uid = _userId;
      if (uid != null) {
        try {
          await _refreshWallet(uid);
        } catch (_) {
          // The balance catches up at the next refresh.
        }
      }
      await sendChatMsg(words, again: true);
      return;
    }
    await askWithSu(words);
  }

  /// Buys this one question with Su, then asks it again. Nothing is spent
  /// unless the server takes it; if it does not, Qamar says so and the wall
  /// stays as it was.
  Future<void> askWithSu(String words) async {
    final repo = _walletRepo;
    final uid = _userId;
    final text = words.trim();
    if (text.isEmpty || repo == null || uid == null || _buyingQuestion || !suQuestionOffered) return;
    _buyingQuestion = true;
    final price = questionPrice;
    chatState = ChatState.thinking;
    _notify();
    try {
      // One key per day: a retry can never buy the day's question twice.
      await repo.redeem(uid, item: kQuestionExtra, idempotencyKey: '${uid}_redeem_chat_extra_${_dayKey()}');
    } catch (e) {
      _buyingQuestion = false;
      if (_disposed) return;
      chatState = ChatState.idle;
      // The redeem function refused (RedeemRefused): its transaction rolled
      // back, so nothing was spent. Anything else — no connection, a
      // timeout, a 5xx — may have come after the purchase committed, so the
      // words say only what is known, and trying again is safe: the same key
      // never charges twice (0067).
      final refused = e is RedeemRefused;
      final what = refused
          ? (isAr ? 'مقدرتش أشتري السؤال، ومفيش ولا نقطة اتصرفت.' : 'I could not buy the question, and no points were spent.')
          : (isAr
              ? 'مقدرتش أتأكد إن السؤال اتشرى. دوس «جرّب تاني»: لو اتشرى هسأله، وعمره ما بيتخصم مرتين.'
              : 'I could not confirm the question was bought. Tap Try again: if it went through I will ask it, and it is never charged twice.');
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: what,
        sub: _failedWhy(e),
        problem: Problem(
          what: what,
          why: _failedWhy(e),
          action: refused
              ? ProblemAction(isAr ? 'شوف قمر+' : 'See Qamar+', () => _leaveChatForWall(photo: false))
              : ProblemAction(isAr ? 'جرّب تاني' : 'Try again', () => _retryBoughtQuestion(text)),
          secondary: ProblemAction(isAr ? 'سجّلها كوجبة' : 'Log it as a meal', () => logTextAsMeal(text)),
          kind: refused || failureOf(e) == Failure.ours ? ProblemKind.error : ProblemKind.offline,
        ),
      ));
      _notify();
      return;
    }
    _buyingQuestion = false;
    if (_disposed) return;
    _track('question_bought', {'price': price});
    _questionBoughtDay = _dayKey();
    suAvailable -= price;
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? kQuestionExtra.nameAr : kQuestionExtra.nameEn, amount: -price, when: isAr ? 'دلوقتي' : 'Just now'));
    aiQuota = aiQuota.withExtra(1);
    // The offer has been taken: the wall keeps Qamar+ and "Log it as a
    // meal", and loses the button that would now do nothing.
    final wall = _questionWall;
    _questionWall = null;
    if (wall != null) {
      final at = chat.indexOf(wall.turn);
      if (at >= 0) chat[at] = _wallTurn(wall.e, words: wall.words, mealLog: false, offerSu: false);
    }
    _notify();
    await sendChatMsg(text, again: true);
  }

  /// A wall's way out from the conversation: the wallet sells another photo;
  /// the fourth question is Qamar+.
  void _leaveChatForWall({required bool photo}) {
    chatOpen = false;
    if (!photo) {
      openSubscription();
      return;
    }
    screen = AppScreen.wallet;
    _notify();
  }

  /// Words that hit the question limit, read as a meal instead (O10). A meal
  /// is read by the meal reader, never the question bucket, so this works
  /// with no questions left.
  Future<void> logTextAsMeal(String text) async {
    final words = text.trim();
    if (words.isEmpty || _logUnderWay) return;
    _logStart = _logStartNow();
    _mealAskAt = null;
    _track('question_logged_as_meal', const {});
    await _analyseMeal(inputType: 'text', text: words);
  }

  /// The camera would not open for a photo in the conversation: Qamar says
  /// so, with [instead] as the way on (choosing a photo that is already on
  /// the phone), and Settings where the phone allows it.
  void cameraFailedInChat(Object e, {required ProblemAction instead}) {
    final p = cameraProblem(e, instead: instead);
    chat.add(ChatTurn(who: ChatWho.q, text: p.what, sub: p.why, problem: p));
    _track('camera_failed', {'where': 'chat', 'refused': p.kind == ProblemKind.permission});
    _notify();
  }

  /// A call that failed, said from the person's side: no connection, too
  /// slow, or us — never the exception itself.
  String _failedWhy(Object e) => switch (failureOf(e)) {
        Failure.offline => isAr ? 'مفيش نت دلوقتي.' : 'You’re offline right now.',
        Failure.slow => isAr ? 'النت بطيء دلوقتي.' : 'The connection is too slow right now.',
        Failure.ours => isAr ? 'المشكلة عندنا، مش منك.' : 'The problem is on our side, not yours.',
      };

  void redeem(SpendItemDef item) {
    final done = item.once && isRedeemed(item.id);
    final afford = suAvailable >= item.price && !done;
    if (!afford) return;
    _track('wallet_redeemed', {'item': item.id});
    suAvailable -= item.price;
    if (item.once) redeemed.add(item.id);
    if (item.grantsAiUses > 0) {
      photoQuota = photoQuota.withExtra(item.grantsAiUses);
    }
    if (item.id == 'streak_freeze') {
      final s = streak();
      serverStreak = s.copyWith(freezesAvailable: s.freezesAvailable + 1);
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

  /// Records points earned, and the reason, at the moment it is earned.
  ///
  /// The balance is still the server's to decide — crediting is server-side
  /// only (see SupabaseWalletRepository.credit) — so this is the local view
  /// until the next hydrate replaces it with the database's.
  void _credit(int amount, {required String ar, required String en}) {
    suAvailable += amount;
    suLifetime += amount;
    ledgerExtra.insert(0, LedgerEntry(label: isAr ? ar : en, amount: amount, when: isAr ? 'دلوقتي' : 'Just now'));
    if (amount > 0) suReceipt = SuReceipt(amount: amount, at: _clock(), seq: (suReceipt?.seq ?? 0) + 1);
  }

  // ---- Su on screen (O9) ----------------------------------------------------
  //
  // One persistent display: Today's header chip, which opens the wallet.
  // Level lives in the wallet only. The orb never shows a balance; when
  // points are credited it shows a passing receipt, a coin and "+١٠٠".

  /// Whether anything on screen keeps score (O4): the "Points and streaks"
  /// switch in Me, on by default and kept on this phone like the digits.
  ///
  /// Off hides everything that counts at the person: Today's Su chip, the
  /// orb's passing receipt, the orb's streak ring, the streak line under the
  /// name, the quest and its coin, Progress's streak card, the streak on the
  /// week card, and Level and lifetime earned in the wallet. Off only hides.
  /// Points are still earned, freezes still apply, the earned month still
  /// counts its days, photos can still be bought, and the wallet still shows
  /// the balance for whoever goes to look. Switching back costs nothing.
  /// Everything that keeps score reads this and nothing else.
  bool showScore = true;

  void setShowScore(bool on) {
    if (showScore == on) return;
    showScore = on;
    _notify();
    _prefs?.setBool(_kShowScore, on).catchError((_) {});
  }

  /// The last credit in this session, for the orb's receipt. Set only by
  /// [_credit]: a balance read from the server is not something earned just
  /// now, so it never makes one.
  SuReceipt? suReceipt;

  /// Su with a number, in words (the naming rule, O9): "100 Su", and in
  /// Arabic the name with the number agreement Arabic needs — "٥ نقاط Su",
  /// "١٠٠ نقطة Su". Where space is tight a coin and the number stand in for
  /// all of it; where only the name is needed it is `t.suName`.
  /// A signed Su number standing alone, where a column of them is the
  /// list (the wallet's History): "+1,000", "-800"; in Arabic "+١٬٠٠٠" and
  /// "-٨٠٠", isolated so the sign stays before the number in a
  /// right-to-left line.
  String suSigned(int n) {
    final text = '${n > 0 ? '+' : ''}${formatSu(n)}';
    return isAr ? iso(text) : text;
  }

  String suAmount(int n, {bool signed = false}) {
    final sign = signed && n > 0 ? '+' : '';
    if (!isAr) return '$sign${formatSu(n)} Su';
    final noun = n.abs() >= 3 && n.abs() <= 10 ? 'نقاط' : 'نقطة';
    return '${iso('$sign${formatSu(n)}')} $noun Su';
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

  /// Turns a Supabase error into something a person can act on. One we do
  /// not recognise is said from the person's side — offline, or a problem on
  /// our side — never as the raw message (O10); the raw text goes to the
  /// debug log, where a misconfigured project is still easy to spot.
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
    debugPrint('auth: $raw');
    return failureOf(e) == Failure.ours
        ? (isAr ? 'حصلت مشكلة عندنا. جرّب تاني بعد شوية.' : 'Something went wrong on our side. Try again in a moment.')
        : (isAr ? 'مفيش نت دلوقتي. جرّب تاني لما يرجع.' : 'You’re offline right now. Try again when you’re back.');
  }

  // ---- progress -------------------------------------------------
  //
  // Everything here is arithmetic over what was actually logged. A day with
  // nothing logged is a zero, not a gap to be filled in, and a week with no
  // data says so instead of drawing a plausible-looking chart.

  /// The last seven days ending today, oldest first. Today's entry always
  /// reflects the meals in memory, so a meal just logged shows immediately
  /// rather than waiting for the next hydrate.
  ///
  /// Stepped by the calendar ([Days]): stepped by 24 hours, the week after
  /// Egypt's clocks change found none of its past days, and in April read
  /// each as the day before.
  List<DayTotals> week() {
    final today = Days.of(_clock());
    final byDay = {for (final d in dayHistory) Days.of(d.day): d};

    final todayTotals = consumed();
    if (meals.isNotEmpty) {
      byDay[today] = DayTotals(day: today, kcal: todayTotals.kcal, meals: meals.length);
    }

    return [
      for (var i = 6; i >= 0; i--) byDay[Days.add(today, -i)] ?? DayTotals(day: Days.add(today, -i), kcal: 0, meals: 0),
    ];
  }

  /// The seven days before [week], oldest first — the comparison the review
  /// card draws. Unlogged days are zeros here too.
  List<DayTotals> lastWeek() {
    final today = Days.of(_clock());
    final byDay = {for (final d in dayHistory) Days.of(d.day): d};
    return [
      for (var i = 13; i >= 7; i--) byDay[Days.add(today, -i)] ?? DayTotals(day: Days.add(today, -i), kcal: 0, meals: 0),
    ];
  }

  /// Days in the last week with anything logged at all.
  int activeDays() => week().where((d) => d.meals > 0).length;

  // ---- the weekly review card ------------------------------------------
  //
  // The only thing in the product designed to be shared. No weight on it,
  // ever; calories only when the person turns numbers on, and that choice is
  // the phone's. The shared card travels with the site link.

  bool reviewShowNumbers = false;

  void setReviewShowNumbers(bool on) {
    reviewShowNumbers = on;
    _notify();
    _prefs?.setBool(_kReviewNumbers, on).catchError((_) {});
  }

  WeekReview weekReview() => WeekReview.build(
        week: week(),
        lastWeek: lastWeek(),
        targetKcal: target().kcal,
        hasTarget: !generalGuidance,
        streak: streak(),
        iso: iso,
      );

  // ---- the week card on Today (O15) -------------------------------------
  //
  // Friday, the Egyptian weekend, is review day: once three days of the week
  // are logged, Today's slot carries the week's one line the person did not
  // expect, with the way to the whole card on Progress. Opened, it leaves
  // the slot for the day, and that is remembered across a restart.

  String? _weekCardSeenDay;

  /// Whether the week card wants Today's slot.
  bool get weekCardDue => _clock().weekday == DateTime.friday && _weekCardSeenDay != _dayKey() && weekReview().enough;

  /// "See the week": the whole card, on Progress.
  void openWeekCard() {
    _weekCardSeenDay = _dayKey();
    // Kept on the phone: a restart the same Friday does not bring it back.
    _prefs?.setString(_kWeekCardSeen, _weekCardSeenDay!).catchError((_) {});
    _track('week_card_opened');
    go(AppScreen.progress);
  }

  /// What travels with the picture: the sentence, and the link.
  String reviewShareText() {
    final r = weekReview();
    return '${isAr ? r.insight.ar : r.insight.en}\n${isAr ? 'أسبوعي مع قمر' : 'My week with Qamar'} · ${QamarConfig.site}';
  }

  /// The card, rendered by the screen, handed to the share sheet: only
  /// once the week has three logged days ([WeekReview.enough]), as the week
  /// card on Today waits. Before then its sentence is what is still missing.
  Future<void> shareReview(Uint8List png) async {
    final s = _sharer;
    if (s == null || !weekReview().enough) return;
    await s.shareImage(png, text: reviewShareText(), fileName: 'qamar-week.png');
    _track('review_shared');
  }

  // ---- streak + orb state ---------------------------------------------

  Future<void> _refreshStreak(String uid) async {
    try {
      final s = await _mealRepo?.streak(uid);
      if (s != null) serverStreak = s;
    } catch (_) {
      // The local count below still works; freezes wait for the next load.
    }
  }

  /// Days in a row with a meal, ending today or yesterday. The server's
  /// answer wins when it exists — it knows about freezes — but a meal logged
  /// this minute counts before the server has been asked again.
  Streak streak() {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final server = serverStreak;
    final local = Streak.fromDays(
      [for (final d in dayHistory) if (d.meals > 0) d.day, if (meals.isNotEmpty) today],
      today: today,
      frozenDays: server?.frozenDays ?? const [],
      freezesAvailable: server?.freezesAvailable ?? 0,
    );
    if (server == null) return local;
    if (meals.isNotEmpty && !server.todayCounted) {
      // Logged since the snapshot: today joins the run.
      return server.copyWith(
        current: server.current + 1,
        best: math.max(server.best, server.current + 1),
        todayCounted: true,
      );
    }
    return server.current >= local.current ? server : local;
  }

  /// What the orb shows: the moon fills toward today's target, the glow
  /// follows the day's meals against the plan, the ring is the streak.
  OrbState orbState() => OrbState.derive(
        consumedKcal: consumed().kcal,
        // No target on the general-guidance route, so nothing to read the
        // day against: the moon stays at rest (OrbDay.unknown).
        targetKcal: generalGuidance ? null : target().kcal,
        mealsToday: meals.length,
        planSlots: plan?.slots.length ?? 0,
        // The ring is the streak, so it goes with "Points and streaks" (O4).
        streak: showScore ? streak() : Streak.none,
      );

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

  /// Last night's sentence about today (the gateway's night job). Null when
  /// nothing was written — a new account, an empty day, no backend.
  NightNote? nightNote;

  Future<void> _refreshNightNote(String uid) async {
    try {
      final now = _clock();
      nightNote = await _mealRepo?.nightNote(uid, DateTime(now.year, now.month, now.day));
    } catch (_) {
      // The card simply stays away.
    }
  }

  /// The sentence in the app's language and digits, or null.
  String? get nightSentence {
    final n = nightNote;
    if (n == null) return null;
    return digits(isAr ? n.ar : n.en);
  }

  /// The plan behind the sentence is Qamar+: on the free tier the sentence is
  /// visible and the plan is locked — the blueprint's fourth paywall.
  bool get nightPlanLocked => !plusActive;

  /// Tapping the sentence: a member opens the plan; the free tier meets the
  /// wall, and that meeting is counted (the blueprint tests this wall against
  /// the scan limit).
  void openNightNote() {
    if (nightPlanLocked) {
      _track('wall_tapped', {'wall': 'tomorrow'});
      go(AppScreen.subscription);
      return;
    }
    go(AppScreen.plan);
  }

  /// The date [plan] was built for, so a day rolling over is noticed.
  String? planDate;

  bool planLoading = false;

  /// Why the last writing of today's plan did not happen, with the next
  /// step (O10). With no plan the Plan screen shows it in the plan's place;
  /// with one, above it, since the plan shown is the one from before. Null
  /// once a plan is written, or while nothing has been asked yet.
  Problem? planProblem;

  /// The problem's first line, for anything that only needs the words.
  String? get planError => planProblem?.what;

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
  /// The day as it stands, for Qamar's words about it (O3): what is eaten
  /// against the target, the hour, and the next planned meal still ahead.
  DayNumbers dayNumbers() {
    final con = consumed();
    final tg = target();
    // The general-guidance route has no target, on purpose: nothing is said
    // against one (the moon is at rest there too).
    final guided = generalGuidance;
    return DayNumbers(
      kcal: con.kcal,
      targetKcal: guided ? null : tg.kcal,
      protein: con.p,
      targetProtein: guided ? null : tg.protein,
      hour: _clock().hour,
      next: guided ? null : _plannedAhead(),
      ahead: _slotsAhead(),
    );
  }

  /// The meal slots still ahead today by the clock, not yet eaten.
  List<MealSlot> _slotsAhead() {
    final order = fasting ? const [MealSlot.iftar, MealSlot.suhoor] : const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];
    final at = order.indexOf(slotForHour(_clock().hour, fasting: fasting));
    final eaten = slotsLoggedToday;
    return [for (final slot in order.skip(at + 1)) if (!eaten.contains(slot)) slot];
  }

  /// The first planned meal in a later slot today that has not been eaten.
  ({String nameAr, String nameEn, int kcal})? _plannedAhead() {
    final order = fasting ? const [MealSlot.iftar, MealSlot.suhoor] : const [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];
    final at = order.indexOf(slotForHour(_clock().hour, fasting: fasting));
    final eaten = slotsLoggedToday;
    final planned = planMeals();
    for (final slot in order.skip(at + 1)) {
      if (eaten.contains(slot)) continue;
      for (final m in planned) {
        if (m.id == slot.name) return (nameAr: m.nameAr, nameEn: m.nameEn, kcal: mealKcal(m));
      }
    }
    return null;
  }

  PlanMeal? nextMeal() {
    final meals = planMeals();
    if (meals.isEmpty) return null;

    final hour = _clock().hour;
    final wanted = slotForHour(hour, fasting: fasting).name;
    for (final m in meals) {
      if (m.id == wanted) return m;
    }
    return meals.first;
  }

  bool isSlotSwapped(String slotId) => swappedSlots.contains(slotId);

  void toggleSlotSwap(String slotId) {
    if (!swappedSlots.remove(slotId)) swappedSlots.add(slotId);
    _notify();
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  void _installPlan(DayPlan built, {String via = 'request'}) {
    final first = planDate == null;
    plan = built;
    planDate = built.date;
    planProblem = null;
    // Written now, for the answer given now.
    _planMissed = null;
    _track('plan_shown', {'via': via, 'first': first});
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
    // No target, no plan: the gateway would refuse (life_stage, or no target
    // row), so it is not asked. The Plan screen says why instead.
    if (generalGuidance) return;
    final today = _today();
    // Something new to avoid since this day's plan was written: a new plan,
    // never the saved one, which the gateway returns unless forced.
    if (_planStaleDays.contains(today)) force = true;
    final note = instruction?.trim();
    if (!force && (note == null || note.isEmpty) && planDate == today && hasPlan) return;
    if (planLoading) return;

    final gateway = _ai;
    if (gateway == null) {
      planProblem = _behindFasting(Problem(
        what: isAr ? 'الخطة بتتكتب لك إنت بالذات، وده محتاج اتصال بالمساعد.' : 'The plan is written for you specifically, which needs a connection to the assistant.',
        action: ProblemAction(isAr ? 'ارجع للنهارده' : 'Back to Today', () => go(AppScreen.today), wayBack: true),
        kind: ProblemKind.offline,
      ));
      _notify();
      return;
    }

    planLoading = true;
    planProblem = null;
    _notify();
    try {
      final built = await gateway
          .generatePlan(
            date: today,
            lang: lang.code,
            force: force,
            instruction: (note == null || note.isEmpty) ? null : note,
          )
          .timeout(planTimeout);
      if (_disposed) return;
      await _pullQuota(gateway);
      _installPlan(built);
      if (_planStaleDays.remove(today)) _savePlanStaleDays();
    } on AiQuotaException catch (e) {
      if (_disposed) return;
      _absorb(e.quota);
      // A rewrite asked for in the conversation carries its instruction.
      planProblem = _planWall(e.message, rebuildAsked: note != null && note.isNotEmpty, notYet: _notYetLine);
    } catch (e) {
      if (_disposed) return;
      planProblem = _behindFasting(_planProblem(e, instruction: note));
    }
    planLoading = false;
    _notify();
  }

  /// How long writing the plan may take before the person is told the
  /// connection is too slow, instead of watching "Writing…" for ever.
  static const planTimeout = Duration(seconds: 60);

  /// The plan's daily cap (O10): a limit, not a failure. Su buys no plan
  /// uses, so the way on is whichever works now without the plan call:
  ///  * a question left and a plan to change: tell Qamar. A new meal or a
  ///    new day asked for in the conversation is saved under the question,
  ///    not the plan. Not after [rebuildAsked]: a full rewrite asked for in
  ///    the conversation is the metered call itself, and would meet this cap
  ///    again;
  ///  * otherwise, a meal on today's plan with another option: swap it on
  ///    the plan, which spends nothing;
  ///  * otherwise, back to Today: the plan can be written again tomorrow.
  /// The server's own words are kept only when the way they name works.
  /// [notYet] is what a change the rewrite was for left undone (a fasting
  /// switch): it is said first, and the cap becomes its reason.
  Problem _planWall(String message, {bool rebuildAsked = false, String? notYet}) {
    final canAsk = !rebuildAsked && hasAssistant && aiQuota.remaining > 0 && hasPlan;
    final canSwap = hasPlan && (plan?.slots.any((s) => slotHasAlternative(s.$1.id)) ?? false);
    final what = isAr ? 'الخطة اتكتبت كفاية النهارده.' : 'Today’s plan has been rewritten enough.';
    String? because(String? way) => notYet == null
        ? way
        : [isAr ? 'اتكتبت كفاية النهارده، فمتكتبتش تاني.' : 'It has been rewritten enough today, so it wasn’t written again.', if (way != null) way].join(' ');
    final toPlan = ProblemAction(isAr ? 'بدّل وجبة من الخطة' : 'Swap a meal on the plan', () {
      chatOpen = false;
      // Already there, the card steps aside for the meals and their swaps.
      if (screen == AppScreen.plan) {
        planProblem = null;
        _notify();
        return;
      }
      go(AppScreen.plan);
    });
    if (canAsk) {
      return Problem(
        what: notYet ?? message,
        why: because(notYet == null ? null : (isAr ? 'قمر لسه يقدر يغيّر وجباتها في المحادثة.' : 'Qamar can still change its meals in the conversation.')),
        action: ProblemAction(isAr ? 'قول لقمر إيه اللي اتغيّر' : 'Tell Qamar what changed', openChat),
        secondary: canSwap ? toPlan : null,
        kind: ProblemKind.limit,
      );
    }
    if (canSwap) {
      return Problem(
        what: notYet ?? what,
        why: because(isAr ? 'الوجبة اللي ليها بديل تقدر تبدّلها من الخطة نفسها، ومن غير ما تصرف حاجة.' : 'A meal with another option can be swapped on the plan itself, and that spends nothing.'),
        action: toPlan,
        kind: ProblemKind.limit,
      );
    }
    return Problem(
      what: notYet ?? what,
      why: because(isAr ? 'تقدر تتكتب تاني من بكرة.' : 'It can be written again from tomorrow.'),
      action: ProblemAction(isAr ? 'ارجع للنهارده' : 'Back to Today', () {
        chatOpen = false;
        go(AppScreen.today);
      }, wayBack: true),
      kind: ProblemKind.limit,
    );
  }

  /// The gateway refuses to guess, and its refusals are actionable — say what
  /// they mean and offer the next step, never a raw status or exception.
  /// [instruction] is a rewrite asked for in the conversation: trying again
  /// asks for the same rewrite, not a different plan.
  Problem _planProblem(Object e, {String? instruction}) {
    final retry = ProblemAction(isAr ? 'جرّب تاني' : 'Try again', () => ensurePlan(force: true, instruction: instruction));
    final away = isAr ? 'الخطة بتتكتب لك على السيرفر، فمحتاجة نت.' : 'The plan is written for you on our server, so it needs a connection.';
    switch (failureOf(e)) {
      case Failure.offline:
        return Problem(what: isAr ? 'مفيش نت دلوقتي.' : 'You’re offline right now.', why: away, action: retry, kind: ProblemKind.offline);
      case Failure.slow:
        return Problem(what: isAr ? 'النت بطيء دلوقتي.' : 'The connection is too slow right now.', why: away, action: retry, kind: ProblemKind.offline);
      case Failure.ours:
        break;
    }
    final raw = '$e';
    if (raw.contains('409') || raw.contains('no target')) {
      return Problem(
        what: isAr ? 'محتاج أعرف هدفك الأول.' : 'I need your target first.',
        why: isAr ? 'كمّل الأسئلة وهعملك الخطة.' : 'Finish the questions and I will build the plan.',
        action: ProblemAction(isAr ? 'كمّل الأسئلة' : 'Finish the questions', startOnboarding),
      );
    }
    if (raw.contains('503') || raw.contains('no grounded guidance')) {
      return Problem(
        what: isAr ? 'مفيش مصادر موثوقة متسجلة لسه.' : 'There is no trusted guidance loaded yet.',
        why: isAr ? 'ومش هألّف خطة من دماغي.' : 'I will not invent a plan without it.',
        action: retry,
      );
    }
    if (raw.contains('403') || raw.contains('not eligible')) {
      return Problem(
        what: isAr ? 'الحساب ده مش مؤهل للخطط.' : 'This account is not eligible for plans.',
        action: ProblemAction(isAr ? 'ارجع للنهارده' : 'Back to Today', () => go(AppScreen.today), wayBack: true),
      );
    }
    if (raw.contains('429') || raw.toLowerCase().contains('quota')) {
      return _planWall(isAr
          ? 'الخطة اتكتبت كفاية النهارده. عدّل الوجبات من الخطة نفسها، أو قوللي إيه اللي اتغيّر وأنا أظبط الباقي.'
          : 'Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.');
    }
    return Problem(
      what: isAr ? 'حصلت مشكلة عندنا.' : 'Something went wrong on our side.',
      why: isAr ? 'مش منك. جرّب تاني بعد شوية.' : 'It isn’t you. Try again in a moment.',
      action: retry,
    );
  }

  // ---- ask qamar (companion overlay) -------------------------------------------------

  /// The conversation header's quota line (O8): nothing while two or more
  /// questions are left, so the conversation never opens on a countdown; a
  /// sentence at the last one, so the limit is never a surprise; and at none,
  /// what still works. Never a number. The full count is in Me
  /// ([quotaSummary]).
  String get quotaLine {
    if (!hasAssistant) return '';
    final left = aiQuota.remaining;
    if (left >= 2) return '';
    if (left == 1) return isAr ? 'آخر سؤال النهارده' : 'Last question today';
    // Short enough to stay whole in the one-line header on a 390pt phone,
    // at the 12pt it is set in: cut short it would lose what still works.
    return isAr ? 'خلصت أسئلة النهارده · لسه تقدر تسجّل أكلك' : 'No questions left today · you can still log meals';
  }

  /// Today's allowance in full, for Me: questions and photos left of the
  /// day's total. Empty when there is no assistant to ask.
  String get quotaSummary {
    if (!hasAssistant) return '';
    final q = aiQuota, p = photoQuota;
    final qTotal = q.limit + q.extra, pTotal = p.limit + p.extra;
    return isAr
        ? 'فاضل النهارده — أسئلة: ${iso('${q.remaining}')} من ${iso('$qTotal')} · صور: ${iso('${p.remaining}')} من ${iso('$pTotal')}'
        : 'Left today — questions: ${q.remaining} of $qTotal · photos: ${p.remaining} of $pTotal';
  }

  /// A typed or spoken meal the food data could not match (O10): the other
  /// way to log it, if it works today. A photo, while today's photos last —
  /// the free tier has its three a day, so no Qamar+ is needed; once they
  /// are used, the words that can be matched instead.
  String get notFoundReply => photoQuota.remaining > 0
      ? (isAr ? 'مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو صوّر الطبق.' : 'I could not match that food. Try a clearer name, or photograph the plate.')
      : (isAr ? 'مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو قوللي فيه إيه وقد إيه.' : 'I could not match that food. Try a clearer name, or tell me what’s in it and how much.');

  void openChat() {
    chatOpen = true;
    _collapseTree();
    // Reopened while a meal is still being read: Qamar is still reading it.
    chatState = _mealReads > 0 ? ChatState.thinking : ChatState.idle;
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
    // Closed mid-sentence, the words still arrive and are the meal. Closed
    // otherwise, a log armed here and not yet answered was abandoned. A
    // reading on its way, or one waiting to be confirmed, is not touched: it
    // took its start with it when it began.
    if (chatState != ChatState.listening) _abandonLog();
    _notify();
  }

  void onChatDraftChanged(String v) {
    chatDraft = v;
    _notify();
  }

  void sendChat() {
    final v = chatDraft.trim();
    if (v.isNotEmpty || chatPhotoPath != null) sendChatMsg(v);
  }

  // ---- a photo in the conversation ----------------------------------------
  //
  // "Photograph the menu, ask what to order." The picture attaches to the next
  // message; the words with it may be empty, in which case the question is
  // implied. The gateway meters it as one of the day's photos.

  /// The photo waiting to go with the next message, if one was taken.
  String? chatPhotoPath;

  void attachChatPhoto(String path) {
    chatPhotoPath = path;
    chatOpen = true;
    _notify();
  }

  void detachChatPhoto() {
    chatPhotoPath = null;
    _notify();
  }

  /// What a photo asks when nothing was typed with it.
  String get menuPhotoQuestion => isAr ? 'أطلب إيه من هنا؟' : 'What should I order here?';

  /// Sends a message and answers it with the real assistant.
  ///
  /// There is no scripted fallback. If the gateway is not configured or the
  /// call fails, Qamar says so — a health app inventing a plausible-sounding
  /// reply is worse than one admitting it is not connected.
  ///
  /// [again] asks a question already in the conversation once more (the one
  /// bought with Su at the wall), so it is not shown a second time.
  Future<void> sendChatMsg(String text, {bool again = false}) async {
    final photo = again ? null : chatPhotoPath;
    if (!again) chatPhotoPath = null;
    if (text.trim().isEmpty && photo != null) text = menuPhotoQuestion;
    // A meal only in answer to a meal question still on screen. Whatever is
    // said, that question has now been answered or passed over.
    final asMeal = !again && _loggingMeal;
    _mealAskAt = null;
    if (!again) chat.add(ChatTurn(who: ChatWho.u, text: text, photoPath: photo));
    lastUser = text;
    chatDraft = '';
    chatState = ChatState.thinking;
    _notify();

    // An answer to a meal question: this message describes a meal, so it goes
    // to the analyser rather than the chat model, and comes back as something
    // to confirm instead of something to read. A photo taken meanwhile is the
    // meal's photo.
    if (asMeal) {
      await _analyseMeal(inputType: photo != null ? 'photo' : proposalInput, text: text, imagePath: photo);
      return;
    }
    _track('question_asked', {if (photo != null) 'photo': true, if (again) 'bought': true});

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
        imagePath: photo,
      );
      if (_disposed) return;

      var menuMoved = false;
      if (result.plan != null) {
        _installPlan(result.plan!, via: 'chat');
        menuMoved = true;
      } else if (result.rebuildInstruction != null && result.rebuildInstruction!.trim().isNotEmpty) {
        while (planLoading && !_disposed) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        if (_disposed) return;
        await ensurePlan(force: true, instruction: result.rebuildInstruction);
        if (_disposed) return;
        final refused = planProblem;
        if (refused != null) {
          // The rewrite did not happen (the plan's cap, or a failure). The
          // model's reply spoke as if it would, so it is not shown: Qamar
          // says what happened instead, with the way on that works now.
          await _pullQuota(gateway);
          chatState = ChatState.idle;
          chat.add(ChatTurn(who: ChatWho.q, text: refused.what, sub: refused.why, problem: refused));
          _notify();
          return;
        }
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
      _onQuotaHit(e, asked: photo == null ? text : null);
    } catch (e) {
      if (_disposed) return;
      chatState = ChatState.idle;
      chat.add(ChatTurn(
        who: ChatWho.q,
        text: isAr
            ? 'مقدرتش أوصل للمساعد دلوقتي. جرّب تاني بعد شوية.'
            : 'I could not reach the assistant just now. Try again in a moment.',
        sub: _failedWhy(e),
        // What was asked goes back in the box, so trying again is one tap.
        problem: Problem(
          what: isAr ? 'مقدرتش أوصل للمساعد دلوقتي. جرّب تاني بعد شوية.' : 'I could not reach the assistant just now. Try again in a moment.',
          why: _failedWhy(e),
          action: ProblemAction(isAr ? 'جرّب تاني' : 'Try again', () {
            chatDraft = text;
            _notify();
          }),
          kind: failureOf(e) == Failure.ours ? ProblemKind.error : ProblemKind.offline,
        ),
      ));
    }
    _notify();
  }

  /// Live transcript while the user is speaking, so the words appear as they
  /// are said instead of arriving all at once.
  String heard = '';

  /// Set when dictation cannot run at all — no recogniser, or the recogniser
  /// failed. The UI offers typing instead of leaving a dead button. A refused
  /// microphone is not this: it is a permission, said as Qamar's line with
  /// its ways on ([micProblem]).
  String? dictationError;

  /// Qamar's "I am listening" line, while it is the last thing said: a
  /// microphone that turns out to be off must not leave it standing.
  ChatTurn? _listeningLine;

  /// Asked each time the composer should take the keyboard, as "Type it
  /// instead" does; the conversation's field follows it.
  int composerFocus = 0;

  void focusComposer() {
    composerFocus++;
    _notify();
  }

  /// The microphone is off for Qamar (O10): a permission, like the camera's,
  /// with Settings first where the phone can be taken there, and typing
  /// always, which never needed the microphone.
  Problem micProblem({required ProblemAction instead}) {
    final settings = canOpenAppSettings ? ProblemAction(isAr ? 'افتح الإعدادات' : 'Open Settings', openAppSettings) : null;
    return Problem(
      what: isAr ? 'المايك مقفول لقمر.' : 'The microphone is off for Qamar.',
      why: settings != null
          ? (isAr ? 'افتحه من الإعدادات، أو اكتبها بدل كده.' : 'Allow it in Settings, or type it instead.')
          : (isAr ? 'اسمح لقمر بالمايك من إعدادات الموبايل، أو اكتبها بدل كده.' : 'Allow the microphone for Qamar in your phone’s Settings, or type it instead.'),
      action: settings ?? instead,
      secondary: settings == null ? null : instead,
      kind: ProblemKind.permission,
    );
  }

  /// Listening was asked for and the microphone is off: Qamar says so in
  /// place of "I am listening", and a meal being logged stays armed, so what
  /// is typed next is still the meal.
  void _micRefused() {
    final logging = _loggingMeal;
    if (_listeningLine != null && chat.isNotEmpty && identical(chat.last, _listeningLine)) chat.removeLast();
    _listeningLine = null;
    final p = micProblem(instead: ProblemAction(isAr ? 'اكتبها بدل كده' : 'Type it instead', focusComposer));
    chat.add(ChatTurn(who: ChatWho.q, text: p.what, sub: p.why, problem: p));
    if (logging) {
      _armMealLog();
      proposalInput = 'text';
    }
    dictationError = null;
    chatState = ChatState.idle;
    _track('mic_refused', {'logging': logging});
    _notify();
  }

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

    var failed = false;
    final ok = await dictation.prepare(
      onError: (e) {
        failed = true;
        dictationError = isAr ? 'مقدرتش أسمعك — جرّب تاني، أو اكتبها.' : 'I couldn’t hear that — try again, or type it.';
        debugPrint('dictation: $e');
        chatState = ChatState.idle;
        // Closed while listening, and nothing came: the log is abandoned.
        if (!chatOpen) _abandonLog();
        _notify();
      },
    );
    if (!ok) {
      // The recogniser failed and has said so; otherwise the microphone was
      // not allowed, which is a permission with a way on, not an error.
      if (failed) {
        _notify();
        return;
      }
      _micRefused();
      return;
    }

    dictationError = null;
    _listeningLine = null;
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
          // Closed while listening, and nothing was said: abandoned.
          if (said.isEmpty && !chatOpen) _abandonLog();
          _notify();
          if (said.isNotEmpty) sendChatMsg(said);
        }
      },
    );
  }

  void chatSuggestionTap(String label) => sendChatMsg(label);

  void chatActionTap() {
    final last = chat.isNotEmpty ? chat.last : null;
    chatOpen = false;
    if (last?.openPlus == true) {
      openSubscription();
      return;
    }
    screen = last?.openWallet == true ? AppScreen.wallet : AppScreen.plan;
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
        // Not the paywall (O1): its back control at the top is the way home
        // (way_back_test), and a decision is made there without the orb over
        // the comparison table or its tree offering ways out mid-choice.
        // Reached from the tree in season: without the orb, and with no back
        // control, it was the one screen with no way out.
        AppScreen.ramadan,
      }.contains(screen);

  /// [start] is measured from the start edge (see [orbStart]); a drag in
  /// Arabic turns its physical movement into start-relative movement first.
  /// Holds the orb at a place off the band, as a drag does.
  void setOrbPosition(double start, double y, {required double maxX, required double maxY}) {
    orbStart = start.clamp(4, maxX).toDouble();
    orbY = y.clamp(46, maxY).toDouble();
    orbHeld = true;
    _notify();
  }

  /// Lets go of the orb: it rests at [stop] in the band, and the phone keeps
  /// that choice for the next launch.
  void settleOrb(OrbStop stop) {
    orbStop = stop;
    orbHeld = false;
    _prefs?.setString(_kOrbStop, stop.name).catchError((_) {});
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
    _learn(OrbGesture.explain);
    explainOpen = ex;
    explainHoverId = null;
    _notify();
  }

  void closeExplain() {
    explainOpen = null;
    _notify();
  }

  // ---- the orb's gestures ---------------------------------------------
  //
  // Blueprint contract. Tap: on Today the tree blooms; anywhere else it goes
  // home to Today — the orb is the one fixed point, so "tap the orb" always
  // gets home (a screen's back arrow, [back], goes where the person came from).
  // Hold: the conversation opens and the moon is already listening. Drag:
  // move the orb, and drop it on a value to have it explained (the explain
  // section above).

  void orbTap() {
    _learn(OrbGesture.tap);
    if (chatOpen) return;
    if (screen != AppScreen.today) {
      _collapseTree();
      go(AppScreen.today);
      return;
    }
    toggleTree();
  }

  /// Hold to talk. Voice is the default input: the conversation opens and the
  /// moon starts listening straight away; typing is one tap away inside it.
  Future<void> holdOrb() async {
    _learn(OrbGesture.hold);
    if (chatOpen) return;
    _collapseTree();
    final n = waitingNudge;
    // The orb holds a meal question. Qamar asks it, as its newest line, the
    // first time the orb is held while it waits in this conversation, and
    // what is said next is the meal, as when the same question arrives as a
    // notification: the in-app prompt is recorded here. Held again while it
    // is still Qamar's last line, it is the same ask. Once the talk has moved
    // past it, or while a log is already under way (a reading to confirm, or
    // one still being read), the hold opens the conversation where it is.
    if (n != null && !_logUnderWay && (_askedQuestion != _questionKey(n) || _asking(n))) {
      _logStart = _logStartNow(fromWaitingQuestion: true);
      _askNudgeQuestion(n);
      openChat();
      _armMealLog();
      proposalInput = 'voice';
      await tapOrbListen();
      return;
    }
    openChat();
    await tapOrbListen();
  }

  /// Index of the Log node while its input methods are fanned out.
  int? treeLogIndex;
  bool get treeLogExpanded => treeLogIndex != null;

  /// Index of the Water node while its units are fanned out.
  int? treeWaterIndex;
  bool get treeWaterExpanded => treeWaterIndex != null;

  /// Whether the ring currently shows a node's choices rather than the nodes.
  bool get treeExpanded => treeLogExpanded || treeWaterExpanded;

  void expandTreeLog(int index) {
    treeWaterIndex = null;
    treeLogIndex = index;
    _notify();
  }

  void expandTreeWater(int index) {
    treeLogIndex = null;
    treeWaterIndex = index;
    _notify();
  }

  /// The Log node's third level, while a branch of it is fanned out.
  TreeSub? treeLogSub;

  void expandTreeSub(TreeSub sub) {
    treeLogSub = sub;
    _notify();
  }

  // ---- repeat a meal ---------------------------------------------------

  /// The last week's meals from the server, newest first; today's local
  /// meals come first in [repeatChoices] whatever the server has.
  final List<LoggedMeal> recentMeals = [];

  /// Up to five distinct recent meals, newest first — the ring's choices.
  List<LoggedMeal> get repeatChoices {
    final seen = <String>{};
    final out = <LoggedMeal>[];
    for (final m in [...meals.reversed, ...recentMeals]) {
      final key = m.name.trim().toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(m);
      if (out.length == 5) break;
    }
    return out;
  }

  /// Logs [source] again, now, with the same numbers. No model, no
  /// confirmation step: repeating is the two-tap path the blueprint asks for.
  void repeatMeal(LoggedMeal source) {
    // One tap from the tree: the log starts and ends here, so its start is
    // now, never one left over from an earlier, abandoned log.
    _logStart = null;
    final start = _logStartNow();
    _collapseTree();
    final first = meals.isEmpty;
    final meal = LoggedMeal(
      name: source.name,
      sub: isAr ? 'مكرر' : 'Repeated',
      kcal: source.kcal,
      p: source.p,
      c: source.c,
      f: source.f,
      at: _clock(),
      prompt: start.prompt,
      orbWaiting: start.orbWaiting,
    );
    meals.add(meal);
    final award = first ? SuEconomy.firstMeal : SuEconomy.mealLogged;
    _credit(award, ar: first ? 'أول وجبة' : 'تأكيد وجبة', en: first ? 'First meal logged' : 'Meal confirmed');
    _track('meal_logged', {
      'source': 'recent',
      'first': first,
      'items': 1,
      'nudged': start.prompt == LogPrompt.push,
      'prompt': start.prompt,
      'orb_waiting': start.orbWaiting,
    });
    _nudgeTappedAt = null;
    chat.add(ChatTurn(
      who: ChatWho.q,
      text: replyFor(meal, dayNumbers(), ar: isAr, iso: iso),
      // The meal's own receipt, never the points (O3).
      sub: meal.sub,
    ));
    _notify();
    _rescheduleNudges();
    if (isBacked && _mealRepo != null) {
      final repo = _mealRepo;
      _pushDurable(
        PendingWrite(
          kind: PendingKind.meal,
          payload: {'meal': meal.toJson(), 'items': const [], 'input': 'recent', 'raw': source.name},
          at: _clock(),
        ),
        (uid) async {
          final draftId = await repo.saveDraft(uid, MealAnalysisDraft(inputType: 'recent', items: const [], rawText: source.name));
          await repo.confirmMeal(uid, draftId: draftId, meal: meal);
        },
        after: (uid) async {
          await _refreshStreak(uid);
          await _refreshWallet(uid);
          _notify();
        },
      );
    }
  }

  // ---- activity --------------------------------------------------------

  final List<ActivityLog> activitiesToday = [];

  /// The kind chosen on the ring, while the duration is being asked.
  ActivityKind? pendingActivity;

  int get activityMinutesToday => activitiesToday.fold(0, (s, a) => s + a.minutes);
  int get activityKcalToday => activitiesToday.fold(0, (s, a) => s + a.kcal);

  void chooseActivity(ActivityKind kind) {
    pendingActivity = kind;
    _collapseTree();
    _notify();
  }

  void cancelActivity() {
    pendingActivity = null;
    _notify();
  }

  /// Writes the movement with an estimate of its cost. Shown, never added to
  /// the food budget: the consultation's activity factor already carries the
  /// person's usual movement, and counting a match twice would be the
  /// tracker habit this app is not building.
  Future<void> logActivity(int minutes) async {
    final kind = pendingActivity;
    if (kind == null) return;
    final entry = ActivityLog(kind: kind, minutes: minutes, kcal: ActivityCatalog.kcalFor(kind, minutes, profile.weight), at: _clock());
    activitiesToday.add(entry);
    pendingActivity = null;
    _credit(SuEconomy.activityLogged, ar: 'حركة', en: 'Activity logged');
    _track('activity_logged', {'kind': kind.name, 'minutes': minutes});
    _notify();
    final repo = _activityRepo;
    if (!isBacked || repo == null) return;
    await _pushDurable(
      PendingWrite(kind: PendingKind.activity, payload: entry.toJson(), at: _clock()),
      (uid) async {
        final id = await repo.add(uid, entry);
        final i = activitiesToday.indexOf(entry);
        if (i >= 0) activitiesToday[i] = entry.copyWith(id: id);
      },
      after: (uid) async {
        await _refreshWallet(uid);
        _notify();
      },
    );
  }

  /// One tap on a unit logs it and closes the tree. Nothing goes through the
  /// assistant.
  void quickWater(WaterUnit unit) {
    closeTree();
    logWater(unit);
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
    _logStart = _logStartNow();
    _collapseTree();
    openChat();

    if (kind == QuickLog.photo) return; // the caller hands the shot back

    proposalInput = kind == QuickLog.voice ? 'voice' : 'text';
    final ask = ChatTurn(
      who: ChatWho.q,
      text: kind == QuickLog.voice
          ? (isAr ? 'أنا سامعك. أكلت إيه؟' : 'I am listening. What did you eat?')
          : (isAr ? 'اكتبلي أكلت إيه.' : 'Tell me what you ate.'),
      sub: isAr ? 'مفيش حاجة بتتسجل قبل ما تأكد.' : 'Nothing is saved until you confirm.',
    );
    chat.add(ask);
    _listeningLine = kind == QuickLog.voice ? ask : null;
    // Whatever they say or type next, in answer, is a meal, not a question.
    _armMealLog();
    if (kind == QuickLog.voice) tapOrbListen();
  }

  /// Most recent meal photo, shown inside the conversation.
  String? lastMealPhotoPath;

  /// A meal photographed from the orb. The picture is sent to the assistant,
  /// which reads it and proposes items — all inside the conversation, with no
  /// analysing page and no confirm page. Three a day are free; the server says
  /// so when they are gone, and the wallet sells a fourth for Su.
  void logPhotoTaken(String path) {
    _logStart ??= _logStartNow();
    lastMealPhotoPath = path;
    _mealAskAt = null;
    proposalInput = 'photo';
    chat.add(ChatTurn(who: ChatWho.u, text: isAr ? 'صوّرت الوجبة دي' : 'I photographed this meal'));
    _notify();
    _analyseMeal(inputType: 'photo', imagePath: path);
  }

  void toggleTree() {
    if (treeOpen) {
      _collapseTree();
    } else {
      treeOpen = true;
    }
    _notify();
  }

  /// The tree was opened by Today's "Log a meal" button rather than the moon.
  bool treeOpenedFromButton = false;

  /// Today's "Log a meal" button (O15): the tree, already open on Log, with
  /// its ways to log fanned out. It opens the moon's own menu rather than
  /// going round it, so using the button shows where logging lives; until
  /// the moon has been tapped, the tree says "next time, tap the moon".
  void openTreeOnLog() {
    treeOpen = true;
    treeOpenedFromButton = true;
    _track('log_button_tapped', const {});
    // Log is the first node on the ring.
    expandTreeLog(0);
  }

  void closeTree() {
    _collapseTree();
    _notify();
  }

  /// Closes the ring and folds any fanned-out node back, without notifying —
  /// every caller goes on to change something else and notifies once. Every
  /// way the tree closes comes through here, so a close is counted once.
  void _collapseTree() {
    if (treeOpen && !gesturesLearned.contains(OrbGesture.hold)) treeClosesWithoutHold++;
    treeLogIndex = null;
    treeLogSub = null;
    treeWaterIndex = null;
    treeProblem = null;
    treeOpenedFromButton = false;
    treeOpen = false;
  }
}
