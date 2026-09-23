import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/trial_words.dart';
import '../l10n/words.dart';
import '../models/billing.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

/// Qamar+ and its paywall: what it is for, the price and the one thing to do,
/// then what is in each tier, and the fine print. Calm and short, and every
/// clause true for the person reading it.
///
/// Prices here match the Paymob catalog (EGP). The charge itself is stamped
/// server-side; this screen only names the plan and, optionally, a promo code.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  static const leadKey = ValueKey('paywall-lead');
  static const withoutKey = ValueKey('paywall-without');
  static const bannerKey = ValueKey('paywall-banner');
  static const paymentKey = ValueKey('paywall-payment');
  static const codeLineKey = ValueKey('paywall-code-line');

  /// The screen's one primary, and the way to a code.
  static const primaryKey = ValueKey('paywall-primary');
  static const buyKey = ValueKey('paywall-buy');
  static const codeToggleKey = ValueKey('paywall-code-toggle');

  /// The billing function's reason a typed professional's code is not the
  /// one paid, in the person's language; null when there is none.
  static String? promoNoticeLine(bool isAr, String? notice) => switch (notice) {
        'referral_ended' => isAr
            ? 'السنة بتاعة أخصائيك على اشتراكك خلصت، فمفيش نصيب بيتدفع له دلوقتي. السعر زي ما هو.'
            : 'Your nutritionist’s twelve months on your subscription have ended, so no share is paid to them now. Your price is the same.',
        'other_professional' => isAr
            // "Account", not "subscription": before a first payment the other
            // professional is a claim on the account (0069), and there is no
            // subscription yet. The same word as Me's refusal.
            ? 'فيه أخصائي تاني على حسابك، وهو اللي بياخد النصيب لحد ما سنته تخلص. لو عايز تغيّر، كلّم الدعم. السعر زي ما هو.'
            : 'Another nutritionist is already on your account, and their share stays with them for their twelve months. To change, write to support. Your price is the same.',
        'unchecked' => isAr
            ? 'مقدرتش أتأكد من كود الأخصائي دلوقتي، فمفيش نصيب على الدفعة دي. السعر زي ما هو.'
            : 'I could not check the nutritionist’s code just now, so no share is attached to this payment. Your price is the same.',
        _ => null,
      };

  /// How to pay, naming only the rails the billing function says checkout
  /// can take (its labelled Paymob integrations). With none stated it names
  /// none, rather than promise Vodafone Cash or Meeza an account cannot take.
  static String paymentLine(bool isAr, List<String> methods) {
    final names = [
      if (methods.contains('card')) isAr ? 'فيزا أو ماستركارد' : 'Visa or Mastercard',
      if (methods.contains('meeza')) isAr ? 'كارت ميزة' : 'a Meeza card',
      if (methods.contains('wallet')) isAr ? 'فودافون كاش أو أي محفظة موبايل' : 'Vodafone Cash or another mobile wallet',
    ];
    final join = names.length < 2
        ? names.join()
        : '${names.sublist(0, names.length - 1).join(isAr ? '، ' : ', ')}${isAr ? '، أو ' : ', or '}${names.last}';
    final how = names.isEmpty
        ? (isAr ? 'الدفع بالجنيه عن طريق Paymob.' : 'You pay in EGP through Paymob.')
        : (isAr ? 'الدفع بالجنيه عن طريق Paymob: $join.' : 'You pay in EGP through Paymob: $join.');
    return '$how ${isAr ? 'قمر+ بيتفعل أول ما Paymob يأكد الدفع.' : 'Qamar+ turns on once Paymob confirms the payment.'}';
  }

  /// The price, as O14 agreed it: priced against a nutritionist, not against
  /// apps, and every clause true for the person reading it.
  /// - "About one visit": a visit costs EGP 350–800, a video consultation
  ///   starts at 300; 500 is in that range, not below it.
  /// - "Same price for everyone" goes whenever a campaign code has lowered
  ///   this quote.
  /// - The earned month is stated in the server's numbers, and only once the
  ///   server has stated them and the month can still be earned.
  /// - "Nothing renews on its own": a payment only extends the month
  ///   (qamar_apply_paid_order), and there is nothing to cancel.
  static String priceBanner(AppState state, PlusQuote quote) {
    final isAr = state.isAr;
    final price = formatEgp(quote.listPounds, ar: isAr, eastern: state.easternDigits);
    final earned = state.earnedMonth;
    return [
      isAr
          ? '$price في الشهر — في حدود تمن كشف واحد عند أخصائي تغذية، وقمر معاك في كل وجبة.'
          : '$price a month — about one nutritionist visit, with Qamar at every meal.',
      if (!quote.discounted) isAr ? 'نفس السعر للكل.' : 'Same price for everyone.',
      if (earned.onOffer)
        isAr
            ? 'سجّل ${Counted.day.of(earned.needed, ar: true, iso: state.iso)} من أول ${Counted.day.of(earned.windowDays, ar: true, iso: state.iso)} بعد ما تشترك، والشهر اللي بعده علينا.'
            : 'Log ${earned.needed} of your first ${Counted.day.of(earned.windowDays, ar: false, iso: state.iso)} after you subscribe and the next month is on us.',
      isAr ? 'ومفيش حاجة بتتجدد لوحدها.' : 'Nothing renews on its own.',
    ].join(' ');
  }

  /// The button that pays for a month, at the quoted amount.
  static String buyLabel(AppState state, PlusQuote quote) {
    final isAr = state.isAr;
    final price = formatEgp(quote.amountPounds, ar: isAr, eastern: state.easternDigits);
    return isAr ? 'ادفع شهر بـ $price' : 'Pay $price for a month';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final quote = state.displayPlusQuote;
    // The one primary: the free week while it is on offer, otherwise a
    // month, and nothing while a paid month is running (there is nothing to
    // renew and nothing to cancel).
    final trialOffer = !state.plusActive && state.plusTrialEligible;
    final canBuy = !state.plusActive || state.plusIsTrial;

    return ListView(
      padding: const EdgeInsets.fromLTRB(QSpace.page, QLayout.pageTop, QSpace.page, QSpace.xxxl),
      children: [
        Row(children: [
          QBackButton(onTap: state.back, isAr: isAr),
          const Spacer(),
          if (state.plusActive) const _ActiveChip(),
        ]),

        // The lockup: the moon, the name and the one sentence it is for, centred.
        const SizedBox(height: QSpace.sm),
        const Center(child: ExcludeSemantics(child: QamarMoon(size: 72))),
        const SizedBox(height: QSpace.lg),
        Center(child: Text('Qamar+', textDirection: TextDirection.ltr, style: QText.display(size: 34, ar: false))),
        const SizedBox(height: QSpace.sm),
        // What Qamar+ is for, first: the answer to "what do I eat?" The night
        // job writes tomorrow's plan for every member at 22:00 Cairo.
        QBalancedText(
          isAr ? 'قمر+ بيقولك تاكل إيه بكرة: بيكتبلك الخطة بالليل، بأكل مصري.' : 'Qamar+ tells you what to eat tomorrow: it writes the plan at night, in Egyptian dishes.',
          textKey: SubscriptionScreen.leadKey,
          style: QText.body(size: 17, height: 24, weight: FontWeight.w600, color: QColors.ink),
        ),
        const SizedBox(height: QSpace.md),
        // What follows reads from the start, like the rest of the screen.
        Text(
          isAr
              ? 'ومن غيره قمر شغال برضه: خطة النهارده، تلات صور وتلات أسئلة كل يوم، والكتابة والصوت بلا حد.'
              : 'Without it Qamar still works: today’s plan, three photos and three questions a day, and unlimited typing and speaking.',
          key: SubscriptionScreen.withoutKey,
          style: QText.body(size: 15, color: QColors.inkSecondary),
        ),
        const SizedBox(height: QSpace.xxl),

        _PlanCard(state: state, quote: quote, buyHere: trialOffer),
        const SizedBox(height: QSpace.lg),

        if (state.plusNotice != null) ...[
          QStateLine(line: state.plusNotice!, icon: QIcons.info),
          const SizedBox(height: QSpace.lg),
        ],

        if (trialOffer) ...[
          QPrimaryButton(
            key: SubscriptionScreen.primaryKey,
            label: TrialWords.paywallButton(ar: isAr),
            onTap: () => state.startPlusTrial(placement: 'paywall'),
          ),
          const SizedBox(height: QSpace.sm),
          Text(
            TrialWords.paywallRule(AppState.trialOfferDays, ar: isAr, iso: state.iso),
            textAlign: TextAlign.center,
            style: QText.body(size: 13, height: 18, color: QColors.inkTertiary),
          ),
        ] else if (canBuy)
          QPrimaryButton(key: SubscriptionScreen.primaryKey, label: SubscriptionScreen.buyLabel(state, quote), onTap: state.startPlusPurchase),

        const SizedBox(height: QSpace.xxl),
        _FeatureTable(state: state),
        // A code rides on a payment: while a paid month runs there is none.
        if (canBuy) ...[
          const SizedBox(height: QSpace.lg),
          _CodeSection(state: state, quote: quote),
        ],

        const SizedBox(height: QSpace.lg),
        Center(
          child: QTapArea(
            onTap: state.restorePlusPurchases,
            builder: (context, pressed) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: QSpace.md),
              child: Text(isAr ? 'استرجع الاشتراك' : 'Restore purchase',
                  style: QText.body(size: 15, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary)),
            ),
          ),
        ),
        const SizedBox(height: QSpace.sm),
        Text(
          '${paymentLine(isAr, quote.paymentMethods)} ${isAr ? 'نقاط Su مش بتتباع ومش بتتشحن بفلوس — بتتكسب بس. نصيب الأخصائي بيتدفع كاش بالجنيه، مش نقاط.' : 'Su Points are never sold or topped up with money — they are only earned. A nutritionist’s share is paid in EGP cash, not Su.'}',
          key: SubscriptionScreen.paymentKey,
          textAlign: TextAlign.center,
          style: QText.body(size: 12, height: 17, color: QColors.inkTertiary),
        ),
        const SizedBox(height: QSpace.sm),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            QLegalLink(label: isAr ? 'الشروط' : 'Terms', url: QamarConfig.termsUrl, size: 13),
            const _Dot(),
            QLegalLink(label: isAr ? 'الخصوصية' : 'Privacy', url: QamarConfig.privacyUrl, size: 13),
            const _Dot(),
            QLegalLink(label: isAr ? 'الدعم' : 'Support', url: QamarConfig.supportUrl, size: 13),
          ],
        ),
      ],
    );
  }
}

