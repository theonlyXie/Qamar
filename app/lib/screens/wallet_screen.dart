import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  /// Found by tests: Level and lifetime earned, drawn only while the score
  /// is shown (O4).
  static const levelKey = ValueKey('wallet-level');
  static const lifetimeKey = ValueKey('wallet-lifetime');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, QLayout.pageTop, 20, QLayout.pageBottom),
      children: [
        Row(children: [
          QBackButton(onTap: state.back, isAr: isAr),
          const SizedBox(width: 6),
          Text(t.walletTitle, style: QText.display(size: 30, ar: QText.arabic(t.walletTitle), color: QColors.textPrimary)),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [QColors.cardMid, QColors.cardSlate]),
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
                  Text('${state.formatSu(state.suAvailable)}', style: QText.number(size: 34, weight: FontWeight.w600, color: QColors.goldPale)),
                ]),
                const Spacer(),
                // Lifetime earned is the number Level is made of and a
                // leaderboard would rank, so it keeps score: it goes with
                // "Points and streaks" (O4). The balance stays, because
                // spending needs it.
                if (state.showScore)
                  Column(key: WalletScreen.lifetimeKey, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(t.suLifetime, style: QText.body(size: 11, weight: FontWeight.w500, color: QColors.textMuted)),
                    Text('${state.formatSu(state.suLifetime)}', style: QText.number(size: 17, weight: FontWeight.w600, color: QColors.textMid)),
                  ]),
              ]),
              // Level lives here only (O9), and only while the score is shown
              // (O4): it buys nothing, and it is the leaderboard's number.
              if (state.showScore) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  key: WalletScreen.levelKey,
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(value: state.levelPct() / 100, minHeight: 6, backgroundColor: QColors.borderFaint, valueColor: const AlwaysStoppedAnimation(QColors.gold)),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Explainable(
                    id: 'level',
                    child: ExplainMark(child: Text(isAr ? 'المستوى ${state.iso('${state.level()}')}' : 'Level ${state.level()}', style: QText.body(size: 11, color: QColors.textMuted))),
                  ),
                  Text(t.levelNote, style: QText.body(size: 11, color: QColors.textMuted)),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          // The tabs take the whole height as their touch (O11); the gold
          // pill is drawn inside, as before.
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
                  Text(entry.when, style: QText.body(size: 11, color: QColors.textMuted)),
                ]),
                Text(entry.amount >= 0 ? '+${entry.amount}' : '${entry.amount}', style: QText.number(size: 14, weight: FontWeight.w600, color: entry.amount < 0 ? QColors.red : QColors.gold)),
              ]),
            ),
          ],
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: QDecor.card(color: QColors.cardSlate, border: QColors.borderFaint, radius: QRadii.lg),
          child: Text(t.walletTerms, style: QText.body(size: 12, height: 19, color: QColors.textMuted)),
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
    return QTapArea(
      onTap: onTap,
      builder: (context, pressed) => Container(
        height: QLayout.minTap,
        padding: const EdgeInsets.all(5),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // The chosen tab is the app's one lighter surface with a gold
            // edge; gold washed over navy read as warm grey, the only warm
            // surface in the app.
            color: active ? QColors.glassHigh : (pressed ? QColors.cardMid : Colors.transparent),
            border: Border.all(color: active ? QColors.gold.withValues(alpha: 0.45) : Colors.transparent),
            borderRadius: BorderRadius.circular(QRadii.pill),
          ),
          child: Text(label, style: QText.body(size: 13, weight: FontWeight.w600, color: active ? QColors.gold : QColors.textMuted)),
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
    final done = item.once && state.isRedeemed(item.id);
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
            Text('${state.formatSu(item.price)} Su', style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.gold)),
          ]),
          const SizedBox(height: 6),
          Text(isAr ? item.whatAr : item.whatEn, style: QText.body(size: 13, height: 20, color: QColors.textMuted)),
          const SizedBox(height: 4),
          Text(isAr ? item.limitAr : item.limitEn, style: QText.body(size: 11, height: 17, color: QColors.textMuted)),
          const SizedBox(height: 8),
          // What the balance would be is said only when it can be spent:
          // "after: 0" under a price the balance does not reach read as a
          // promise. Out of reach, the button is off (O11), not a tap that
          // quietly does nothing.
          Row(children: [
            if (afford) Text('${state.t.balanceAfter}: ${state.formatSu(after)}', style: QText.body(size: 11, color: QColors.textMuted)),
            const Spacer(),
            QOutlineButton(
              key: ValueKey('redeem-${item.id}'),
              label: done ? (isAr ? 'اتمت' : 'Redeemed') : state.t.spendCta,
              height: 36,
              color: QColors.gold,
              onTap: afford ? () => state.redeem(item) : null,
            ),
          ]),
        ],
      ),
    );
  }
}
