import 'package:flutter/material.dart';

import '../models/dishes.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../theme/text_styles.dart';
import 'common.dart';
import 'dish_card.dart';
import 'moon.dart';

/// What "Chat with Qamar" opens first (O5): something real before any
/// question. Three everyday dishes as chips; a tap shows the dish with the
/// food graph's numbers and one plain sentence; "Tell me about you — two
/// minutes" starts the consultation, and is there from the start, so the
/// taster never stands in the way.
///
/// Nothing here promises a target. The welcome comes before the safety
/// question, and someone who answers it is deliberately given none (the
/// general-guidance route), so every line is one that is true for everyone:
/// the consultation, and how long it takes.
///
/// Chips only, no typing: consent comes before anything personal, and what
/// someone ate is health data. Nothing about the person leaves the phone
/// here; the graph is asked for the three dishes' numbers only.
class WelcomeDishes extends StatefulWidget {
  final AppState state;
  const WelcomeDishes({super.key, required this.state});

  static const startKey = ValueKey('welcome-dishes-start');

  /// Qamar's first line, above the chips.
  static String intro(bool ar) => ar ? 'قبل أي أسئلة: اختار أكلة، وأنا أوريك فيها إيه.' : 'Before any questions: pick a dish, and I’ll show you what’s in it.';

  /// The button that starts the consultation: what it is, and how long.
  static String startLabel(bool ar) => ar ? 'احكيلي عنك — دقيقتين' : 'Tell me about you — two minutes';
  static Key chipKey(String id) => ValueKey('welcome-dish-$id');

  static Future<void> show(BuildContext context, AppState state) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: QColors.cardDeep,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(QRadii.sheet))),
        builder: (_) => WelcomeDishes(state: state),
      );

  @override
  State<WelcomeDishes> createState() => _WelcomeDishesState();
}

class _WelcomeDishesState extends State<WelcomeDishes> {
  EgyptianDish? _chosen;

  @override
  void initState() {
    super.initState();
    widget.state.openWelcomeDishes();
  }

  void _choose(EgyptianDish d) {
    setState(() => _chosen = d);
    widget.state.welcomeDishShown(d);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final isAr = state.isAr;
    final dishes = [for (final id in kWelcomeDishIds) kEgyptianDishes.firstWhere((d) => d.id == id)];
    final chosen = _chosen;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final facts = chosen == null ? null : state.dishFactsFor(chosen);
        return Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const QamarMoon(size: 36),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          WelcomeDishes.intro(isAr),
                          style: QText.body(size: 15, height: 22, color: QColors.textHigh),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in dishes)
                        QPillChip(key: WelcomeDishes.chipKey(d.id), label: welcomeDishLabel(d, isAr), selected: chosen?.id == d.id, onTap: () => _choose(d)),
                    ],
                  ),
                  if (chosen != null && facts != null) ...[
                    const SizedBox(height: 14),
                    DishCard(dish: chosen, facts: facts, isAr: isAr, iso: state.iso),
                    const SizedBox(height: 10),
                    Text(dishSentence(facts, ar: isAr, iso: state.iso), style: QText.body(size: 14, height: 21, color: QColors.textMid)),
                  ],
                  const SizedBox(height: 16),
                  QPrimaryButton(
                    key: WelcomeDishes.startKey,
                    label: WelcomeDishes.startLabel(isAr),
                    height: 52,
                    onTap: () {
                      Navigator.of(context).pop();
                      state.startOnboarding();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