/// The mark between two links, with room either side of it.
class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: QSpace.xs),
        child: Text('·', style: QText.body(size: 13, color: QColors.inkTertiary)),
      );
}

/// "Active", beside the back control while Qamar+ is on: a check and the
/// word, inside the strong edge.
class _ActiveChip extends StatelessWidget {
  const _ActiveChip();

  @override
  Widget build(BuildContext context) {
    final isAr = Directionality.of(context) == TextDirection.rtl;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: QSpace.md, vertical: 6),
      decoration: QDecor.capsule(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(QIcons.check, size: 15, color: QColors.ink),
        const SizedBox(width: 6),
        Text(isAr ? 'مفعّل' : 'Active', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.ink)),
      ]),
    );
  }
}

/// The one plan: its name and price, the line under them, the agreed banner,
/// and — while the free week is the primary — the way to pay for a month.
/// One plan, so no radio: a single option is not a choice.
class _PlanCard extends StatelessWidget {
  final AppState state;
  final PlusQuote quote;
  final bool buyHere;
  const _PlanCard({required this.state, required this.quote, required this.buyHere});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final until = state.plusUntil?.toLocal();
    final earned = state.earnedMonth;
    final day = until == null ? '' : '${until.day}/${until.month}';
    final sub = state.plusIsTrial && until != null
        ? (isAr ? 'الأسبوع المجاني شغال · لحد ${state.iso(day)}' : 'Free week on · until $day')
        : state.plusIsEarned && until != null
            ? (isAr ? 'شهر علينا · لحد ${state.iso(day)}' : 'A month on us · until $day')
            : state.plusActive && earned.inProgress
                ? (isAr
                    ? 'شهر علينا: ${state.iso('${earned.loggedDays}')} من ${Counted.day.of(earned.needed, ar: true, iso: state.iso)} مسجّلين'
                    : 'A month on us: ${earned.loggedDays} of ${Counted.day.of(earned.needed, ar: false, iso: state.iso)} logged')
                : state.plusActive && until != null
                    ? (isAr ? 'شهرك شغال · لحد ${state.iso(day)}' : 'Your month · until $day')
                    : quote.pricingReason == 'affiliate'
                        ? (isAr ? '٣٠ يوم · بكود أخصائيك' : '30 days · with your nutritionist’s code')
                        : (isAr ? '٣٠ يوم · مفيش حاجة بتتجدد لوحدها' : '30 days · nothing renews on its own');

