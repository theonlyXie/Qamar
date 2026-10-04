# Review checklist

Use this on a screen, a diff or a screenshot. Every "no" is a finding, and every finding names the rule it breaks. Look at the rendered images, in English **and** Arabic, and on a short phone (375 × 667), not just the code.

## 1. Purpose and simplicity (the owner's rule: the faster and simpler, the better)
- [ ] The screen's job fits in one sentence.
- [ ] There is exactly one burgundy fill (the primary), the tab bar aside, or none on a pure reading screen.
- [ ] The main task takes at most two taps from where the person is. Write down the count. Logging anything is the orb's tap and one choice on the Log sheet.
- [ ] No question is asked that could have been defaulted or inferred.
- [ ] No confirmation for a reversible action (Undo instead). Anything irreversible, paid or on the person's behalf is confirmed once.
- [ ] No jargon: no model, tokens, API, sync, server, confidence, error codes or IDs.
- [ ] No sheet opened from a sheet, and no tutorial wall.
- [ ] Anything a person waits on over about 300 ms shows specific words.

## 2. Colour
- [ ] The ground is `canvas`; cards `surface`; controls `surfaceRaised`; a circle on a control `surfaceHigh`.
- [ ] Pastels only as a card's whole ground (or a band or tile in one), with black words (`onPastel`). No pastel word, line or edge on the dark.
- [ ] Where a macro is shown, its pastel means it: calories lavender, protein mint, carbs lime, fat coral.
- [ ] Burgundy only for the thing to do and what is chosen: the primary, the send circle, a chosen chip or segment, a switch that is on, the tab on show. Never status: a reading over target is not red or burgundy, and nothing is coloured to mean success, warning or error.
- [ ] `accentInk` is never body text: a way on, the streak line and ring, a bar on the dark.
- [ ] Quiet actions (Later, Not now, Cancel, Undo) are `inkSecondary`; legal links `inkTertiary`, underlined.
- [ ] Every colour is a `QColors` token; no `Color(0x…)` at the call site.
- [ ] Text contrast is at least 4.5:1 on its own ground, pastels included; `inkDisabled` only for what can't be used.
- [ ] No state is shown by colour alone: each has a glyph, a shape or words.

## 3. Surfaces
- [ ] Flat: no shadow, no gradient, no glass, no blur on a surface. The only blur is a sheet's scrim.
- [ ] Cards have the one-point edge (`QDecor.card()`) or are pastels (no edge). A card never holds a card: an item inside is `surfaceRaised` at `inset`.
- [ ] Sheets are `surface`, top corners 32, with a grabber; a tall one scrolls and stops under the top.
- [ ] Over a photo or the camera, controls are `overPhoto`.
- [ ] Content scrolling under the tab bar passes under the fade; a tab page's end rests above the band.

## 4. Type
- [ ] Only the scale's sizes (12–18 text, 20/24/28/34 titles, 20–56 figures); nothing under 12.
- [ ] Weights 400 to 700 only; nothing tracked; nothing uppercased (the eyebrow is sentence case).
- [ ] At most one hero figure per screen, its unit in the second ink.
- [ ] Live numbers are tabular and follow the digits setting.

## 5. Icons
- [ ] Every glyph comes from `QIcons` and is drawn through `QIcon`; no Material or emoji glyphs (the sign-in marks aside).
- [ ] Linear at rest, bold only for chosen or on.
- [ ] Every icon-only control has a spoken label, and a word wherever the glyph could be misread.
- [ ] Only directional glyphs mirror in Arabic.

## 6. The tab bar, the orb and the Log sheet
- [ ] The four tab pages have the bar and no back control; pages under a tab have one back control and no bar.
- [ ] The tab on show is the burgundy circle with its bold glyph, and says it is selected.
- [ ] The orb is calm: it breathes in its circle; nothing orbits, drifts or sparkles.
- [ ] The Log sheet rises under the bar; every way to log is on it, one tap each; its last row ends above the bar.

## 7. The brand
- [ ] The moon is Qamar's mark: the orb in the bar, the mascot where the kit draws a character, the coin's crescent. The mascot stands on a pastel, lit on the right as the app's moons are.
- [ ] Burgundy where the kit has its orange; the name Qamar / قمر, never a stand-in.

## 8. Motion
- [ ] The press shows on touch-down (0.97).
- [ ] Arrivals use the settle spring and leave by the same path; no bounce unless flicked.
- [ ] Frequent actions barely animate; everything is interruptible.
- [ ] Reduce Motion gives fades, every loop stops, and the screen settles (`pumpAndSettle` returns).
- [ ] Nothing a finger must hit drifts.

## 9. Shape and space
- [ ] Buttons are rounded rectangles at `control` (primary 50 tall); chips, segments and the tab bar capsules; round buttons circles; cards 24; sheets 32.
- [ ] No corner written as a number outside the theme; nested corners concentric.
- [ ] Spacing on the 4-point grid; page margin 20.
- [ ] Every target at least 48 × 48.

## 10. Arabic and RTL
- [ ] The Arabic render mirrors: back points right, lists and rows start on the right, bars and the calorie gauge fill from the right, the tab bar reads Today first from the right.
- [ ] Rings, clocks and the moon's phase are the same in both languages.
- [ ] Nothing clipped, overlapping or truncating a number in the longer language; two numbers joined by a slash keep their spaces.
- [ ] Arabic copy reads as natural Egyptian Arabic.

## 11. Accessibility
- [ ] Semantics labels in the current language; custom paint labelled or excluded.
- [ ] The layout survives 200% text (restack or scroll, don't truncate).
- [ ] A chat reply or completion is announced once.

## 12. Code and tests
- [ ] `flutter analyze` clean, `flutter test` green, the design tests included.
- [ ] Tests that pinned the old design were updated to the new intent, not deleted or loosened.
- [ ] A changed colour token is changed in `references/tokens.md` too.
- [ ] The render harness is not committed.

## How to report
List each finding with a severity, a location and the fix:
- **blocker:** breaks a law (burgundy as status, a second burgundy action, a pastel word on the dark, broken RTL, below 4.5:1, a lost function).
- **should:** breaks a rule in a component or reference.
- **nit:** craft.

Then list what you checked and found fine, in one line.
