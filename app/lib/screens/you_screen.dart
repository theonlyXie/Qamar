import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/billing.dart';
import '../models/invitation.dart';
import '../models/su_economy.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/orb_gesture_guide.dart';
import '../widgets/moon.dart';

class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

  /// The "Points and streaks" switch (O4) and its row, found by tests.
  static const scoreSwitchKey = ValueKey('points-and-streaks');
  static const scoreRowKey = ValueKey('points-and-streaks-row');
  static const proCodeKey = ValueKey('affiliate-code');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final tg = state.target();

    // Everything in this list is read off real state. "Qamar memory" counts
    // what Qamar actually holds about this person — it used to say "6 items"
    // regardless of whether it knew anything at all.
    final remembered = state.rememberedCount();
    final rows = <(String, String)>[
      (isAr ? 'الهدف والسعرات' : 'Target and calories', isAr ? '${state.iso('${tg.kcal}')} سعر' : '${tg.kcal} kcal'),
      (isAr ? 'ما يجب تجنبه' : 'What to avoid', state.profile.prefs.isNotEmpty ? state.iso('${state.profile.prefs.length}') : (isAr ? 'مفيش' : 'None')),
      (
        isAr ? 'ذاكرة قمر' : 'Qamar memory',
        remembered == 0
            ? (isAr ? 'فاضية' : 'Empty')
            : (isAr ? '${state.iso('$remembered')} عناصر' : '$remembered items')
      ),
      (isAr ? 'محفظة نقاط Su' : 'Su Points wallet', state.iso(state.formatSu(state.suAvailable))),
      (isAr ? 'الموافقات' : 'Consents', isAr ? 'الإصدار ${state.digits(QamarConfig.consentVersion)}' : 'v${QamarConfig.consentVersion}'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        Row(children: [
          QBackButton(onTap: state.back, isAr: isAr),
          const SizedBox(width: 6),
          Expanded(child: Text(t.you, style: QText.display(size: 30, ar: QText.arabic(t.you), color: QColors.textPrimary))),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), border: QColors.borderStrong, radius: QRadii.xl),
          child: Row(children: [
            const QamarMoon(size: 48),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.profile.name.isNotEmpty ? state.profile.name : (isAr ? 'يا صاحبي' : 'friend'), style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.textPrimary)),
              Text(state.accountEmail ?? t.guestAccount, style: QText.body(size: 12, color: QColors.textMuted)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        // Only offered while the account really is a guest one. Once an email
        // is attached this card would be inviting the user to do something
        // they have already done.
        if (!state.hasAccount) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: QColors.violet.withOpacity(0.1), border: Border.all(color: QColors.violet.withOpacity(0.4)), borderRadius: BorderRadius.circular(QRadii.xl)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.saveProgress, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                const SizedBox(height: 4),
                Text(t.saveProgressSub, style: QText.body(size: 13, height: 20, color: QColors.textMid)),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: QPillButton(label: t.linkAccount, onTap: state.openLinkAccount),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(QRadii.xl),
            onTap: state.openSubscription,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
                border: Border.all(color: QColors.violet.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(QRadii.xl),
              ),
              child: Row(children: [
                const QamarMoon(size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('Qamar+', textDirection: TextDirection.ltr, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                      if (state.plusActive) ...[
                        const SizedBox(width: 8),
                        Text(isAr ? 'مفعّل' : 'Active',
                            style: QText.body(size: 11, weight: FontWeight.w600, color: QColors.green)),
                      ],
                    ]),
                    Text(
                      state.plusActive
                          ? (isAr ? 'شكراً إنك معانا' : 'Thanks for supporting Qamar')
                          : state.trialWaiting
                              // "Not now" at the reveal leaves the free week here.
                              ? (isAr
                                  ? 'أسبوعك المجاني مستنيك: ${state.iso('${AppState.trialOfferDays}')} أيام، من غير بطاقة، ومفيش حاجة بتتجدد لوحدها.'
                                  : 'Your free week is waiting: ${AppState.trialOfferDays} days, no card, nothing renews.')
                              : (isAr ? 'خطة بكرة، وصور وأسئلة أكتر' : 'Tomorrow’s plan, more photos and questions'),
                      style: QText.body(size: 12, height: 18, color: QColors.textMuted),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right, size: 20, color: QColors.textMuted),
              ]),
            ),
          ),
        ),
        // The day's allowance in full. The conversation's header says only
        // "Last question today" near the limit (O8); the numbers are here.
        if (state.quotaSummary.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
            child: Text(state.quotaSummary, style: QText.body(size: 12, height: 18, color: QColors.textMuted)),
          ),
        ],
        const SizedBox(height: 14),
        _ProCodeCard(state: state),
        const SizedBox(height: 14),
        _AffiliateCard(state: state),
        if (state.proClients.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ClientsCard(state: state),
        ],
        const SizedBox(height: 14),
        _InvitationsCard(state: state),
        const SizedBox(height: 14),
        // The moon's gestures, for good: the tutorial on Today can be put
        // away, and this is where to look them up again.
        OrbGestureGuide(state: state, dismissible: false),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isAr ? 'كلم قمر من برّه التطبيق' : 'Talk to Qamar without opening the app',
                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'آيفون: الإعدادات ← تسهيلات الاستخدام ← لمس ← الضغط على الخلف ← اربط «Ask Qamar» أو «Log a meal with Qamar».\n'
                      'أندرويد: اضغط مطوّلاً على أيقونة قمر واختار اسأل / سجّل وجبة. على Pixel: الإيماءات ← Quick Tap ← افتح قمر، أو نفس الاختصار.'
                    : 'iPhone: Settings → Accessibility → Touch → Back Tap → assign “Ask Qamar” or “Log a meal with Qamar”.\n'
                      'Android: long-press the Qamar icon and choose Ask / Log a meal. On Pixel: Gestures → Quick Tap → open Qamar, or the same shortcut.',
                style: QText.body(size: 12, height: 18, color: QColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'سيري: «Ask Qamar» أو «Log a meal with Qamar». تسجيل الوجبة من الاختصار مجاناً ومش بيتعد. سؤال قمر بيتعد من التلات أسئلة اليومية.'
                    : 'Siri: “Ask Qamar” or “Log a meal with Qamar”. Logging a meal from a shortcut is free and never counted. Asking Qamar counts toward the daily three.',
                style: QText.body(size: 12, height: 18, color: QColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: QColors.gold.withOpacity(0.08), border: Border.all(color: QColors.gold.withOpacity(0.32)), borderRadius: BorderRadius.circular(QRadii.xl)),
          child: Row(children: [
            const SuCoinIcon(size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.walletTitle, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.goldPale)),
                // Lifetime earned keeps score (it is what Level is made of),
                // so with "Points and streaks" off only the balance is said.
                Text(
                  state.showScore
                      ? (isAr ? '${state.iso(state.formatSu(state.suAvailable))} متاح · ${state.iso(state.formatSu(state.suLifetime))} مكتسب' : '${state.formatSu(state.suAvailable)} available · ${state.formatSu(state.suLifetime)} lifetime')
                      : (isAr ? '${state.iso(state.formatSu(state.suAvailable))} متاح' : '${state.formatSu(state.suAvailable)} available'),
                  style: QText.body(size: 12, color: QColors.goldMuted),
                ),
              ]),
            ),
            QOutlineButton(label: t.spendTab, onTap: state.openWallet, height: 36, color: QColors.gold),
          ]),
        ),
        const SizedBox(height: 10),
        // "Points and streaks" (O4): off hides everything on screen that keeps
        // score, and only hides it. The wallet's balance stays, for whoever
        // goes to look, and earning, freezes and photo purchases carry on.
        // The whole row is the control, not only the switch.
        MergeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: YouScreen.scoreRowKey,
              borderRadius: BorderRadius.circular(QRadii.lg),
              onTap: () => state.setShowScore(!state.showScore),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isAr ? 'النقاط والسلسلة' : 'Points and streaks', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                      Text(
                        isAr
                            ? 'نقاط Su ومستواك والسلسلة ومهمة اليوم على شاشاتك. لو قفلتها بتستخبى بس: النقاط بتتحسب زي ما هي، ورصيدك فاضل في المحفظة.'
                            : 'Su, your level, the streak and the day’s quest on your screens. Off only hides them: you still earn, and your balance stays in the wallet.',
                        style: QText.body(size: 12, height: 16, color: QColors.textMuted),
                      ),
                    ]),
                  ),
                  Switch.adaptive(
                    key: YouScreen.scoreSwitchKey,
                    value: state.showScore,
                    onChanged: state.setShowScore,
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final r in rows) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(r.$1, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
              Text(r.$2, style: QText.body(size: 13, color: QColors.textMuted)),
            ]),
          ),
        ],
        // Both of these are store requirements, and the second is a legal
        // obligation — they cannot stay as decoration.
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isAr ? 'سياسة الخصوصية والشروط' : 'Privacy policy and terms',
                style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
            Row(children: [
              QLegalLink(label: isAr ? 'الخصوصية' : 'Privacy', url: QamarConfig.privacyUrl, size: 12),
              Text('  ·  ', style: QText.body(size: 12, color: QColors.textMuted)),
              QLegalLink(label: isAr ? 'الشروط' : 'Terms', url: QamarConfig.termsUrl, size: 12),
            ]),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(
              child: Text(isAr ? 'تصدير أو حذف بياناتي' : 'Export or delete my data',
                  style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
            ),
            QLegalLink(label: isAr ? 'افتح' : 'Open', url: QamarConfig.deleteDataUrl, size: 12),
          ]),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(isAr ? 'اللغة' : 'Language', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
            QLangToggle(lang: state.lang, onChanged: state.setLang),
          ]),
        ),
        // The consent given in the consultation, changeable here. Off means
        // off: the analytics SDK stops and nothing is sent again.
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'تحسين الخدمة' : 'Service improvement', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                Text(
                  isAr ? 'أحداث استخدام مجهولة. من غير أكلك ولا جسمك ولا صورك.' : 'Anonymous usage events. Never your food, your body or your photos.',
                  style: QText.body(size: 12, height: 16, color: QColors.textMuted),
                ),
              ]),
            ),
            Switch.adaptive(
              value: state.improve,
              onChanged: (v) => state.setImprove(v),
            ),
          ]),
        ),
        // The professional programme's one condition: the client's yes.
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'مشاركة الالتزام مع أخصائيي' : 'Share adherence with my nutritionist',
                    style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                Text(
                  isAr
                      ? 'أرقام الأسبوع بس — أيام التسجيل والمتوسط مقابل الهدف. لصاحب الكود اللي على اشتراكك، وبس.'
                      : 'The week as numbers only — days logged and the average against your target. To whoever’s code is on your subscription, and no one else.',
                  style: QText.body(size: 12, height: 16, color: QColors.textMuted),
                ),
              ]),
            ),
            Switch.adaptive(
              value: state.adherenceShare,
              onChanged: (v) => state.setAdherenceShare(v),
            ),
          ]),
        ),
        if (isAr)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('الأرقام', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                Text(state.easternDigits ? '٠١٢٣٤٥٦٧٨٩' : '0123456789', style: QText.number(size: 12, color: QColors.textMuted)),
              ]),
              Switch.adaptive(
                value: state.easternDigits,
                onChanged: state.setEasternDigits,
              ),
            ]),
          ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isAr ? 'أسئلة قمر' : 'Qamar’s questions', style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
                  Text(isAr ? 'في مواعيد أكلك · مرتين كحد أقصى' : 'At your meal times · two a day at most',
                      style: QText.body(size: 12, color: QColors.textMuted)),
                ]),
              ),
              const SizedBox(width: 8),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final n in [0, 1, 2]) ...[
                  GestureDetector(
                    onTap: () { state.setNudgesPerDay(n); },
                    child: Container(
                      width: 36,
                      height: 30,
                      margin: const EdgeInsets.only(left: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: state.nudgesPerDay == n ? QColors.violetDeep : Colors.transparent,
                        border: Border.all(color: state.nudgesPerDay == n ? QColors.violetDeep : QColors.borderSoft),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(state.iso('$n'),
                          style: QText.number(size: 13, weight: FontWeight.w600, color: state.nudgesPerDay == n ? QColors.onAccent : QColors.textMuted)),
                    ),
                  ),
                ],
              ]),
            ]),
            if (state.nudgesPerDay > 0 && state.nudgePromptDone && !state.nudgesAllowed) ...[
              const SizedBox(height: 6),
              Text(isAr ? 'مقفولة من إعدادات الموبايل — افتحها من هناك.' : 'Off in the phone’s settings — turn them on there.',
                  style: QText.body(size: 12, color: QColors.amber)),
            ],
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [QColors.cyan.withOpacity(0.12), QColors.violet.withOpacity(0.14)]),
            border: Border.all(color: QColors.cyan.withOpacity(0.35)),
            borderRadius: BorderRadius.circular(QRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Qamar+', textDirection: TextDirection.ltr, style: QText.display(size: 24, ar: false, color: QColors.textPrimary)),
              const SizedBox(height: 4),
              Text(t.plusSub, style: QText.body(size: 13, height: 20, color: QColors.textMid)),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: state.openSubscription,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      decoration: BoxDecoration(color: QColors.textPrimary, borderRadius: BorderRadius.circular(999)),
                      child: Text(t.plusCta, style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.cardNavy)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            // In the language's own digits, like the consent version above.
            '${t.brand} ${state.iso(QamarConfig.buildLabel)}',
            style: QText.number(size: 11, color: QColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The referral loop, from Me: three named invitations a quarter, numbered,
/// each carrying the friend's name. Members send; the free tier is told
/// where invitations come from.
class _InvitationsCard extends StatefulWidget {
  final AppState state;
  const _InvitationsCard({required this.state});

  @override
  State<_InvitationsCard> createState() => _InvitationsCardState();
}

class _InvitationsCardState extends State<_InvitationsCard> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isAr = state.isAr;
    final book = state.invitations;
    final member = state.plusActive;
    final left = state.invitationsLeft;

    String statusOf(Invitation i) => switch (i.status) {
          InvitationStatus.sent => isAr ? 'مبعوتة' : 'Sent',
          InvitationStatus.joined => isAr ? 'انضم' : 'Joined',
          InvitationStatus.subscribed => isAr ? 'اشترك' : 'Subscribed',
        };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(isAr ? 'دعواتك' : 'Your invitations',
                  style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
            ),
            if (member)
              Text(
                isAr ? 'باقي ${state.iso('$left')} من ${state.iso('${book.limit}')}' : '$left of ${book.limit} left',
                style: QText.number(size: 12, color: left > 0 ? QColors.cyan : QColors.textMuted),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            isAr
                ? '${state.iso('${book.limit}')} دعوات بالاسم كل تلات شهور. صاحبك بياخد أسبوعين قمر+ واسمك بيظهرله من أول لحظة. لما يدفع أول شهر: إنت ${state.suAmount(SuEconomy.invitationSender)} وهو ${state.suAmount(SuEconomy.invitationFriend)}.'
                : '${book.limit} named invitations a quarter. Your friend gets two weeks of Qamar+ and sees your name from the first moment. When they pay their first month: ${state.suAmount(SuEconomy.invitationSender)} for you, ${state.suAmount(SuEconomy.invitationFriend)} for them.',
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          if (!member) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.lock_outline, size: 14, color: QColors.gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(isAr ? 'الدعوات لأعضاء قمر+.' : 'Invitations are for Qamar+ members.',
                    style: QText.body(size: 12, color: QColors.gold)),
              ),
              QOutlineButton(label: isAr ? 'شوف قمر+' : 'See Qamar+', height: 34, color: QColors.gold, onTap: () => state.go(AppScreen.subscription)),
            ]),
          ] else ...[
            if (book.invitations.isNotEmpty) const SizedBox(height: 10),
            for (final i in book.invitations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Text(state.iso('${i.number}'), style: QText.number(size: 12, weight: FontWeight.w600, color: QColors.violetSoft)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(i.name, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textHigh), overflow: TextOverflow.ellipsis),
                  ),
                  Text(statusOf(i), style: QText.body(size: 12, color: i.status == InvitationStatus.sent ? QColors.textMuted : QColors.green)),
                  if (i.status == InvitationStatus.sent) ...[
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.ios_share, size: 16, color: QColors.textMid),
                      onPressed: () => state.shareInvitation(i),
                    ),
                  ],
                ]),
              ),
            if (left > 0 && state.isBacked) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: !state.invitationBusy,
                    style: QText.body(size: 14, color: QColors.textHigh),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: isAr ? 'اسم صاحبك' : 'Your friend’s name',
                      hintStyle: QText.body(size: 14, color: QColors.textMuted),
                      filled: true,
                      fillColor: QColors.cardMid,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                QOutlineButton(
                  label: isAr ? 'ادعي' : 'Invite',
                  height: 38,
                  color: QColors.cyan,
                  onTap: state.invitationBusy
                      ? null
                      : () async {
                          await state.issueInvitation(_name.text);
                          if (state.invitationNotice == null) _name.clear();
                        },
                ),
              ]),
            ],
            if (!state.isBacked) ...[
              const SizedBox(height: 10),
              Text(isAr ? 'اربط حسابك عشان تبعت دعوات.' : 'Link your account to send invitations.',
                  style: QText.body(size: 12, color: QColors.textMuted)),
            ],
          ],
          if (state.invitationNotice != null) ...[
            const SizedBox(height: 8),
            Text(state.invitationNotice!, style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
          ],
        ],
      ),
    );
  }
}