    return Container(
      padding: const EdgeInsets.all(QSpace.xl),
      decoration: QDecor.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text(isAr ? 'شهري' : 'Monthly', style: QText.body(size: 17, weight: FontWeight.w600, color: QColors.ink))),
            // A campaign code is the one thing that can lower the price; when
            // it has, show what it came down from.
            if (quote.discounted) ...[
              Text(
                formatEgp(quote.listPounds, ar: isAr, eastern: state.easternDigits),
                style: QText.number(size: 15, color: QColors.inkTertiary, ar: isAr).copyWith(decoration: TextDecoration.lineThrough, decorationColor: QColors.inkTertiary),
              ),
              const SizedBox(width: QSpace.sm),
            ],
            Text(formatEgp(quote.amountPounds, ar: isAr, eastern: state.easternDigits), style: QText.number(size: 20, weight: FontWeight.w600, ar: isAr)),
          ]),
          const SizedBox(height: 2),
          Text(sub, style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
          const SizedBox(height: QSpace.lg),
          const Divider(height: 1, thickness: 1, color: QColors.hairline),
          const SizedBox(height: QSpace.lg),
          Text(SubscriptionScreen.priceBanner(state, quote), key: SubscriptionScreen.bannerKey, style: QText.body(size: 15, color: QColors.inkSecondary)),
          if (buyHere) ...[
            const SizedBox(height: QSpace.lg),
            QOutlineButton(key: SubscriptionScreen.buyKey, label: SubscriptionScreen.buyLabel(state, quote), height: 44, onTap: state.startPlusPurchase),
          ],
        ],
      ),
    );
  }
}

