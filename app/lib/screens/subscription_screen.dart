import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

/// Qamar+ paywall.
///
/// Prices here are display copy only. The real figures come from the store at
/// runtime once `PaymentsService.loadProducts()` is wired up — App Store and
/// Play localise price and currency per storefront, and hardcoded prices are a
/// review rejection. Treat these as placeholders for layout.
typedef PlusTier = ({
  PlusPlan plan,
  String titleAr,
  String titleEn,
  String priceAr,
  String priceEn,
  String subAr,
  String subEn,
  String? badgeAr,
  String? badgeEn,
});

const _tiers = <PlusTier>[
  (
    plan: PlusPlan.monthly,
    titleAr: 'شهري',
    titleEn: 'Monthly',
    priceAr: '١٩٩ ج.م',
    priceEn: 'EGP 199',
    subAr: 'كل شهر · تقدر تلغي في أي وقت',
    subEn: 'per month · cancel any time',
    badgeAr: null,
    badgeEn: null,
  ),
  (
    plan: PlusPlan.annual,
    titleAr: 'سنوي',
    titleEn: 'Annual',
    priceAr: '١٫٥٩٠ ج.م',
    priceEn: 'EGP 1,590',
    subAr: 'يعني ١٣٢ ج.م في الشهر',
    subEn: 'works out to EGP 132 a month',
    badgeAr: 'وفّر ٣٣٪',
    badgeEn: 'Save 33%',
  ),
];

typedef PlusFeature = ({String ar, String en, bool inFree});

const _features = <PlusFeature>[
  (ar: 'تسجيل الوجبات بالكتابة', en: 'Log meals by typing', inFree: true),
  (ar: 'هدف يومي وخطة أساسية', en: 'Daily target and a basic plan', inFree: true),
  (ar: 'نقاط Su والمهام اليومية', en: 'Su Points and daily quests', inFree: true),
  (ar: 'تحليل الوجبة بالصورة من غير حد', en: 'Unlimited photo meal analysis', inFree: false),
  (ar: 'خطة أسبوعية كاملة بالمقادير', en: 'Full weekly plan with portions', inFree: false),
  (ar: 'أسئلة غير محدودة لقمر', en: 'Unlimited questions to Qamar', inFree: false),
  (ar: 'تقارير تقدم أعمق', en: 'Deeper progress reports', inFree: false),
  (ar: 'أولوية في المزايا الجديدة', en: 'Early access to new features', inFree: false),
];

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;

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
        const SizedBox(height: 20),

        for (final tier in _tiers) ...[
          _TierCard(state: state, tier: tier),
          const SizedBox(height: 10),
        ],

        const SizedBox(height: 8),
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
              : (isAr ? 'ابدأ Qamar+' : 'Start Qamar+'),
          onTap: state.startPlusPurchase,
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: state.restorePlusPurchases,
            child: Text(isAr ? 'استرجاع مشترياتي' : 'Restore purchases',
                style: QText.body(size: 13, weight: FontWeight.w500, color: QColors.textMuted)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isAr
              ? 'الاشتراك بيتجدد تلقائياً لحد ما تلغيه من إعدادات المتجر. نقاط Su مش بتتباع ومش بتتشحن بفلوس — بتتكسب بس.'
              : 'Subscriptions renew automatically until cancelled in your store settings. Su Points are never sold or topped up with money — they are only earned.',
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

class _TierCard extends StatelessWidget {
  final AppState state;
  final PlusTier tier;
  const _TierCard({required this.state, required this.tier});

  @override
  Widget build(BuildContext context) {
    final isAr = state.isAr;
    final selected = state.plusPlan == tier.plan;
    final badge = isAr ? tier.badgeAr : tier.badgeEn;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(QRadii.xl),
        onTap: () => state.selectPlusPlan(tier.plan),
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
                        Text(isAr ? tier.titleAr : tier.titleEn,
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
                    Text(isAr ? tier.subAr : tier.subEn,
                        style: QText.body(size: 12, color: QColors.textMuted)),
                  ],
                ),
              ),
              Text(isAr ? tier.priceAr : tier.priceEn,
                  style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

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
