import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/billing.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

/// Qamar+ paywall.
///
/// Prices here match the Paymob catalog (EGP). The charge itself is stamped
/// server-side; this screen only names the plan and, optionally, a promo code.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  static const leadKey = ValueKey('paywall-lead');
  static const bannerKey = ValueKey('paywall-banner');
  static const paymentKey = ValueKey('paywall-payment');
  static const codeLineKey = ValueKey('paywall-code-line');

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
            ? 'سجّل ${state.iso('${earned.needed}')} يوم من أول ${state.iso('${earned.windowDays}')} يوم بعد ما تشترك، والشهر اللي بعده علينا.'
            : 'Log ${earned.needed} of your first ${earned.windowDays} days after you subscribe and the next month is on us.',
      isAr ? 'ومفيش حاجة بتتجدد لوحدها.' : 'Nothing renews on its own.',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final quote = state.displayPlusQuote;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, QLayout.pageBottom),
      children: [
        Row(
          children: [
            QBackButton(onTap: state.back, isAr: isAr),
            const Spacer(),
            if (state.plusActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: QColors.green.withValues(alpha: 0.14),
                  border: Border.all(color: QColors.green.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(isAr ? 'مفعّل' : 'Active',
                    style: QText.body(size: 11, weight: FontWeight.w600, color: QColors.green)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Center(child: const QamarMoon(size: 84)),
        const SizedBox(height: 14),
        Center(
          child: ShaderMask(
            shaderCallback: (r) => QColors.brandGradient.createShader(r),
            child: Text('Qamar+', textDirection: TextDirection.ltr, style: QText.display(size: 34, height: 42, color: QColors.textPrimary)),
          ),
        ),
        const SizedBox(height: 6),
        // What Qamar+ is for, first: the answer to "what do I eat?" The
        // night job writes tomorrow's plan for every member at 22:00 Cairo.
        Text(
          isAr ? 'قمر+ بيقولك تاكل إيه بكرة: بيكتبلك الخطة بالليل، بأكل مصري.' : 'Qamar+ tells you what to eat tomorrow: it writes the plan at night, in Egyptian dishes.',
          key: SubscriptionScreen.leadKey,
          textAlign: TextAlign.center,
          style: QText.body(size: 15, height: 23, weight: FontWeight.w600, color: QColors.textHigh),
        ),
        const SizedBox(height: 6),
        Text(
          isAr
              ? 'ومن غيره قمر شغال برضه: خطة النهارده، تلات صور وتلات أسئلة كل يوم، والكتابة والصوت بلا حد.'
              : 'Without it Qamar still works: today’s plan, three photos and three questions a day, and unlimited typing and speaking.',
          textAlign: TextAlign.center,
          style: QText.body(size: 14, height: 22, color: QColors.textMuted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: QColors.violet.withValues(alpha: 0.10),
            border: Border.all(color: QColors.violet.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(QRadii.xl),
          ),
          child: Text(
            priceBanner(state, quote),
            key: SubscriptionScreen.bannerKey,
            style: QText.body(size: 13, height: 20, color: QColors.textHigh),
          ),
        ),
        const SizedBox(height: 16),

        _TierCard(state: state, plan: PlusPlan.monthly),
        const SizedBox(height: 10),

        const SizedBox(height: 4),
        Text(
          isAr ? 'كود الأخصائي أو المدرّب' : 'Your nutritionist’s or coach’s code',
          style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.textMuted),
        ),
        const SizedBox(height: 6),
        const _PromoField(),
        const SizedBox(height: 6),
        Text(
          key: SubscriptionScreen.codeLineKey,
          // A typed code that is not the one paid says why, before anything
          // that would say it is (the billing function's rule: twelve months,
          // one professional per client).
          promoNoticeLine(isAr, quote.promoNotice) ??
          (quote.pricingReason == 'affiliate'
              ? (isAr
                  ? 'الكود شغال. السعر زي ما هو، وأخصائيك بيتابع خطتك وبياخد نصيب من الاشتراك لمدة سنة.'
                  : 'Code applied. Your price is unchanged; your nutritionist follows your plan and earns a share of this subscription for a year.')
              : (isAr
                  ? 'لو أخصائي أو مدرّب بعتك، اكتب الكود هنا. السعر مش بيتغير — الكود بيربط خطتك بيه وبيديه نصيب من الاشتراك.'
                  : 'If a nutritionist or coach sent you, enter their code. The price does not change — the code links your plan to them and pays them a share.')),
          style: QText.body(size: 12, height: 18, color: QColors.textMuted),
        ),
        if (quote.promoError != null) ...[
          const SizedBox(height: 8),
          Text(quote.promoError!, style: QText.body(size: 12, color: QColors.amber)),
        ],
        // The code's second half: the client's yes to the professional seeing
        // the week as numbers. Off until turned on; also on Me.
        if (quote.pricingReason == 'affiliate' || state.plusPromoCode.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                isAr
                    ? 'شاركه التزامي الأسبوعي (أيام التسجيل والمتوسط مقابل الهدف، بس)'
                    : 'Share my weekly adherence with them (days logged and the average against my target, nothing else)',
                style: QText.body(size: 12, height: 17, color: QColors.textMuted),
              ),
            ),
            Switch.adaptive(
              value: state.adherenceShare,
              activeThumbColor: QColors.violet,
              onChanged: (v) => state.setAdherenceShare(v),
            ),
          ]),
        ],
        if (quote.promoNote != null) ...[
          const SizedBox(height: 8),
          Text(quote.promoNote!, style: QText.body(size: 12, height: 18, color: QColors.textMuted)),
        ],

        const SizedBox(height: 16),
        _FeatureTable(state: state),
        const SizedBox(height: 18),

        if (state.plusNotice != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: QColors.amber.withValues(alpha: 0.10),
              border: Border.all(color: QColors.amber.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(QRadii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: QColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(state.plusNotice!,
                      style: QText.body(size: 12, height: 19, color: QColors.amberSoft)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        if (!state.plusActive && state.plusTrialEligible) ...[
          QPrimaryButton(
            label: isAr
                ? 'ابدأ أسبوعك المجاني: ${state.iso('${AppState.trialOfferDays}')} أيام من قمر كامل'
                : 'Start your free week: ${AppState.trialOfferDays} days of the full Qamar',
            onTap: () { state.startPlusTrial(placement: 'paywall'); },
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'من غير بطاقة، ومفيش حاجة بتتجدد لوحدها: بعد ${state.iso('${AppState.trialOfferDays}')} أيام بترجع لقمر المجاني.'
                : 'No card, and nothing renews on its own: after ${AppState.trialOfferDays} days you are simply back on the free Qamar.',
            textAlign: TextAlign.center,
            style: QText.body(size: 11, height: 17, color: QColors.textMuted),
          ),
          const SizedBox(height: 10),
        ],
        QPrimaryButton(
          label: state.plusActive && !state.plusIsTrial
              ? (isAr ? 'شهرك' : 'Your month')
              : (isAr
                  ? 'ابدأ ${formatEgp(quote.amountPounds, ar: true, eastern: state.easternDigits)}'
                  : 'Start Qamar+ — ${formatEgp(quote.amountPounds, ar: false)}'),
          onTap: () { state.startPlusPurchase(); },
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () { state.restorePlusPurchases(); },
            child: Text(isAr ? 'تأكيد الاشتراك' : 'Confirm subscription',
                style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${paymentLine(isAr, quote.paymentMethods)} ${isAr ? 'نقاط Su مش بتتباع ومش بتتشحن بفلوس — بتتكسب بس. عمولة الأفلييت كاش بالجنيه، مش نقاط.' : 'Su Points are never sold or topped up with money — they are only earned. Affiliate commission is EGP cash, not Su.'}',
          key: SubscriptionScreen.paymentKey,
          textAlign: TextAlign.center,
          style: QText.body(size: 11, height: 17, color: QColors.textMuted),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            QLegalLink(label: isAr ? 'الشروط' : 'Terms', url: QamarConfig.termsUrl),
            Text('  ·  ', style: QText.body(size: 11, color: QColors.textMuted)),
            QLegalLink(label: isAr ? 'الخصوصية' : 'Privacy', url: QamarConfig.privacyUrl),
            Text('  ·  ', style: QText.body(size: 11, color: QColors.textMuted)),
            QLegalLink(label: isAr ? 'الدعم' : 'Support', url: QamarConfig.supportUrl),
          ],
        ),
      ],
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
    final isAr = context.watch<AppState>().isAr;
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      // A code is Latin: left to right in both languages ("QMR…", not "…QMR").
      textDirection: TextDirection.ltr,
      onChanged: (v) => context.read<AppState>().setPlusPromoCode(v),
      style: QText.number(size: 15, color: QColors.textPrimary),
      decoration: InputDecoration(
        hintText: isAr ? 'QMR…' : 'QMR…',
        hintStyle: QText.body(size: 14, color: QColors.textMuted),
        filled: true,
        fillColor: QColors.cardNavy,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.borderSoft)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: QColors.violet)),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final AppState state;
  final PlusPlan plan;
  const _TierCard({required this.state, required this.plan});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final quote = state.displayPlusQuote;
    final title = isAr ? 'شهري' : 'Monthly';
    final until = state.plusUntil?.toLocal();
    final earned = state.earnedMonth;
    final sub = state.plusIsTrial && until != null
        ? (isAr
            ? 'الأسبوع المجاني شغال · لحد ${state.iso('${until.day}/${until.month}')}'
            : 'Free week on · until ${until.day}/${until.month}')
        : state.plusIsEarned && until != null
            ? (isAr
                ? 'شهر علينا · لحد ${state.iso('${until.day}/${until.month}')}'
                : 'A month on us · until ${until.day}/${until.month}')
            : state.plusActive && earned.inProgress
                ? (isAr
                    ? 'شهر علينا: ${state.iso('${earned.loggedDays}')} من ${state.iso('${earned.needed}')} يوم مسجّلين'
                    : 'A month on us: ${earned.loggedDays} of ${earned.needed} days logged')
                : quote.pricingReason == 'affiliate'
                    ? (isAr ? '٣٠ يوم · بكود أخصائيك' : '30 days · with your nutritionist’s code')
                    : (isAr ? '٣٠ يوم · مفيش حاجة بتتجدد لوحدها' : '30 days · nothing renews on its own');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]),
        border: Border.all(color: QColors.violet, width: 1.6),
        borderRadius: BorderRadius.circular(QRadii.xl),
        boxShadow: [BoxShadow(color: QColors.violet.withValues(alpha: 0.22), blurRadius: 26)],
      ),
      child: Row(
        children: [
          const Icon(Icons.radio_button_checked, size: 20, color: QColors.violet),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                const SizedBox(height: 2),
                Text(sub, style: QText.body(size: 12, color: QColors.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // A campaign code is the one thing that can lower the price; when
              // it has, show what it came down from.
              if (quote.discounted)
                Text(
                  formatEgp(quote.listPounds, ar: isAr, eastern: state.easternDigits),
                  style: QText.number(size: 11, color: QColors.textMuted).copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                formatEgp(quote.amountPounds, ar: isAr, eastern: state.easternDigits),
                style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textPrimary),
              ),
            ],
          ),
        ],
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
  (ar: 'تصوير الوجبة — ٣ في اليوم (٣٠ مع قمر+)', en: 'Photograph a meal — 3 a day (30 with Qamar+)', inFree: true),
  (ar: 'أسئلة لقمر — ٣ في اليوم (٥٠ مع قمر+)', en: 'Questions to Qamar — 3 a day (50 with Qamar+)', inFree: true),
  (ar: 'صورة زيادة من المحفظة بنقاط Su', en: 'An extra photo from the wallet with Su Points', inFree: true),
  (ar: 'نقاط Su والمهام اليومية', en: 'Su Points and daily quests', inFree: true),
  (ar: 'المراجعة الأسبوعية الكاملة والمشاركة', en: 'The full weekly review, shareable', inFree: false),
  (ar: 'أولوية في المزايا الجديدة', en: 'Early access to new features', inFree: false),
];