/// A professional's code, which most people do not have: behind one quiet
/// line until it is wanted, and open whenever there is something in it. A
/// typed code that is not the one paid says why, before anything that would
/// say it is (the billing function's rule: twelve months, one professional
/// per client); its second half is the client's yes to the professional
/// seeing the week as numbers, off until turned on, and also on Me.
class _CodeSection extends StatefulWidget {
  final AppState state;
  final PlusQuote quote;
  const _CodeSection({required this.state, required this.quote});

  @override
  State<_CodeSection> createState() => _CodeSectionState();
}

class _CodeSectionState extends State<_CodeSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final quote = widget.quote;
    final isAr = state.isAr;
    final typed = state.plusPromoCode.trim().isNotEmpty;
    final open = _open || typed || quote.pricingReason == 'affiliate' || quote.promoNotice != null || quote.promoError != null;
    final still = MediaQuery.disableAnimationsOf(context);

    return AnimatedSize(
      duration: still ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: !open
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: QTapArea(
                key: SubscriptionScreen.codeToggleKey,
                onTap: () => setState(() => _open = true),
                builder: (context, pressed) => Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(QIcons.add, size: 17, color: pressed ? QColors.ink : QColors.inkSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(isAr ? 'معاك كود أخصائي أو مدرّب؟' : 'Have a nutritionist’s or coach’s code?',
                        style: QText.body(size: 15, weight: FontWeight.w500, color: pressed ? QColors.ink : QColors.inkSecondary)),
                  ),
                ]),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: QSpace.lg, bottom: QSpace.sm),
                  child: Text(QText.eyebrowText(isAr ? 'كود الأخصائي أو المدرّب' : 'Your nutritionist’s or coach’s code', ar: isAr), style: QText.eyebrow(ar: isAr)),
                ),
                const _PromoField(),
                const SizedBox(height: QSpace.sm),
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: QSpace.lg),
                  child: Text(
                    key: SubscriptionScreen.codeLineKey,
                    SubscriptionScreen.promoNoticeLine(isAr, quote.promoNotice) ??
                        (quote.pricingReason == 'affiliate'
                            ? (isAr
                                ? 'الكود شغال. السعر زي ما هو، وأخصائيك بيتابع خطتك وبياخد نصيب من الاشتراك لمدة سنة.'
                                : 'Code applied. Your price is unchanged; your nutritionist follows your plan and earns a share of this subscription for a year.')
                            : (isAr
                                ? 'لو أخصائي أو مدرّب بعتك، اكتب الكود هنا. السعر مش بيتغير — الكود بيربط خطتك بيه وبيديه نصيب من الاشتراك.'
                                : 'If a nutritionist or coach sent you, enter their code. The price does not change — the code links your plan to them and pays them a share.')),
                    style: QText.body(size: 13, height: 18, color: QColors.inkTertiary),
                  ),
                ),
                if (quote.promoError != null) ...[
                  const SizedBox(height: QSpace.sm),
                  QStateLine(line: quote.promoError!, icon: QIcons.warning),
                ],
                if (quote.pricingReason == 'affiliate' || typed) ...[
                  const SizedBox(height: QSpace.md),
                  _ShareSwitch(state: state),
                ],
                if (quote.promoNote != null) ...[
                  const SizedBox(height: QSpace.sm),
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: QSpace.lg),
                    child: Text(quote.promoNote!, style: QText.body(size: 13, height: 18, color: QColors.inkTertiary)),
                  ),
                ],
              ],
            ),
    );
  }
}

