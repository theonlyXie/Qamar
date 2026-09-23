# Review checklist

Use this on a screen, a diff or a screenshot. Every "no" is a finding, and every finding names the rule it breaks. Look at the rendered images, in English **and** Arabic, not just the code.

## 1. Purpose and simplicity (the user's own rule: the faster and simpler, the better)
- [ ] The screen's job fits in one sentence.
- [ ] There is exactly one primary (white) button, or none on a pure reading screen.
- [ ] The main task takes at most two taps from where the person is. Write down the count.
- [ ] No question is asked that could have been defaulted or inferred.
- [ ] No confirmation for a reversible action (Undo instead). Anything irreversible, paid or on the person's behalf is confirmed once.
- [ ] No jargon: no model, tokens, API, sync, server, confidence, error codes, IDs or "estimate ±". Every technical state is said as what it means.
- [ ] No sheet opened from a sheet, and no tutorial wall.
- [ ] Anything a person waits on over about 300 ms shows specific words, and long work can be cancelled.

## 2. Colour
- [ ] No hue anywhere except photographs and required third-party marks.
- [ ] Every colour is a `QColors` token; no `Color(0x…)` at the call site.
- [ ] White is spent on at most the primary action, the hero and the text.
- [ ] Text contrast is at least 4.5:1, and `inkDisabled` is used only for disabled or decorative things.
- [ ] No state is shown by grey level alone: each has a shape, icon or words.

## 3. Layers and glass
- [ ] Glass only on floating controls. No glass cards, rows or messages.
- [ ] No glass on glass, and about four glass surfaces at most on screen.
- [ ] Clear glass only over a photo or camera, with a dim.
- [ ] Scroll edges fade under floating controls. There are no dividers or solid bars there, and nothing rests under glass at the top.
- [ ] High contrast makes glass solid (checked in a test or render).

## 4. Type
- [ ] Only the scale's sizes (11–17 text, 20/22/28/34 display, 20–48 figures). Nothing smaller than 11.
- [ ] Weights are 400 to 700 only.
- [ ] Arabic is never tracked or uppercased. English eyebrows are uppercase with 0.6 tracking.
- [ ] At most one dot-matrix hero per screen, at least 40 tall, and digits only.
- [ ] Live numbers are tabular and follow the digits setting.

## 5. Icons
- [ ] Every glyph comes from `QIcons`. There are no Material `Icons.` glyphs and no emoji-as-icons.
- [ ] Glyphs are outline at rest and filled only for selected or on.
- [ ] Every icon-only control has a spoken label, and a visible word wherever the meaning could be misread.
- [ ] Only directional glyphs mirror in Arabic.

## 6. Motion
- [ ] The press shows on touch-down (0.97 and a brighter fill).
- [ ] Arrivals use the settle spring and leave by the same path. There's no bounce unless the element was flicked.
- [ ] Frequent actions barely animate.
- [ ] Everything is interruptible, and input is never locked during a transition.
- [ ] Reduce Motion gives fades. There's no breathing, orbit or parallax, and the meaning is still conveyed in words.

## 7. Shape and space
- [ ] Controls are capsules, icon buttons are circles, cards are 24, sheets are 32.
- [ ] Nested corners are concentric.
- [ ] Spacing is on the 4-pt grid, with a 20 page margin.
- [ ] Every target is at least 48 × 48.

## 8. Arabic and RTL
- [ ] The Arabic render mirrors correctly: back points right, lists start on the right, bars fill from the right.
- [ ] Rings and the moon are unchanged between the two languages.
- [ ] Nothing is clipped, overlapping or truncating a number in the longer language.
- [ ] Arabic copy reads as natural Egyptian Arabic, not a translation.

## 9. Accessibility
- [ ] Semantics labels are in the current language, and custom paint is labelled or excluded.
- [ ] The layout survives 200% text (restack, don't truncate).
- [ ] A chat reply or completion is announced once.

## 10. Code and tests
- [ ] `flutter analyze` is clean and `flutter test` is green, including the design tests.
- [ ] Tests that pinned the old design were updated to the new intent, not deleted or loosened.
- [ ] The render harness is not committed.

## How to report
List each finding with a severity, a location and the fix:
- **blocker:** breaks a law (colour, glass on content, broken RTL, below 4.5:1, a lost function).
- **should:** breaks a rule in a component or reference.
- **nit:** craft.

Then list what you checked and found fine, in one line.