/// A client's side of the professional programme: the code a nutritionist or
/// coach gave them (O12). It puts the professional on the account, so their
/// share reaches them at the first payment with no code typed at checkout,
/// and starts the free trial while the account's one trial is unused. The
/// length is the server's; this card never states a number the server can
/// change, and the answer says the days actually given.
class _ProCodeCard extends StatefulWidget {
  final AppState state;
  const _ProCodeCard({required this.state});

  static const fieldKey = ValueKey('pro-code-field');
  static const useKey = ValueKey('pro-code-use');

  @override
  State<_ProCodeCard> createState() => _ProCodeCardState();
}

class _ProCodeCardState extends State<_ProCodeCard> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isAr = state.isAr;
    final who = state.proName;
    return Container(
      key: const ValueKey('pro-code-card'),
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isAr ? 'كود أخصائيك' : 'Your nutritionist’s code',
              style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          const SizedBox(height: 4),
          Text(
            who != null
                ? (isAr ? 'كود $who على حسابك. السعر زي ما هو، وبياخد نصيبه لما تشترك.' : '$who’s code is on your account. Your price is the same, and they get their share when you subscribe.')
                : (isAr
                    ? 'لو أخصائي تغذية أو مدرّب بعتك، اكتب الكود بتاعه. لو لسه ما خدتش التجربة المجانية، بتبدأ دلوقتي، وهو بياخد نصيبه لما تشترك. السعر مش بيتغير.'
                    : 'If a nutritionist or coach sent you, enter their code. If you have not had your free trial yet, it starts now, and they get their share when you subscribe. Your price does not change.'),
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          if (who == null) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  key: _ProCodeCard.fieldKey,
                  controller: _code,
                  // A code is Latin letters and digits: left to right in
                  // both languages, or Arabic turns "QMR…" into "…QMR".
                  textDirection: TextDirection.ltr,
                  enabled: !state.proBusy,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  style: QText.number(size: 15, color: QColors.textHigh),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'QMR…',
                    hintStyle: QText.body(size: 14, color: QColors.textMuted),
                    filled: true,
                    fillColor: QColors.cardMid,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              QOutlineButton(
                key: _ProCodeCard.useKey,
                label: isAr ? 'استخدم الكود' : 'Use the code',
                height: 44,
                color: QColors.cyan,
                onTap: state.proBusy
                    ? null
                    : () async {
                        await state.enterProCode(_code.text);
                        if (state.proName != null) _code.clear();
                      },
              ),
            ]),
          ],
          if (state.proNotice != null) ...[
            const SizedBox(height: 8),
            Text(state.proNotice!, style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
          ],
        ],
      ),
    );
  }
}

