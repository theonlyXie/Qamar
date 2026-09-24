import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../theme/layout.dart';
import '../widgets/account_sheet.dart';
import '../widgets/ask_qamar_overlay.dart';
import '../widgets/common.dart';
import '../widgets/explain.dart';
import '../widgets/log_sheet.dart';
import '../widgets/tab_bar.dart';
import '../widgets/why_sheet.dart';
import 'onboarding_screen.dart';
import 'plan_screen.dart';
import 'progress_screen.dart';
import 'scan_screen.dart';
import 'today_screen.dart';
import 'subscription_screen.dart';
import 'wallet_screen.dart';
import 'welcome_screen.dart';
import '../widgets/activity_sheet.dart';
import 'ramadan_screen.dart';
import 'you_screen.dart';

/// Root of the real app — equivalent to the prototype's single device frame.
/// Owns the current-screen switch, the floating tab bar with the orb in its
/// middle, and the overlays that float above any screen (the conversation,
/// the Log sheet, the Why sheet and the rest).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  Widget _currentScreen(AppScreen s) {
    switch (s) {
      case AppScreen.welcome:
        return const WelcomeScreen();
      case AppScreen.scan:
        return const ScanScreen();
      case AppScreen.onboard:
        return const OnboardingScreen();
      case AppScreen.today:
        return const TodayScreen();
      case AppScreen.plan:
        return const PlanScreen();
      case AppScreen.progress:
        return const ProgressScreen();
      case AppScreen.you:
        return const YouScreen();
      case AppScreen.wallet:
        return const WalletScreen();
      case AppScreen.subscription:
        return const SubscriptionScreen();
      case AppScreen.ramadan:
        return const RamadanScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // The phone's back follows the same rule as the back control: the
    // topmost sheet first, then the screen the person came from. Only at a
    // root with nothing open is it the system's (leaving the app). Without
    // this, one route and no stack meant Android's back left the app from
    // any screen.
    return PopScope(
      canPop: !state.handlesSystemBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) state.systemBack();
      },
      child: _Strips(state: state, child: _shell(state)),
    );
  }

  /// The strips above and below the safe area: the status bar's and the
  /// home indicator's.
  static const topStripKey = ValueKey('shell-top-strip');
  static const bottomStripKey = ValueKey('shell-bottom-strip');

  /// What covers the screen, seen where the strips are: the scan's black,
  /// the conversation's ground, a sheet's dimming, in the order they stack.
  /// Null when only the page's own ground is there.
  static Color? coverAt(AppState state, {required bool top}) {
    Color? c;
    void add(Color layer) => c = c == null ? layer : Color.alphaBlend(layer, c!);
    if (state.screen == AppScreen.scan) add(QColors.canvas);
    if (state.chatOpen) add(top ? AskQamarOverlay.groundTop : AskQamarOverlay.groundBottom);
    final sheet = state.logOpen || state.whyOpen || state.authOpen || state.pendingActivity != null || state.explainOpen != null;
    // A sheet dims what is above it; at the bottom it is the sheet itself,
    // whose surface runs on under the home indicator.
    if (sheet) add(top ? QColors.scrim : QColors.surface);
    return c;
  }

  Widget _shell(AppState state) {
    return Scaffold(
      backgroundColor: QColors.canvas,
      body: Stack(children: [
        // The page's ground, under the phone's own bars: the dark, or the
        // welcome's lavender with its bump.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: state.screen == AppScreen.welcome ? const WelcomeBackdrop() : const ColoredBox(color: QColors.canvas, child: SizedBox.expand()),
          ),
        ),
        SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(state.screen), child: _currentScreen(state.screen)),
                ),
              ),
              // The tab bar's band (O1): content that is still scrolling
              // passes under a soft fade rather than a hard edge, and the
              // fade takes no touches — only the bar does.
              if (state.orbVisible) const Positioned(left: 0, right: 0, bottom: 0, height: QLayout.tabBand + TabBarFade.reachAbove, child: TabBarFade()),
              // The orb's own sheet rises under the bar, so the moon that
              // opened it stays in view and answers: a tap puts the sheet
              // away, a hold talks, as the sheet's last line says.
              QSheetSlot(open: state.logOpen, child: const LogSheet()),
              if (state.orbVisible) const QTabBar(),
              // The conversation arrives under its own fade and leaves under
              // this one, so closing it is as soft as opening it was.
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !state.chatOpen,
                  child: AnimatedSwitcher(
                    duration: Duration.zero,
                    reverseDuration: const Duration(milliseconds: 180),
                    child: state.chatOpen ? const AskQamarOverlay() : const SizedBox.shrink(),
                  ),
                ),
              ),
              // Each sheet stays until it has left the way it came.
              QSheetSlot(open: state.whyOpen, child: const WhySheet()),
              QSheetSlot(open: state.authOpen, child: const AccountSheet()),
              QSheetSlot(open: state.pendingActivity != null, child: const ActivitySheet()),
              QSheetSlot(open: state.explainOpen != null, child: const ExplainSheet()),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Nothing inside the safe area reaches the status bar or the home
/// indicator, so without these the scan's black, the conversation's ground
/// and a sheet's dimming all stopped short of the screen's edges, under a
/// strip of the page's sky.
class _Strips extends StatelessWidget {
  final AppState state;
  final Widget child;
  const _Strips({required this.state, required this.child});

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final still = MediaQuery.of(context).disableAnimations;
    Widget strip(Key key, Color? color) => IgnorePointer(
          child: AnimatedContainer(
            key: key,
            duration: still ? Duration.zero : const Duration(milliseconds: 180),
            color: color ?? Colors.transparent,
          ),
        );
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(top: 0, left: 0, right: 0, height: pad.top, child: strip(HomeShell.topStripKey, HomeShell.coverAt(state, top: true))),
        Positioned(bottom: 0, left: 0, right: 0, height: pad.bottom, child: strip(HomeShell.bottomStripKey, HomeShell.coverAt(state, top: false))),
      ],
    );
  }
}