/// The client's yes to the professional seeing the week as numbers: a row
/// with its switch, the whole row the control, in Me's own words.
class _ShareSwitch extends StatelessWidget {
  final AppState state;
  const _ShareSwitch({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    return MergeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () => state.setAdherenceShare(!state.adherenceShare),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(QSpace.lg, QSpace.md, QSpace.md, QSpace.md),
          decoration: QDecor.card(),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isAr ? 'شارك أسبوعي معاه' : 'Share my week with them', style: QText.body(size: 17, color: QColors.ink)),
                const SizedBox(height: 2),
                Text(
                  isAr ? 'أيام التسجيل والمتوسط مقابل الهدف، ومفيش حاجة غيرهم.' : 'Days logged and the average against your target, nothing else.',
                  style: QText.body(size: 13, height: 18, color: QColors.inkTertiary),
                ),
              ]),
            ),
            const SizedBox(width: QSpace.md),
            Switch.adaptive(value: state.adherenceShare, onChanged: (v) => state.setAdherenceShare(v)),
          ]),
        ),
      ),
    );
  }
}

class _PromoField extends StatefulWidget {
  const _PromoField();

  @override
  State<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends State<_PromoField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<AppState>().plusPromoCode);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const shape = BorderRadius.all(Radius.circular(QRadii.control));
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      // A code is Latin: left to right in both languages ("QMR…", not "…QMR").
      textDirection: TextDirection.ltr,
      textInputAction: TextInputAction.done,
      onChanged: (v) => context.read<AppState>().setPlusPromoCode(v),
      style: QText.number(size: 17, color: QColors.ink),
      decoration: InputDecoration(
        hintText: 'QMR…',
        hintTextDirection: TextDirection.ltr,
        hintStyle: QText.body(size: 17, color: QColors.inkTertiary),
        filled: true,
        fillColor: QColors.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: 15),
        border: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide.none),
        enabledBorder: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide.none),
        focusedBorder: const OutlineInputBorder(borderRadius: shape, borderSide: BorderSide(color: QColors.hairlineStrong, width: 1.5)),
      ),
    );
  }
}