class _AffiliateCard extends StatelessWidget {
  final AppState state;
  const _AffiliateCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final wallet = state.affiliateWallet;
    final code = wallet.code;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isAr ? 'برنامج الأخصائيين' : 'Professional programme',
              style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          const SizedBox(height: 4),
          Text(
            (isAr
                    ? 'لو إنت أخصائي تغذية أو مدرّب: اديلي الكود ده لعميلك. يشترك بـ ٥٠٠ ج.م زي أي حد، وإنت يوصلك ١٠٠ ج.م كل شهر لمدة سنة. كاش بالجنيه، مش نقاط Su.'
                    : 'For nutritionists and coaches: give this code to a client. They subscribe at EGP 500 like anyone else, and you earn EGP 100 a month for a year. EGP cash, not Su Points.') +
                // The trial rides only on a code the operator has confirmed
                // (0069), and its length is the server's.
                (wallet.clientTrialDays <= 0
                    ? ''
                    : wallet.professional
                        ? (isAr
                            ? ' عميلك لما يكتبه في «حسابي» قبل ما يشترك بياخد ${state.iso('${wallet.clientTrialDays}')} يوم قمر+ ببلاش.'
                            : ' A client who enters it in Me before subscribing also gets ${wallet.clientTrialDays} days of Qamar+ free.')
                        : (isAr
                            ? ' لما قمر يتأكد إنك أخصائي أو مدرّب، عميلك اللي يكتبه في «حسابي» بياخد كمان ${state.iso('${wallet.clientTrialDays}')} يوم قمر+ ببلاش.'
                            : ' Once Qamar confirms you are a nutritionist or coach, a client who enters it in Me also gets ${wallet.clientTrialDays} days of Qamar+ free.')),
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // The code is set as a code; with none yet, the way to one is
              // an instruction, not a title-sized line pretending to be one.
              Expanded(
                child: code != null
                    ? Text(code, key: YouScreen.proCodeKey, style: QText.number(size: 17, weight: FontWeight.w600, color: QColors.textPrimary))
                    : Text(isAr ? 'اربط حسابك عشان يطلعلك كود' : 'Link an account to get a code',
                        key: YouScreen.proCodeKey, style: QText.body(size: 13, height: 20, color: QColors.textMuted)),
              ),
              if (code != null)
                QOutlineButton(
                  label: isAr ? 'نسخ' : 'Copy',
                  height: 36,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isAr
                ? '${formatEgp(wallet.balancePounds, ar: true, eastern: state.easternDigits)} متاح · ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: true, eastern: state.easternDigits)} مكتسب'
                : '${formatEgp(wallet.balancePounds, ar: false)} available · ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: false)} earned',
            style: QText.body(size: 12, color: QColors.textMuted),
          ),
          const SizedBox(height: 8),
          // Below the smallest payout there is nothing to send: the button
          // says so by being off (O11), where it used to look ready at EGP 0
          // and answer with a notice.
          QOutlineButton(
            label: isAr ? 'حوّل العمولة' : 'Redeem EGP',
            height: 36,
            color: QColors.gold,
            onTap: wallet.canRedeem ? state.requestAffiliatePayout : null,
          ),
          if (state.affiliateNotice != null) ...[
            const SizedBox(height: 8),
            Text(state.affiliateNotice!, style: QText.body(size: 12, height: 18, color: QColors.amberSoft)),
          ],
        ],
      ),
    );
  }
}

