import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

    final rows = <(String, String)>[
      (isAr ? 'الهدف والسعرات' : 'Target and calories', '${tg.kcal} kcal'),
      (isAr ? 'ما يجب تجنبه' : 'What to avoid', state.profile.prefs.isNotEmpty ? '${state.profile.prefs.length}' : (isAr ? 'مفيش' : 'None')),
      (isAr ? 'ذاكرة قمر' : 'Qamar memory', isAr ? '٦ عناصر' : '6 items'),
      (isAr ? 'محفظة نقاط Su' : 'Su Points wallet', state.iso('${state.suAvailable}')),
      (isAr ? 'موافقة تحسين الخدمة' : 'Service-improvement consent', state.improve ? (isAr ? 'مفعّلة' : 'On') : (isAr ? 'موقوفة' : 'Off')),
      (isAr ? 'الخصوصية والموافقات' : 'Privacy and consents', isAr ? 'الإصدار ١.١' : 'v1.1'),
      (isAr ? 'تصدير أو حذف بياناتي' : 'Export or delete my data', ''),
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
              Text(t.guestAccount, style: QText.body(size: 12, color: QColors.textMuted)),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
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
                    onTap: () {},
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
                          : (isAr ? 'الخطة الكاملة والتحليل بالصورة من غير حد' : 'The full plan and unlimited photo analysis'),
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
                  isAr ? '${state.iso('${state.suAvailable}')} متاح · ${state.iso('${state.suLifetime}')} مكتسب' : '${state.suAvailable} available · ${state.suLifetime} lifetime',
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
                    onTap: () {},
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
