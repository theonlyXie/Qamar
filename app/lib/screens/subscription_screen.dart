import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/billing.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

/// Qamar+ paywall.
///
/// Prices here match the Paymob catalog (EGP). The charge itself is stamped
/// server-side; this screen only names the plan and, optionally, a promo code.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final quote = state.displayPlusQuote;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 160),
      children: [
        Row(
          children: [
            QRoundIconButton(icon: Icons.close, onTap: () => state.go(AppScreen.you)),
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
            child: Text('Qamar+', style: QText.display(size: 34, height: 42, color: Colors.white)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isAr
              ? 'قمر بيشتغل معاك من غير اشتراك: خطة اليوم، تلات صور وتلات أسئلة كل يوم، والكتابة والصوت بلا حد. Qamar+ بيفتح خطة بكرة وصور وأسئلة أكتر.'
              : 'Qamar works without a subscription: today’s plan, three photos and three questions a day, and unlimited typing and speaking. Qamar+ opens tomorrow’s plan and more photos and questions.',
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
            isAr
                ? '٥٠٠ ج.م في الشهر — أقل من زيارة واحدة لأخصائي. مفيش سنة ومفيش خصومات؛ سعر واحد، والإلغاء بضغطة من «حسابي».'
                : 'EGP 500 a month — less than one visit to a nutritionist. No annual tier and no discounts; one price, and cancel in one tap from Me.',
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
          quote.pricingReason == 'affiliate'
              ? (isAr
                  ? 'الكود شغال. السعر زي ما هو، وأخصائيك بيتابع خطتك وبياخد نصيب من الاشتراك لمدة سنة.'
                  : 'Code applied. Your price is unchanged; your nutritionist follows your plan and earns a share of this subscription for a year.')
              : (isAr
                  ? 'لو أخصائي أو مدرّب بعتك، اكتب الكود هنا. السعر مش بيتغير — الكود بيربط خطتك بيه وبيديه نصيب من الاشتراك.'
                  : 'If a nutritionist or coach sent you, enter their code. The price does not change — the code links your plan to them and pays them a share.'),
          style: QText.body(size: 12, height: 18, color: QColors.textFaint),
        ),
        if (quote.promoError != null) ...[
          const SizedBox(height: 8),
          Text(quote.promoError!, style: QText.body(size: 12, color: QColors.amber)),
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
            label: isAr ? 'جرّب قمر+ سبعة أيام ببلاش' : 'Try Qamar+ free for seven days',
            onTap: () { state.startPlusTrial(); },
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'من غير بطاقة. بعد السبعة أيام بترجع Lite لوحدك — مفيش تجديد تلقائي.'
                : 'No card. After seven days you are simply back on Lite — nothing renews on its own.',
            textAlign: TextAlign.center,
            style: QText.body(size: 11, height: 17, color: QColors.textFaint),
          ),
          const SizedBox(height: 10),
        ],
        QPrimaryButton(
          label: state.plusActive && !state.plusIsTrial
              ? (isAr ? 'إدارة الاشتراك' : 'Manage subscription')
              : (isAr
                  ? 'ابدأ ${formatEgp(quote.amountPounds, ar: true)}'
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
          isAr
              ? 'الدفع في مصر عن طريق Paymob بالجنيه: فيزا، ماستركارد، Meeza، أو محفظة فودافون/أورانج. قمر+ بيتفعل بعد ما Paymob يأكد التحويل. نقاط Su مش بتتباع ومش بتتشحن بفلوس — بتتكسب بس. عمولة الأفلييت كاش بالجنيه، مش نقاط.'
              : 'Egypt billing is Paymob, in EGP: Visa, Mastercard, Meeza, or Vodafone/Orange Cash. Qamar+ turns on after Paymob confirms the transfer. Su Points are never sold or topped up with money — they are only earned. Affiliate commission is EGP cash, not Su.',
          textAlign: TextAlign.center,
          style: QText.body(size: 11, height: 17, color: QColors.textFaint),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            QLegalLink(label: isAr ? 'الشروط' : 'Terms', url: QamarConfig.termsUrl),
            Text('  ·  ', style: QText.body(size: 11, color: QColors.textFaint)),
            QLegalLink(label: isAr ? 'الخصوصية' : 'Privacy', url: QamarConfig.privacyUrl),
            Text('  ·  ', style: QText.body(size: 11, color: QColors.textFaint)),
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
      onChanged: (v) => context.read<AppState>().setPlusPromoCode(v),
      style: QText.number(size: 15, color: QColors.textPrimary),
      decoration: InputDecoration(
        hintText: isAr ? 'QMR…' : 'QMR…',
        hintStyle: QText.body(size: 14, color: QColors.textFaint),
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
    final sub = state.plusIsTrial && until != null
        ? (isAr
            ? 'الأسبوع المجاني شغال · لحد ${state.iso('${until.day}/${until.month}')}'
            : 'Free week on · until ${until.day}/${until.month}')
        : quote.pricingReason == 'affiliate'
            ? (isAr ? '٣٠ يوم · بكود أخصائيك' : '30 days · with your nutritionist’s code')
            : (isAr ? '٣٠ يوم · إلغاء بضغطة' : '30 days · cancel in one tap');

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
                  formatEgp(quote.listPounds, ar: isAr),
                  style: QText.number(size: 11, color: QColors.textFaint).copyWith(
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                formatEgp(quote.amountPounds, ar: isAr),
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
  (ar: 'تسجيل الوجبات بالكتابة أو الصوت، بلا حد', en: 'Log meals by typing or speaking, unlimited', inFree: true),
  (ar: 'خطة اليوم بأطباق حقيقية', en: 'Today’s plan in real dishes', inFree: true),
  (ar: 'تصوير الوجبة — ٣ في اليوم (٣٠ مع Qamar+)', en: 'Photograph a meal — 3 a day (30 with Qamar+)', inFree: true),
  (ar: 'أسئلة لقمر — ٣ في اليوم (٥٠ مع Qamar+)', en: 'Questions to Qamar — 3 a day (50 with Qamar+)', inFree: true),
  (ar: 'صورة زيادة من المحفظة بنقاط Su', en: 'An extra photo from the wallet with Su Points', inFree: true),
  (ar: 'نقاط Su والمهام اليومية', en: 'Su Points and daily quests', inFree: true),
  (ar: 'خطة بكرة، مكتوبة بالليل', en: 'Tomorrow’s plan, written overnight', inFree: false),
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
                    style: QText.body(size: 10, weight: FontWeight.w500, color: QColors.textFaint, letterSpacing: 0.5)),
              ),
              SizedBox(
                width: 52,
                child: Text(isAr ? 'مجاني' : 'Free',
                    textAlign: TextAlign.center,
                    style: QText.body(size: 10, weight: FontWeight.w500, color: QColors.textFaint)),
              ),
              SizedBox(
                width: 52,
                child: Text('Qamar+',
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
                      color: f.inFree ? QColors.green : QColors.textFaint,
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