/// The professional's dashboard, as the blueprint bounds it: each client who
/// said yes, and their week as numbers. No meals, no photos, no weight.
class _ClientsCard extends StatelessWidget {
  final AppState state;
  const _ClientsCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final clients = state.proClients;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isAr ? 'عملاؤك، الأسبوع ده' : 'Your clients, this week',
              style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'اللي وافقوا على المشاركة بس. أيام التسجيل من ٧، وكام يوم منهم قريب من الهدف.'
                : 'Only those who said yes to sharing. Days logged out of 7, and how many of them landed near the target.',
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          const SizedBox(height: 10),
          for (final c in clients) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textHigh)),
                      const SizedBox(height: 2),
                      Text(
                        c.daysLogged == 0
                            ? (isAr ? 'مفيش تسجيل الأسبوع ده' : 'Nothing logged this week')
                            : c.targetKcal == null
                                ? (isAr
                                    ? 'متوسط ${state.iso('${c.avgKcal}')} سعر في اليوم'
                                    : 'avg ${c.avgKcal} kcal a day')
                                : (isAr
                                    ? 'متوسط ${state.iso('${c.avgKcal}')} من ${state.iso('${c.targetKcal}')} سعر · ${state.iso('${c.onTargetDays}')} يوم قريب من الهدف'
                                    : 'avg ${c.avgKcal} of ${c.targetKcal} kcal · ${c.onTargetDays} day${c.onTargetDays == 1 ? '' : 's'} near target'),
                        style: QText.body(size: 12, height: 17, color: QColors.textMuted),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isAr ? '${state.iso('${c.daysLogged}')}/${state.iso('7')}' : '${c.daysLogged}/7',
                    style: QText.number(size: 17, weight: FontWeight.w600, color: c.daysLogged >= 5 ? QColors.green : QColors.textPrimary),
                  ),
                ],
              ),
            ),
            if (c != clients.last) const Divider(height: 1, color: QColors.borderFaint),
          ],
        ],
      ),
    );
  }
}