typedef PlusFeature = ({String ar, String en, bool inFree});

const _features = <PlusFeature>[
  // First, what Qamar+ is for: the answer to "what do I eat tomorrow?"
  (ar: 'خطة بكرة، مكتوبة بالليل', en: 'Tomorrow’s plan, written overnight', inFree: false),
  (ar: 'تسجيل الوجبات بالكتابة أو الصوت، بلا حد', en: 'Log meals by typing or speaking, unlimited', inFree: true),
  (ar: 'خطة اليوم بأطباق حقيقية', en: 'Today’s plan in real dishes', inFree: true),
  (ar: 'صور الوجبات — ٣ في اليوم (٣٠ مع قمر+)', en: 'Meal photos — 3 a day (30 with Qamar+)', inFree: true),
  (ar: 'أسئلة لقمر — ٣ في اليوم (٥٠ مع قمر+)', en: 'Questions — 3 a day (50 with Qamar+)', inFree: true),
  (ar: 'صور زيادة بنقاط Su', en: 'Extra photos with Su Points', inFree: true),
  (ar: 'نقاط Su والمهام اليومية', en: 'Su Points and daily quests', inFree: true),
  (ar: 'المراجعة الأسبوعية الكاملة والمشاركة', en: 'The full weekly review, shareable', inFree: false),
  (ar: 'أولوية في المزايا الجديدة', en: 'Early access to new features', inFree: false),
];

/// What each tier has, row by row: a check where it is included and a dash
/// where it is not, in the ink (the shape says which, not a shade), and a
/// screen reader told the same in words.
class _FeatureTable extends StatelessWidget {
  final AppState state;
  const _FeatureTable({required this.state});

  static const _column = 60.0;

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final free = isAr ? 'مجاني' : 'Free';
    String says(bool on) => on ? (isAr ? 'موجود' : 'included') : (isAr ? 'مش موجود' : 'not included');

    Widget mark(bool on) => SizedBox(
          width: _column,
          child: Icon(on ? QIcons.check : QIcons.remove, size: 18, color: on ? QColors.ink : QColors.inkTertiary),
        );

    return Container(
      decoration: QDecor.card(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(QSpace.lg, QSpace.md, QSpace.sm, QSpace.md),
            child: ExcludeSemantics(
              child: Row(children: [
                Expanded(child: Text(QText.eyebrowText(isAr ? 'اللي بتاخده' : 'What you get', ar: isAr), style: QText.eyebrow(ar: isAr))),
                SizedBox(width: _column, child: Text(QText.eyebrowText(free, ar: isAr), textAlign: TextAlign.center, style: QText.eyebrow(ar: isAr))),
                SizedBox(
                  width: _column,
                  child: Text('Qamar+', textDirection: TextDirection.ltr, textAlign: TextAlign.center, style: QText.eyebrow(ar: true, color: QColors.inkSecondary)),
                ),
              ]),
            ),
          ),
          for (final f in _features) ...[
            const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairline),
            MergeSemantics(
              child: Semantics(
                label: '${isAr ? f.ar : f.en}. $free: ${says(f.inFree)}. Qamar+: ${says(true)}.',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(QSpace.lg, QSpace.md, QSpace.sm, QSpace.md),
                    child: Row(children: [
                      Expanded(child: Text(isAr ? f.ar : f.en, style: QText.body(size: 15, color: QColors.ink))),
                      mark(f.inFree),
                      mark(true),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
