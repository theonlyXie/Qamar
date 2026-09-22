import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/colors.dart';
import '../widgets/account_sheet.dart';
import '../widgets/ask_qamar_overlay.dart';
import '../widgets/explain.dart';
import '../widgets/orb_nav.dart';
import '../widgets/tree_overlay.dart';
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
/// Owns the current-screen switch plus the overlays that float above any
/// screen (Ask Qamar, the radial tree, the Why sheet) and the persistent
/// draggable orb.
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
    return Scaffold(
      backgroundColor: QColors.bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: QColors.deviceBg),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(state.screen), child: _currentScreen(state.screen)),
                ),
              ),
              if (state.orbVisible) const OrbNav(),
              if (state.treeOpen) const TreeOverlay(),
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
              if (state.whyOpen) const WhySheet(),
              if (state.authOpen) const AccountSheet(),
              if (state.pendingActivity != null) const ActivitySheet(),
              if (state.explainOpen != null) const ExplainSheet(),
            ],
          ),
        ),
      ),
    );
  }
}
