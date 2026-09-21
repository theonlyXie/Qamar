/// Shop this plan — the blueprint's outbound commerce, bounded.
///
/// "One grocery-delivery partner in Cairo; basket built from the plan's
/// dishes; deep link to partner checkout with Qamar's affiliate ID." No
/// partner is signed yet, so everything partner-specific is configuration:
/// the link template, the name on the button, the affiliate reference. With
/// no template configured, nothing about shopping appears anywhere.
///
/// The basket is the plan's portions as they are written — household units,
/// not SKUs. Converting "a bowl of koshary" into a partner's catalogue is the
/// partner's side of the integration and cannot be guessed here.
library;

import 'plan.dart';

/// The signed partner, from build configuration.
class GroceryPartner {
  /// The deep-link template. `{items}`, `{ref}` and `{lang}` are replaced;
  /// a template without them gets `items`, `ref` and `lang` as query
  /// parameters instead.
  final String url;

  /// The name on the button — "Breadfast", "Rabbit", "Talabat Mart".
  final String name;

  /// Qamar's affiliate reference with that partner.
  final String ref;

  const GroceryPartner({required this.url, required this.name, required this.ref});

  static const none = GroceryPartner(url: '', name: '', ref: '');

  bool get enabled => url.trim().isNotEmpty;
}

class BasketLine {
  final String ar;
  final String en;
  final String amountAr;
  final String amountEn;
  final int kcal;
  const BasketLine({required this.ar, required this.en, required this.amountAr, required this.amountEn, required this.kcal});

  String name({required bool ar}) => ar ? this.ar : en;
  String amount({required bool ar}) => ar ? amountAr : amountEn;
}

class GroceryBasket {
  final List<BasketLine> lines;
  const GroceryBasket(this.lines);

  /// Every distinct portion across the meals, first occurrence wins. A dish
  /// that appears at two meals is one line, not two — the partner's basket
  /// is not the place to discover the plan repeats itself.
  static GroceryBasket fromMeals(Iterable<PlanMeal> meals) {
    final seen = <String>{};
    final out = <BasketLine>[];
    for (final m in meals) {
      for (final p in m.portions) {
        final key = p.en.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(BasketLine(ar: p.ar, en: p.en, amountAr: p.amountAr, amountEn: p.amountEn, kcal: p.kcal));
      }
    }
    return GroceryBasket(out);
  }

  bool get isEmpty => lines.isEmpty;
  int get count => lines.length;

  /// The partner checkout link for this basket, tagged with Qamar's reference.
  Uri link(GroceryPartner partner, {required bool ar}) {
    final items = lines.map((l) => l.name(ar: ar)).join(',');
    final lang = ar ? 'ar' : 'en';
    final template = partner.url.trim();
    if (template.contains('{items}') || template.contains('{ref}') || template.contains('{lang}')) {
      return Uri.parse(
        template
            .replaceAll('{items}', Uri.encodeComponent(items))
            .replaceAll('{ref}', Uri.encodeComponent(partner.ref))
            .replaceAll('{lang}', lang),
      );
    }
    final base = Uri.parse(template);
    return base.replace(queryParameters: {
      ...base.queryParameters,
      'items': items,
      if (partner.ref.isNotEmpty) 'ref': partner.ref,
      'lang': lang,
    });
  }
}