class _FeatureTable extends StatelessWidget {
  final AppState state;
  const _FeatureTable({required this.state});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: QDecor.card(color: QColors.cardNavy, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(isAr ? 'اللي بتاخده' : 'What you get',
                    style: QText.body(size: 10, weight: FontWeight.w500, color: QColors.textMuted, letterSpacing: 0.5)),
              ),
              SizedBox(
                width: 52,
                child: Text(isAr ? 'مجاني' : 'Free',
                    textAlign: TextAlign.center,
                    style: QText.body(size: 10, weight: FontWeight.w500, color: QColors.textMuted)),
              ),
              SizedBox(
                width: 52,
                child: Text('Qamar+', textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: QText.body(size: 10, weight: FontWeight.w600, color: QColors.violetSoft)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final f in _features) ...[
            const Divider(color: QColors.borderFaint, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text(isAr ? f.ar : f.en,
                        style: QText.body(size: 13, height: 18, color: QColors.textHigh)),
                  ),
                  SizedBox(
                    width: 52,
                    child: Icon(
                      f.inFree ? Icons.check : Icons.remove,
                      size: 16,
                      color: f.inFree ? QColors.green : QColors.textMuted,
                    ),
                  ),
                  const SizedBox(
                    width: 52,
                    child: Icon(Icons.check, size: 16, color: QColors.violetSoft),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
