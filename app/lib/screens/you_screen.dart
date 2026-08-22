import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/billing.dart';
import '../services/config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/moon.dart';

class YouScreen extends StatelessWidget {
  const YouScreen({super.key});

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
      (isAr ? 'الهدف والسعرات' : 'Target and calories', '${tg.kcal} kcal'),
      (isAr ? 'ما يجب تجنبه' : 'What to avoid', state.profile.prefs.isNotEmpty ? '${state.profile.prefs.length}' : (isAr ? 'مفيش' : 'None')),
      (
        isAr ? 'ذاكرة قمر' : 'Qamar memory',
        remembered == 0
            ? (isAr ? 'فاضية' : 'Empty')
            : (isAr ? '${state.iso('$remembered')} عناصر' : '$remembered items')
      ),
      (isAr ? 'محفظة نقاط Su' : 'Su Points wallet', state.iso(state.formatSu(state.suAvailable))),
      (isAr ? 'موافقة تحسين الخدمة' : 'Service-improvement consent', state.improve ? (isAr ? 'مفعّلة' : 'On') : (isAr ? 'موقوفة' : 'Off')),
      (isAr ? 'الموافقات' : 'Consents', isAr ? 'الإصدار ١.١' : 'v1.1'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Text(t.you, style: QText.display(size: 30, height: 38, color: const Color(0xFFF5F7FF))),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: QDecor.card(gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardDeep]), border: QColors.borderStrong, radius: QRadii.xl),
          child: Row(children: [
            const QamarMoon(size: 48),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(state.profile.name.isNotEmpty ? state.profile.name : (isAr ? 'يا صاحبي' : 'friend'), style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.textPrimary)),
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
                Text(t.saveProgress, style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFE9ECFF))),
                const SizedBox(height: 4),
                Text(t.saveProgressSub, style: QText.body(size: 13, height: 20, color: QColors.textMid)),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: state.openLinkAccount,
                      child: Ink(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: const BoxDecoration(gradient: QColors.brandGradient, borderRadius: BorderRadius.all(Radius.circular(999))),
                        child: Text(t.linkAccount, style: QText.body(size: 13, weight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ),
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
                      Text('Qamar+', style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFE9ECFF))),
                      if (state.plusActive) ...[
                        const SizedBox(width: 8),
                        Text(isAr ? 'مفعّل' : 'Active',
                            style: QText.body(size: 11, weight: FontWeight.w600, color: QColors.green)),
                      ],
                    ]),
                    Text(
                      state.plusActive
                          ? (isAr ? 'شكراً إنك معانا' : 'Thanks for supporting Qamar')
                          : (isAr ? 'تحليل الوجبة بالصورة، وخطة أعمق' : 'Photo meal analysis and a deeper plan'),
                      style: QText.body(size: 12, height: 18, color: QColors.textMuted),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right, size: 20, color: QColors.textFaint),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _AffiliateCard(state: state),
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
                    ? 'سيري: «Ask Qamar» أو «Log a meal with Qamar». تسجيل الوجبة من الاختصار مجاناً ومش بيخصم استخدام. سؤال قمر بيستخدم من الخمس استخدامات في اليوم.'
                    : 'Siri: “Ask Qamar” or “Log a meal with Qamar”. Logging a meal from a shortcut is free and does not spend a use. Asking Qamar still uses the daily five.',
                style: QText.body(size: 12, height: 18, color: QColors.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (state.studyModeEnabled) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(QRadii.xl),
              onTap: state.openStudyMode,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
                child: Row(children: [
                  const Icon(Icons.menu_book_rounded, color: QColors.moonlight, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(isAr ? 'الأوضاع' : 'Modes',
                          style: QText.body(size: 12, color: QColors.textMuted)),
                      Text(isAr ? 'وضع الدراسة' : 'Study Mode',
                          style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
                      Text(
                        isAr ? 'خطة مذاكرة · جلسات · نفس محفظة Su' : 'Study plan · sessions · same Su wallet',
                        style: QText.body(size: 12, height: 18, color: QColors.textFaint),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, size: 20, color: QColors.textFaint),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: QColors.gold.withOpacity(0.08), border: Border.all(color: QColors.gold.withOpacity(0.32)), borderRadius: BorderRadius.circular(QRadii.xl)),
          child: Row(children: [
            const SuCoinIcon(size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.walletTitle, style: QText.body(size: 15, weight: FontWeight.w600, color: const Color(0xFFF2E4C6))),
                Text(
                  isAr ? '${state.iso(state.formatSu(state.suAvailable))} متاح · ${state.iso(state.formatSu(state.suLifetime))} مكتسب' : '${state.formatSu(state.suAvailable)} available · ${state.formatSu(state.suLifetime)} lifetime',
                  style: QText.body(size: 12, color: const Color(0xFFB9A57C)),
                ),
              ]),
            ),
            QOutlineButton(label: t.spendTab, onTap: state.openWallet, height: 36, color: QColors.gold),
          ]),
        ),
        const SizedBox(height: 14),
        for (final r in rows) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(r.$1, style: QText.body(size: 15, weight: FontWeight.w500, color: QColors.textHigh)),
              Text(r.$2, style: QText.body(size: 13, color: QColors.textFaint)),
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
              Text('  ·  ', style: QText.body(size: 12, color: QColors.textFaint)),
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
              Text('Qamar+', style: QText.display(size: 24, height: 30, color: const Color(0xFFF5F7FF))),
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
                      decoration: BoxDecoration(color: const Color(0xFFF5F7FF), borderRadius: BorderRadius.circular(999)),
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
            'Qamar ${QamarConfig.buildLabel}',
            style: QText.number(size: 11, color: QColors.textFaint),
          ),
        ),
      ],
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
          Text(isAr ? 'عمولة الأفلييت' : 'Affiliate wallet',
              style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textHigh)),
          const SizedBox(height: 4),
          Text(
            isAr
                ? 'ابعتهالكود لحد: يشترك بـ ٢٩٩ ج.م، وإنت يوصلك ٥٠ ج.م كاش نبعتهالك من طرفنا. مش نقاط Su.'
                : 'Share your code: they subscribe at EGP 299, and you earn EGP 50 cash we send from our end. Not Su Points.',
            style: QText.body(size: 12, height: 18, color: QColors.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  code ?? (isAr ? 'اربط حسابك عشان يطلعلك كود' : 'Link an account to get a code'),
                  style: QText.number(size: 16, weight: FontWeight.w600, color: QColors.textPrimary),
                ),
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
                ? '${formatEgp(wallet.balancePounds, ar: true)} متاح · ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: true)} مكتسب'
                : '${formatEgp(wallet.balancePounds, ar: false)} available · ${formatEgp(wallet.lifetimeEarnedCents ~/ 100, ar: false)} earned',
            style: QText.body(size: 12, color: QColors.textFaint),
          ),
          const SizedBox(height: 8),
          QOutlineButton(
            label: isAr ? 'حوّل العمولة' : 'Redeem EGP',
            height: 36,
            color: QColors.gold,
            onTap: state.requestAffiliatePayout,
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
