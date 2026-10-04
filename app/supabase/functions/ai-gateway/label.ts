// Reading the nutrition table off the back of a packet.
//
// The vision model transcribes what it can see; everything here decides
// whether what it saw can be trusted and converts it to the one basis the rest
// of the app uses (per 100 g).
//
// Three ways a nutrition label quietly produces a wrong number, all of them
// handled below rather than hoped about:
//
//   BASIS      An EU or Egyptian panel is per 100 g. An American one is per
//              serving. Many show both. Reading a 30 g serving column as if it
//              were per 100 g understates the food by a factor of three, and
//              nothing downstream would notice.
//   ENERGY     European labels lead with kilojoules. 2000 kJ is 478 kcal, and
//              treating the kJ figure as kcal inflates a food four-fold.
//   DECIMALS   A misread decimal point turns 54.0 into 540. Nothing that comes
//              off a label should be believed past the limits of food itself.

/** Per 100 g, in Qamar nutrient codes. */
export type Per100g = Record<string, number>;

/** What the model says it saw. Every field may be absent. */
export interface LabelReading {
  /** "per_100g" | "per_serving" — which column was transcribed. */
  basis?: string | null;
  /** The serving size in grams, when the panel states one. */
  servingGrams?: number | null;
  kcal?: number | null;
  kj?: number | null;
  proteinG?: number | null;
  carbsG?: number | null;
  fatG?: number | null;
  satFatG?: number | null;
  sugarsG?: number | null;
  fiberG?: number | null;
  sodiumMg?: number | null;
  saltG?: number | null;
  legible?: boolean;
  note?: string | null;
}

export interface NormalisedLabel {
  per100g: Per100g;
  /** Grams of one serving, when the label said. */
  servingGrams: number | null;
  /** Which column the figures were read from. */
  basis: "per_100g" | "per_serving";
  /** True when energy was derived from kilojoules rather than read as kcal. */
  energyFromKj: boolean;
}

export type LabelProblem =
  | "illegible"
  | "no_energy"
  | "serving_basis_without_serving_size"
  | "implausible_energy"
  | "energy_disagrees_with_macros";

/** 1 kcal = 4.184 kJ, by definition. */
const KJ_PER_KCAL = 4.184;

/**
 * The most energy 100 g of food can hold.
 *
 * Pure fat is 900 kcal per 100 g, so nothing edible exceeds it. A label read
 * as more than that is a misplaced decimal or a kJ figure in the kcal box, and
 * either way it must not become somebody's dinner.
 */
const MAX_KCAL_PER_100G = 900;

const num = (v: unknown): number | null =>
  typeof v === "number" && Number.isFinite(v) && v >= 0 ? v : null;

/**
 * Turns a transcribed panel into per-100 g figures, or explains why it cannot.
 *
 * Returns a problem rather than a best guess. The whole point of scanning a
 * label instead of typing it is accuracy, so a panel that cannot be read
 * confidently is worth less than nothing.
 */
export function normaliseLabel(
  r: LabelReading,
): { ok: true; value: NormalisedLabel } | { ok: false; problem: LabelProblem } {
  if (r.legible === false) return { ok: false, problem: "illegible" };

  // Energy first: without it there is nothing to add to a day.
  let kcal = num(r.kcal);
  let energyFromKj = false;
  if (kcal == null) {
    const kj = num(r.kj);
    if (kj == null) return { ok: false, problem: "no_energy" };
    kcal = Math.round(kj / KJ_PER_KCAL);
    energyFromKj = true;
  }

  const basis = r.basis === "per_serving" ? "per_serving" : "per_100g";
  const servingGrams = num(r.servingGrams);

  // A per-serving column is unusable without knowing what a serving weighs.
  // Guessing 100 g here would be exactly the three-fold error this exists to
  // prevent.
  if (basis === "per_serving" && (servingGrams == null || servingGrams <= 0)) {
    return { ok: false, problem: "serving_basis_without_serving_size" };
  }

  const factor = basis === "per_serving" ? 100 / servingGrams! : 1;
  const scale = (v: number | null): number | null =>
    v == null ? null : Math.round(v * factor * 100) / 100;

  const per100g: Per100g = {};
  const put = (code: string, v: number | null) => {
    if (v != null) per100g[code] = v;
  };

  const kcal100 = Math.round((kcal * factor) * 10) / 10;
  if (kcal100 > MAX_KCAL_PER_100G) return { ok: false, problem: "implausible_energy" };
  put("energy_kcal", kcal100);

  put("protein_g", scale(num(r.proteinG)));
  put("carbs_g", scale(num(r.carbsG)));
  put("fat_g", scale(num(r.fatG)));
  put("sat_fat_g", scale(num(r.satFatG)));
  put("sugars_g", scale(num(r.sugarsG)));
  put("fiber_g", scale(num(r.fiberG)));

  // Salt and sodium are two ways of printing the same thing. Egyptian and EU
  // panels usually give salt; 1 g of salt is 400 mg of sodium.
  const sodium = num(r.sodiumMg);
  const salt = num(r.saltG);
  if (sodium != null) put("sodium_mg", scale(sodium));
  else if (salt != null) put("sodium_mg", scale(salt * 400));

  // Atwater cross-check. If the macros are present they should account for the
  // energy; a large disagreement means a column was misread, and it is better
  // to ask again than to log a confident wrong number.
  const p = per100g.protein_g, c = per100g.carbs_g, f = per100g.fat_g;
  if (p != null && c != null && f != null) {
    const computed = 4 * p + 4 * c + 9 * f;
    const gap = Math.abs(computed - kcal100);
    // Generous: fibre, polyols and rounding on a printed panel all move this.
    if (gap > Math.max(0.35 * kcal100, 60)) {
      return { ok: false, problem: "energy_disagrees_with_macros" };
    }
  }

  return {
    ok: true,
    value: { per100g, servingGrams, basis, energyFromKj },
  };
}

/** What to tell the person when a panel could not be used. */
export function labelProblemText(problem: LabelProblem, lang: string): string {
  const ar: Record<LabelProblem, string> = {
    illegible: "الصورة مش واضحة كفاية أقرا منها الجدول. قرّب على الجدول نفسه والنور يكون عليه.",
    no_energy: "مش لاقي السعرات في الجدول. صوّر الجزء اللي فيه الطاقة/السعرات.",
    serving_basis_without_serving_size:
      "الجدول بالحصة مش بالـ ١٠٠ جم، ومكتوبش الحصة كام جرام. صوّرلي الجزء ده كمان.",
    implausible_energy: "الرقم اللي قريته مش منطقي لأكل. صوّر الجدول تاني من غير انعكاس.",
    energy_disagrees_with_macros:
      "الأرقام في الجدول مش متطابقة مع بعضها، يمكن الصورة مايلة. صوّرها تاني بشكل مستقيم.",
  };
  const en: Record<LabelProblem, string> = {
    illegible: "That photo is not clear enough to read the table. Get closer to the panel itself, with light on it.",
    no_energy: "I cannot find the calories on that panel. Photograph the part with energy or kcal on it.",
    serving_basis_without_serving_size:
      "The panel is per serving rather than per 100 g, and it does not say what a serving weighs. Include that part too.",
    implausible_energy: "The figure I read is not possible for food. Photograph the panel again without glare.",
    energy_disagrees_with_macros:
      "The numbers on that panel do not agree with each other — the photo may be at an angle. Try again straight on.",
  };
  return (lang === "ar" ? ar : en)[problem];
}
