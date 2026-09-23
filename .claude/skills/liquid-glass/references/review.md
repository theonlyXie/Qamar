# Review checklist

Use this on a screen, a diff or a screenshot. Every "no" is a finding, and every finding names the rule it breaks. Look at the rendered images, in English **and** Arabic, not just the code.

## 1. Purpose and simplicity (the owner's own rule: the faster and simpler, the better)
- [ ] The screen's job fits in one sentence.
- [ ] There is exactly one primary (burgundy) button, or none on a pure reading screen.
- [ ] The main task takes at most two taps from where the person is. Write down the count.
- [ ] No question is asked that could have been defaulted or inferred.
- [ ] No confirmation for a reversible action (Undo instead). Anything irreversible, paid or on the person's behalf is confirmed once.
- [ ] No jargon: no model, tokens, API, sync, server, confidence, error codes, IDs or "estimate ±". Every technical state is said as what it means.
- [ ] No sheet opened from a sheet, and no tutorial wall.
- [ ] Anything a person waits on over about 300 ms shows specific words, and long work can be cancelled.

## 2. Colour
- [ ] The only hue is burgundy (the `accent` tokens and the page's light), plus photographs and the Google "G" on the account sheet.
- [ ] One burgundy action per screen: the primary button, or in the conversation the send circle once there is something to send. Chosen chips may all be burgundy, as many as are chosen, and so may a switch that is on: they mark what is chosen.
- [ ] In the conversation, the mic beside an empty field and stop are clear glass, a turn's next step is a clear glass chip with `accentInk` words, and "Confirm and log" is the primary. The onboarding composer's send is burgundy only while there is text.
- [ ] Burgundy never shows status. A reading over target isn't red or burgundy, and nothing is coloured to mean success, warning or error: a glyph and words say it.
- [ ] `accentInk` is never body text. It colours bars, the streak ring, a chosen radio mark and the words of a way on (a notice's action, a turn's next step), and nothing longer than an action's own words.
- [ ] Quiet actions (Later, Not now, Cancel, Undo) are `inkSecondary`. Legal links (Terms, Privacy) are `inkTertiary` with an underline.
- [ ] Every colour is a `QColors` token; no `Color(0x…)` at the call site.
- [ ] Text contrast is at least 4.5:1, and `inkDisabled` is used only for disabled or decorative things.
- [ ] No state is shown by colour or grey level alone: each has a shape, icon or words.

## 3. Glass
- [ ] Cards, grouped lists and sheets are glass panels (lens fill, rim, no shadow). Cards don't blur; sheets are frosted (`glassSheet` over a sigma-24 blur); floating controls blur at sigma 20.
- [ ] Glass panels are readable over the ambient light. Every readable ink holds 4.5:1 on a pane, a raised pane and an inset at 80% of the glow (the most any card sees), and words directly on the page hold it on the full glow. A bar on its track is a graphic, held to 3:1.
- [ ] The primary and the pill are burgundy glass, and the send circle is, once there is text. Secondary buttons, unchosen chips, the mic and stop are clear glass. A chosen segment is neutral raised glass, never burgundy.
- [ ] Glass on glass only as an inset (`glassInset`). No blurring layer sits on another, and about four blurring surfaces at most are on screen.
- [ ] Over a photo or the camera, controls use the thin fill with a 35% dim.
- [ ] Scroll edges fade under floating controls. There are no dividers or solid bars there, and nothing rests under floating glass at the top.
- [ ] The conversation is plain: Qamar's words on black, the person's in a `surfaceHigh` bubble, no glass behind the transcript.
- [ ] Increase Contrast makes floating glass and sheets solid, and cards keep their pane (checked in a test or render).

## 4. Type
- [ ] Only the scale's sizes (11–17 text, 20/22/28/34 display, 20/28/34/48/56 figures). Nothing smaller than 11.
- [ ] Weights are 400 to 700 only.
- [ ] Arabic is never tracked or uppercased. English eyebrows are uppercase with 0.6 tracking.
- [ ] At most one hero numeral per screen (`HeroNumber`, 56, bold, tabular), with its unit in `inkSecondary`.
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
- [ ] Reduce Motion gives fades. Every loop stops, the orb's breathing and the moon's phase drift included, and the meaning is still conveyed in words. The screen settles: nothing keeps scheduling frames (a widget test's `pumpAndSettle` returns).
- [ ] No control drifts on its own. Buttons, chips and the tree's circles hold still.

## 7. Shape and space
- [ ] Controls are capsules, icon buttons are circles, cards are 24, sheets are 32.
- [ ] Nested corners are concentric.
- [ ] Spacing is on the 4-pt grid, with a 20 page margin.
- [ ] Every target is at least 48 × 48.

## 8. No dots
- [ ] No dot-matrix numerals, dot rings, dot sweeps or dotted connecting lines. Numbers are set in the UI face, the streak is arc segments, and the tree has no lines.
- [ ] The only dotted line is the explain mark: a quiet dotted underline under a value the orb can explain, and only there.

## 9. Arabic and RTL
- [ ] The Arabic render mirrors correctly: back points right, lists start on the right, bars fill from the right.
- [ ] Rings and the moon are unchanged between the two languages.
- [ ] Nothing is clipped, overlapping or truncating a number in the longer language.
- [ ] Arabic copy reads as natural Egyptian Arabic, not a translation.

## 10. Accessibility
- [ ] Semantics labels are in the current language, and custom paint is labelled or excluded.
- [ ] The layout survives 200% text (restack, don't truncate).
- [ ] A chat reply or completion is announced once.

## 11. Code and tests
- [ ] `flutter analyze` is clean and `flutter test` is green, including the design tests.
- [ ] Tests that pinned the old design were updated to the new intent, not deleted or loosened.
- [ ] A changed colour token is changed in `references/tokens.md` too.
- [ ] The render harness is not committed.

## How to report
List each finding with a severity, a location and the fix:
- **blocker:** breaks a law (burgundy as status, a second burgundy action, broken RTL, below 4.5:1, a lost function).
- **should:** breaks a rule in a component or reference.
- **nit:** craft.

Then list what you checked and found fine, in one line.
