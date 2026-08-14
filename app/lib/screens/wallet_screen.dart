import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 160),
      children: [
        Row(children: [
          QRoundIconButton(icon: Icons.arrow_back, onTap: () => state.go(AppScreen.today)),
          const SizedBox(width: 12),
          Text(t.walletTitle, style: QText.display(size: 28, height: 34, color: const Color(0xFFF5F7FF))),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF151B33), Color(0xFF0F1526)]),
            border: Border.all(color: QColors.gold.withOpacity(0.32)),
            borderRadius: BorderRadius.circular(QRadii.xxxl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const SuCoinIcon(size: 40),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.suAvailable, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
                  Text('${state.suAvailable}', style: QText.number(size: 34, weight: FontWeight.w600, color: const Color(0xFFF2E4C6))),
                ]),
                const Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(t.suLifetime, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
                  Text('${state.suLifetime}', style: QText.number(size: 18, weight: FontWeight.w600, color: QColors.textMid)),
                ]),
              ]),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: state.levelPct() / 100, minHeight: 6, backgroundColor: QColors.borderFaint, valueColor: const AlwaysStoppedAnimation(QColors.gold)),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(isAr ? 'المستوى ${state.level()}' : 'Level ${state.level()}', style: QText.body(size: 11, color: QColors.textFaint)),
                Text(t.levelNote, style: QText.body(size: 11, color: QColors.textFaint)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: QColors.cardSlate, border: Border.all(color: QColors.borderFaint), borderRadius: BorderRadius.circular(999)),
          child: Row(children: [
            Expanded(child: _WalletTab(label: t.spendTab, active: state.walletTab == WalletTab.spend, onTap: state.showSpend)),
            Expanded(child: _WalletTab(label: t.historyTab, active: state.walletTab == WalletTab.history, onTap: state.showHistory)),
          ]),
        ),
        const SizedBox(height: 14),
        if (state.walletTab == WalletTab.spend)
          for (final item in kSpendCatalog) ...[
            _SpendCard(item: item),
            const SizedBox(height: 12),
          ]
        else if (state.ledger().isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
            child: Text(
              state.isAr
                  ? 'مفيش حركات لسه. كل نقطة بتتكسب هتظهر هنا بسببها.'
                  : 'No entries yet. Every point you earn shows up here with its reason.',
              style: QText.body(size: 13, height: 20, color: QColors.textMuted),
            ),
          )
        else
          for (final entry in state.ledger()) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.lg),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.label, style: QText.body(size: 14, weight: FontWeight.w500, color: QColors.textHigh)),
                  Text(entry.when, style: QText.body(size: 11, color: QColors.textFaint)),
                ]),
                Text(entry.amount >= 0 ? '+${entry.amount}' : '${entry.amount}', style: QText.number(size: 14, weight: FontWeight.w600, color: entry.amount < 0 ? QColors.red : QColors.gold)),
              ]),
            ),
          ],
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: QDecor.card(color: QColors.cardSlate, border: QColors.borderFaint, radius: QRadii.lg),
          child: Text(t.walletTerms, style: QText.body(size: 12, height: 19, color: QColors.textFaint)),
        ),
      ],
    );
  }
}

class _WalletTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _WalletTab({required this.label, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: active ? QColors.gold.withOpacity(0.16) : Colors.transparent, borderRadius: BorderRadius.circular(999)),
          child: Text(label, style: QText.body(size: 13, weight: FontWeight.w600, color: active ? QColors.gold : QColors.textFaint)),
        ),
      ),
    );
  }
}

class _SpendCard extends StatelessWidget {
  final SpendItemDef item;
  const _SpendCard({required this.item});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final done = state.isRedeemed(item.id);
    final afford = state.suAvailable >= item.price && !done;
    final after = state.suAvailable - item.price < 0 ? 0 : state.suAvailable - item.price;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: QDecor.card(color: QColors.cardDeep, border: QColors.borderFaint, radius: QRadii.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(isAr ? item.nameAr : item.nameEn, style: QText.body(size: 15, weight: FontWeight.w600, color: QColors.textPrimary))),
            Text('${item.price} Su', style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.gold)),
          ]),
          const SizedBox(height: 6),
          Text(isAr ? item.whatAr : item.whatEn, style: QText.body(size: 13, height: 20, color: QColors.textMuted)),
          const SizedBox(height: 4),
          Text(isAr ? item.limitAr : item.limitEn, style: QText.body(size: 11, height: 17, color: QColors.textFaint)),
          const SizedBox(height: 8),
          Row(children: [
            Text('${state.t.balanceAfter}: $after', style: QText.body(size: 11, color: QColors.textMuted)),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => state.redeem(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(border: Border.all(color: afford ? QColors.gold.withOpacity(0.45) : QColors.borderSoft), borderRadius: BorderRadius.circular(999)),
                  child: Text(done ? (isAr ? 'اتمت' : 'Redeemed') : state.t.spendCta, style: QText.body(size: 12, weight: FontWeight.w600, color: afford ? QColors.gold : QColors.textFaint)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
