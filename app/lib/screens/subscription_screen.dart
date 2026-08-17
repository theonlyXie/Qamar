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
              ? 'قمر بيشتغل معاك من غير اشتراك. Qamar+ بيشيل الحدود ويفتح الخطة الكاملة والتحليل بالصورة.'
              : 'Qamar works without a subscription. Qamar+ removes the limits and unlocks the full plan and photo analysis.',
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
                ? 'السعر ٥٠٠ ج.م في الشهر. أول اشتراك خصم ٣٠٪ (٣٥٠ ج.م). السنة بـ ٢٤٩ ج.م — نفس سعر باقة ٣ شهور، ودي العرض اللي بنشجّع عليه.'
                : 'List is EGP 500 a month. Your first subscription is 30% off (EGP 350). One year is EGP 249 — the same cash as the 3-month pack, and the plan we push.',
            style: QText.body(size: 13, height: 20, color: QColors.textHigh),
          ),
        ),
        const SizedBox(height: 16),

        for (final plan in const [PlusPlan.annual, PlusPlan.quarterly, PlusPlan.monthly]) ...[
          _TierCard(state: state, plan: plan),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 4),
        Text(
          isAr ? 'كود عرض أو صديق' : 'A friend’s code or a promo',
          style: QText.body(size: 12, weight: FontWeight.w600, color: QColors.textMuted),
        ),
        const SizedBox(height: 6),
        const _PromoField(),
        const SizedBox(height: 6),
        Text(
          quote.pricingReason == 'affiliate'
              ? (isAr
                  ? 'بالكود ده الشهر بـ ٢٩٩ ج.م. صاحبك ياخد ٥٠ ج.م كاش في محفظة العمولة (مش نقاط Su)، وصافي قمر ٢٤٩ ج.م.'
                  : 'With this code the month is EGP 299. Your friend earns EGP 50 cash in their affiliate wallet (not Su Points). Qamar’s net is EGP 249.')
              : (isAr
                  ? 'لو حد بعتلك كود، اكتبه هنا: الشهر يبقى ٢٩٩ ج.م، وهو ياخد ٥٠ ج.م كاش نبعتهاله من طرفنا.'
                  : 'If someone sent you a code, enter it here: monthly Plus is EGP 299, and they earn EGP 50 cash we send from our end.'),
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

        QPrimaryButton(
          label: state.plusActive
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

  PlusQuote _quote() {
    if (state.plusPlan == plan) return state.displayPlusQuote;
    return PlusPricing.quote(plan: plan.name, firstPurchase: state.plusFirstPurchase);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final selected = state.plusPlan == plan;
    final quote = _quote();
    final title = switch (plan) {
      PlusPlan.annual => (isAr ? 'سنة' : '1 year'),
      PlusPlan.quarterly => (isAr ? '٣ شهور' : '3 months'),
      PlusPlan.monthly => (isAr ? 'شهري' : 'Monthly'),
    };
    final sub = switch (plan) {
      PlusPlan.annual => isAr
          ? 'خصم ٥٠٪ · نفس سعر ٣ شهور، و١٢ شهر'
          : '50% off · same cash as 3 months, for 12',
      PlusPlan.quarterly => isAr ? '٩٠ يوم · نفس سعر السنة نقداً' : '90 days · same cash price as a year',
      PlusPlan.monthly => quote.pricingReason == 'affiliate'
          ? (isAr ? 'بكود الصديق · ٣٠ يوم' : 'with a friend’s code · 30 days')
          : quote.pricingReason == 'first_user'
              ? (isAr ? 'أول اشتراك · خصم ٣٠٪' : 'first subscription · 30% off')
              : (isAr ? '٣٠ يوم' : '30 days'),
    };
    final badge = switch (plan) {
      PlusPlan.annual => isAr ? 'الأفضل' : 'Best value',
      PlusPlan.quarterly => null,
      PlusPlan.monthly => quote.discounted ? (isAr ? 'عرض' : 'Offer') : null,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.xl),
        onTap: () => state.selectPlusPlan(plan),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep])
                : null,
            color: selected ? null : QColors.cardNavy,
            border: Border.all(
              color: selected ? QColors.violet : QColors.borderSoft,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(QRadii.xl),
            boxShadow: selected
                ? [BoxShadow(color: QColors.violet.withValues(alpha: 0.22), blurRadius: 26)]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? QColors.violet : QColors.textFaint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title,
                            style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary)),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: QColors.green.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(badge,
                                style: QText.body(size: 10, weight: FontWeight.w600, color: QColors.green)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(sub, style: QText.body(size: 12, color: QColors.textMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
        ),
      ),
    );
  }
}

typedef PlusFeature = ({String ar, String en, bool inFree});

const _features = <PlusFeature>[
  (ar: 'تسجيل الوجبات بالكتابة', en: 'Log meals by typing', inFree: true),
  (ar: 'هدف يومي وخطة أساسية', en: 'Daily target and a basic plan', inFree: true),
  (ar: '٥ استخدامات لقمر في اليوم — سؤال، طبق، أو خطة', en: '5 Qamar uses a day — chat, a plate, or the plan', inFree: true),
  (ar: 'نقاط Su والمهام اليومية', en: 'Su Points and daily quests', inFree: true),
  (ar: 'استخدام زيادة من المحفظة بنقاط Su', en: 'Buy extra uses from the wallet with Su Points', inFree: true),
  (ar: 'خطة أسبوعية كاملة بالمقادير', en: 'Full weekly plan with portions', inFree: false),
  (ar: 'تقارير تقدم أعمق', en: 'Deeper progress reports', inFree: false),
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
