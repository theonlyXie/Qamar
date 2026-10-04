import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/meal.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/icons.dart';
import '../theme/layout.dart';
import '../theme/text_styles.dart';
import '../widgets/common.dart';
import '../widgets/hero_number.dart';
import '../widgets/explain.dart';
import '../widgets/kit.dart';

/// The Su Points wallet: the balance is the page's one hero, a large figure
/// on the kit's lime; under it the two tabs as the kit's segmented control,
/// Spend and History, and under them plain rows.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  /// Found by tests: Level and lifetime earned, drawn only while the score
  /// is shown (O4).
  static const levelKey = ValueKey('wallet-level');
  static const lifetimeKey = ValueKey('wallet-lifetime');
  static const availableLabelKey = ValueKey('wallet-available-label');
  static const lifetimeLabelKey = ValueKey('wallet-lifetime-label');

  /// The balance's dot figure.
  static const balanceKey = ValueKey('wallet-balance');

  /// The two tabs, and the white segment under the chosen one.
  static Key tabKey(WalletTab tab) => ValueKey('wallet-tab-${tab.name}');
  static const thumbKey = ValueKey('wallet-tab-thumb');

  /// The terms at the foot of both tabs, whatever "Points and streaks" is
  /// set to: they are where the wallet says Su are earned, never sold.
  static const termsKey = ValueKey('wallet-terms');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final t = state.t;
    final isAr = state.isAr;
    final balance = state.formatSu(state.suAvailable);

    return ListView(
      padding: const EdgeInsets.fromLTRB(QSpace.page, QLayout.pageTop, QSpace.page, QLayout.pageBottom),
      children: [
        QPageTitle(title: t.walletTitle, isAr: QText.arabic(t.walletTitle), back: state.back),
        const SizedBox(height: QSpace.lg),

        // The hero: what there is to spend, large, with the coin as its
        // unit. Lifetime earned and Level keep score, so they go with "Points
        // and streaks" (O4); the balance stays, because spending needs it.
        PastelCard(
          color: QColors.lime,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The two labels share a baseline; a long figure or a large
              // text size wraps the second rather than pushing it off the card.
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(QText.eyebrowText(t.suAvailable, ar: isAr), key: WalletScreen.availableLabelKey, style: QText.eyebrow(ar: isAr, color: QColors.onPastel)),
                if (state.showScore) ...[
                  const SizedBox(width: QSpace.md),
                  Flexible(
                    child: Row(
                      key: WalletScreen.lifetimeKey,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(child: Text(QText.eyebrowText(t.suLifetime, ar: isAr), key: WalletScreen.lifetimeLabelKey, textAlign: TextAlign.end, style: QText.eyebrow(ar: isAr, color: QColors.onPastelSecondary))),
                        const SizedBox(width: QSpace.sm),
                        Text(state.formatSu(state.suLifetime), style: QText.number(size: 13, weight: FontWeight.w600, color: QColors.onPastel)),
                      ],
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: QSpace.lg),
              Row(children: [
                const SuCoinIcon(size: 28, color: QColors.onPastel),
                const SizedBox(width: QSpace.md),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: HeroNumber(balance, key: WalletScreen.balanceKey, color: QColors.onPastel, semanticsLabel: '$balance ${t.suName}, ${t.suAvailable}'),
                  ),
                ),
              ]),
              // Level lives here only (O9), and only while the score is shown
              // (O4): it buys nothing, and it is the leaderboard's number.
              if (state.showScore) ...[
                const SizedBox(height: QSpace.lg),
                QBar(key: WalletScreen.levelKey, value: state.levelPct() / 100, onPastel: true),
                const SizedBox(height: QSpace.sm),
                Row(children: [
                  Explainable(
                    id: 'level',
                    child: ExplainMark(child: Text(isAr ? 'المستوى ${state.iso('${state.level()}')}' : 'Level ${state.level()}', style: QText.body(size: 13, weight: FontWeight.w600, color: QColors.onPastel))),
                  ),
                  const SizedBox(width: QSpace.md),
                  Expanded(child: Text(t.levelNote, textAlign: TextAlign.end, style: QText.body(size: 13, color: QColors.onPastelSecondary))),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: QSpace.xxl),

        _Tabs(
          tabs: [(WalletTab.spend, t.spendTab), (WalletTab.history, t.historyTab)],
          chosen: state.walletTab,
          onChoose: (tab) => tab == WalletTab.spend ? state.showSpend() : state.showHistory(),
        ),
        const SizedBox(height: QSpace.lg),

        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
          child: KeyedSubtree(
            key: ValueKey(state.walletTab),
            child: state.walletTab == WalletTab.spend ? const _SpendList() : const _History(),
          ),
        ),
        const SizedBox(height: QSpace.md),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: QSpace.lg),
          child: Text(t.walletTerms, key: WalletScreen.termsKey, style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
        ),
      ],
    );
  }
}

