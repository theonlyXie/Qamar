/** Mifflin–St Jeor target calculation — mirrors the Flutter AppState formula. */

export type TargetInputs = {
  birth_date: string;
  gender: "male" | "female";
  height_cm: number;
  weight_kg: number;
  activity_factor: number;
  goal: "lose" | "maintain" | "gain";
};

export type TargetResult = {
  kcal: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  formula_version: string;
  inputs: TargetInputs;
  bmr: number;
  tdee: number;
};

function ageFromBirthDate(iso: string, now = new Date()): number {
  const b = new Date(iso);
  let age = now.getFullYear() - b.getFullYear();
  const before =
    now.getMonth() < b.getMonth() ||
    (now.getMonth() === b.getMonth() && now.getDate() < b.getDate());
  if (before) age--;
  return age;
}

export function calculateTarget(inputs: TargetInputs): TargetResult {
  const age = ageFromBirthDate(inputs.birth_date);
  const s = inputs.gender === "male" ? 5 : -161;
  const bmr = 10 * inputs.weight_kg + 6.25 * inputs.height_cm - 5 * age + s;
  const tdee = bmr * inputs.activity_factor;
  let kcal = Math.round(tdee);
  if (inputs.goal === "lose") kcal = Math.round(tdee - 500);
  if (inputs.goal === "gain") kcal = Math.round(tdee + 300);
  kcal = Math.max(1200, Math.min(4000, kcal));

  const protein_g = Math.round(inputs.weight_kg * 1.6);
  const fat_g = Math.round((kcal * 0.25) / 9);
  const carbs_g = Math.max(0, Math.round((kcal - protein_g * 4 - fat_g * 9) / 4));

  return {
    kcal,
    protein_g,
    carbs_g,
    fat_g,
    formula_version: "calc v2.0",
    inputs,
    bmr: Math.round(bmr),
    tdee: Math.round(tdee),
  };
}