/// Two tabs as the kit's segmented control: a white track, and under the
/// chosen tab a burgundy segment with white words, which slides to the other
/// when it is chosen (a state change: 220 ms, ease-out; with reduce motion it
/// simply moves). Each tab is a whole touch and says it is selected.
class _Tabs extends StatelessWidget {
  final List<(WalletTab, String)> tabs;
  final WalletTab chosen;
  final ValueChanged<WalletTab> onChoose;
  const _Tabs({required this.tabs, required this.chosen, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final index = tabs.indexWhere((t) => t.$1 == chosen);
    const track = 44.0;
    const inset = 4.0;
    // The track is drawn 40 tall in a band a whole touch tall (O11): each
    // tab takes the full 48, the capsule and its white segment sit inside.
    return SizedBox(
      height: QLayout.minTap,
      child: Stack(children: [
        Positioned.fill(
          child: Center(
            child: Container(height: track, decoration: QDecor.segmentTrack),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: SizedBox(
              height: track,
              child: Padding(
                padding: const EdgeInsets.all(inset),
                child: AnimatedAlign(
                  duration: still ? Duration.zero : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: AlignmentDirectional(index == 0 ? -1 : 1, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / tabs.length,
                    heightFactor: 1,
                    child: const DecoratedBox(key: WalletScreen.thumbKey, decoration: QDecor.segmentThumb),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(children: [
          for (final (tab, label) in tabs)
            Expanded(
              child: Semantics(
                selected: tab == chosen,
                child: QTapArea(
                  key: WalletScreen.tabKey(tab),
                  onTap: () {
                    if (tab == chosen) return;
                    HapticFeedback.selectionClick();
                    onChoose(tab);
                  },
                  builder: (context, pressed) => Center(
                    child: AnimatedDefaultTextStyle(
                      duration: still ? Duration.zero : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: QText.body(size: 15, weight: FontWeight.w500, color: tab == chosen ? QColors.onAccent : (pressed ? QColors.onPastelSecondary : QColors.onInk)),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// What Su can buy, one row each on one card: the name and the price, what
/// it does and its limit, and the one way to take it. A price the balance
/// does not reach is off (O11), not a live-looking button that quietly does
/// nothing, and only then does it say what would be left.
class _SpendList extends StatelessWidget {
  const _SpendList();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: QDecor.card(),
      child: Column(children: [
        for (final (i, item) in kSpendCatalog.indexed) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairline),
          _SpendRow(item: item),
        ],
      ]),
    );
  }
}

class _SpendRow extends StatelessWidget {
  final SpendItemDef item;
  const _SpendRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final done = item.once && state.isRedeemed(item.id);
    final afford = state.suAvailable >= item.price && !done;
    final after = state.suAvailable - item.price < 0 ? 0 : state.suAvailable - item.price;

    return Padding(
      padding: const EdgeInsets.fromLTRB(QSpace.xl, QSpace.lg, QSpace.lg, QSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Expanded(child: Text(isAr ? item.nameAr : item.nameEn, style: QText.body(size: 16, weight: FontWeight.w600, color: QColors.ink))),
            const SizedBox(width: QSpace.md),
            Text(state.suAmount(item.price), style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink, ar: isAr)),
          ]),
          const SizedBox(height: QSpace.xs),
          Text(isAr ? item.whatAr : item.whatEn, style: QText.body(size: 15, color: QColors.inkSecondary)),
          const SizedBox(height: QSpace.xs),
          Text(isAr ? item.limitAr : item.limitEn, style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
          Row(children: [
            Expanded(
              child: afford
                  ? Text('${state.t.balanceAfter} ${state.formatSu(after)}', style: QText.number(size: 13, color: QColors.inkSecondary, ar: isAr))
                  : const SizedBox.shrink(),
            ),
            QOutlineButton(
              key: ValueKey('redeem-${item.id}'),
              label: done ? (isAr ? 'اتستخدم' : 'Redeemed') : state.t.spendCta,
              height: 36,
              onTap: afford ? () => state.redeem(item) : null,
            ),
          ]),
        ],
      ),
    );
  }
}

/// Every point, the reason it came or went, and when: one row each.
class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isAr = state.isAr;
    final ledger = state.ledger();
    if (ledger.isEmpty) {
      return QStateLine(
        icon: QIcons.empty,
        line: isAr ? 'مفيش حركات لسه. كل نقطة بتتكسب هتظهر هنا بسببها.' : 'Nothing here yet. Every point you earn shows up here with its reason.',
      );
    }
    return Container(
      decoration: QDecor.card(),
      child: Column(children: [
        for (final (i, entry) in ledger.indexed) ...[
          if (i > 0) const Divider(height: 1, thickness: 1, indent: QSpace.lg, color: QColors.hairline),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: QSpace.lg, vertical: QSpace.md),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // A server row carries a reason code and a timestamp; these
                    // turn them into words and a time in the person's language.
                    Text(entry.displayLabel(isAr), style: QText.body(size: 16, color: QColors.ink)),
                    Text(state.iso(entry.displayWhen(isAr, now: state.clockNow())), style: QText.body(size: 13, height: 18, color: QColors.inkSecondary)),
                  ]),
                ),
                const SizedBox(width: QSpace.md),
                Text(state.suSigned(entry.amount), style: QText.number(size: 15, weight: FontWeight.w600, color: QColors.ink)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
