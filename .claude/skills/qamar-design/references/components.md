# Components

Each entry gives what the component is for, its anatomy, its states and its name in Qamar's kit (`app/lib/widgets/common.dart` unless noted; `kit.dart` holds the Nutri AI kit's own pieces). Every component has a press state, a spoken label and a 48 × 48 target. Colours are tokens (`references/tokens.md`).

## Contents
- Buttons: primary, secondary, pill, on a pastel, text, burgundy words, legal links, round, back and close
- Choices: chips, segmented control, switch, radio rows, wheel
- Containers: card, pastel card, grouped list, sheet, the Log sheet, state card, state line, empty state
- Figures: calorie gauge, macro tiles, bar, hero figure, streak ring, the moon, the mascot, explain mark
- Page structure: page title, section title, the tab bar
- Forms and input
- Feedback

---

## Buttons

### Primary: the one thing to do (`QPrimaryButton`)
- **Anatomy:** a burgundy rounded rectangle (`accent`, corner `control` 12), white words (`onAccent`, 16/600) and an optional leading glyph. 50 tall; spans the content width or hugs its label with 20 of side padding.
- **States:**
  - Pressed: `accentPressed` and scale 0.97, on touch-down.
  - Disabled: not burgundy, because there's nothing to act on: `QDisabled.fill` with `QDisabled.label`, no press. Say why nearby if it isn't obvious.
  - Busy: the label becomes a specific present-tense phrase ("Logging…"); the width stays.
- **Rules:** one per screen, or one per sheet while it's open. Never destructive. Its label starts with a verb ("Log it", "Start", "Confirm and log").

### Secondary: a second choice (`QOutlineButton`)
- **Anatomy:** the control grey (`surfaceRaised`) rounded rectangle with white words (15/500), 44 tall (50 beside a primary), a 48 touch. It can carry a leading glyph. The kit's sign-in buttons are this.
- **Pressed:** `surfaceHigh` and 0.97.
- **The name is historical:** it has no outline.

### Pill: a compact primary in a card (`QPillButton`)
- **Anatomy:** burgundy, 40 tall, white 15/600. "Try it" on a quest. It still counts as the screen's one burgundy fill.

### On a pastel (`QPastelButton`, `kit.dart`)
- **Anatomy:** the kit's black capsule with white words (its "Next"), 36 tall by default (48 on the welcome), touched across 48; `light: true` is the white capsule with black words, for a second way on.
- **Use:** an action inside a pastel card, where burgundy would fight the pastel.

### Text: a quiet action
- `inkSecondary` 15/500, no container, a 48 target: "Later", "Not now", "Cancel", "Skip", "Undo".

### Burgundy words: a way on
- `accentInk` 15/600, no fill, a 48 target: a notice's way on (`QStateLine`, "See Qamar+"), "Got it", a turn's suggested next step. It colours the action's own words, never the sentence round them.

### Legal links (`QLegalLink`)
- `inkTertiary`, 12, underlined. Terms and Privacy are not actions in the flow.

### Round icon (`QRoundIconButton`)
- **Anatomy:** a grey circle (`surfaceRaised`; `raised: true` makes it `surfaceHigh` for a control on a control), 34 by default, 44 in a header, a white glyph about half its size.
- **Use:** a header's bell or crown, steppers (− / +), the Ramadan moon on Today in season.

### Back and close (`QBackButton`, `QRoundIconButton(icon: QIcons.close)`)
- **Placement:** the top start corner. Back is `QIcons.back`, which mirrors in Arabic; close is `QIcons.close`, drawn through `QIcon` (it is the family's add, turned).
- **Labels:** no visible "Back"; spoken "Back" / "رجوع", "Close" / "إغلاق".
- **Tab pages have none:** the tab bar is the way between them. A page under a tab (the wallet, Qamar+, Ramadan) has back and no bar.

---

## Choices

### Chips (`QPillChip`)
- **Anatomy:** a capsule of the control grey, a 15/500 label, about 42 drawn, a 48 target.
- **States:** chosen is burgundy with white words, as many as are chosen (they mark what is chosen, not what to do); pressed 0.97 and a step lighter.
- **Use:** one or a few of up to about six (goals, the Log sheet's Repeat meals are a sibling: a grey capsule with the repeat glyph).

### Segmented control (`QSegmented`, `kit.dart`; `QLangToggle`)
- **Anatomy:** the kit's white capsule track (`QDecor.segmentTrack`), 48 tall; the chosen segment a burgundy capsule (`segmentThumb`) with white words; the others black words on the white.
- **A locked segment** (the plan's Tomorrow on Lite) carries a lock and still answers the tap, so the page can say why.
- **Motion:** 180 ms ease-out between segments.

### Switch
- The theme's: on is a burgundy track under a white thumb, off `surfaceHigh`. The whole row is the target; the label sits on the row.

### Radio rows (one of several)
- The chosen row takes `accentWash` and a filled round mark (`QIcons.chosen`); the others an empty mark (`unchosen`). Never colour alone.

### Wheel (`QWheelField`)
- A numeric wheel with its unit; the selection band is `surfaceHigh` at `control`. For height, weight, age.

---

## Containers

### Card (`QDecor.card()`)
- **Anatomy:** `surface` with a one-point `hairline` edge, corner 24, padding 20. No shadow.
- **Variants:** `color: QColors.surfaceRaised` for a pressed card or an item inside a card; `border: QColors.hairlineStrong` for one that must read as a boundary; `border: QColors.accent` for the chosen one of several.
- **Content order:** an eyebrow (optional, 15/600 `inkSecondary`), a title or a figure, supporting text (`inkSecondary`), at most one action row.
- **Rules:** one job per card. A card never holds a card: an item inside is `surfaceRaised` at `inset`.

### Pastel card (`PastelCard`, `kit.dart`)
- **Anatomy:** one pastel as the ground (`QDecor.pastel`), corner 24, padding 20, black words (it sets `onPastel` as the default text colour). No edge.
- **Inside:** a glyph in a `pastelTrack` circle (`PastelGlyph`), black bars on a `pastelTrack` track, the black button (`QPastelButton`), the mascot.
- **Which pastel:** calories lavender, protein mint, carbs lime, fat coral wherever a macro is shown; otherwise one pastel per card as decoration (`references/tokens.md` lists where each goes).

### Grouped list (`QListGroup` of `QListRow`, `kit.dart`)
- **Anatomy:** one card holding rows at least 56 tall: a 22 glyph (optional), the name (16 `ink`), a sub-line (13 `inkSecondary`), the value at the end (15 `inkSecondary`), and a chevron (`QIcons.forward`) when it opens something, or its own control (a switch). No lines between rows.
- **A row that ends something** (Log out) has its words and glyph in `accentInk`, and opens a confirmation.

### Sheet (`QSheetSlot` + `QSheetScrim` + `QSheetPanel`)
- **Anatomy:** it rises from the bottom over a 50% scrim (with an 8 sigma blur of the page); the panel is `surface`, top corners 32, a 36 × 5 `hairlineStrong` grabber; its title 24/700; one primary at the foot.
- **Dismissal:** a swipe down, a tap on the scrim, or close; all three do the same. A drag follows the finger and projects the release.
- **Tall content** (`scrolls: true`): the panel stops 24 under the top and its content scrolls, so a short phone or large text never overflows.
- **One sheet at a time.** A sheet never opens another.

### The Log sheet (`LogSheet`, `log_sheet.dart`)
- **What it is:** the orb's tap. Every way to log, one tap each, nothing a level down.
- **Anatomy, top to bottom:** "Log" / "سجّل" (24/700) and today's photo count; three pastel tiles, 96 tall at `inset` (Speak lavender, Type lime, Photo mint; a lock on Photo when today's are used); **Repeat** — recent meals as grey capsules; **Water** — glass, bottle, tea as grey circles with their names, and the day's litres at the end; **Movement** — football, walk, gym, run, other; **Ask Qamar anything**, a grey row that opens the conversation to type, with "or hold the moon to talk" under it.
- **Placement:** it rises **under the tab bar**, and its foot runs on under the bar (the last row ends above the band). The moon stays in view and answers: a tap puts the sheet away, a hold talks, a tab goes to its page, the current tab puts the sheet away.
- **A failure** (no camera, a refused permission) replaces the choices with a state card in the same sheet.

### State card (`QStateCard`) and state line (`QStateLine`)
- **State card:** for empty, error, offline, permission or a limit, where the state fills the space: a 48 grey circle with the glyph, one sentence (17/600), an optional second line (`inkSecondary`), one primary, and up to two secondaries.
- **State line:** a single-row notice at `control` on `surface`: a glyph, a sentence, and an optional way on in `accentInk` words.
- **Glyphs:** `QIcons.empty`, `error`, `offline`, `locked`, `limit`. All in white: the glyph and the words carry the meaning, never a colour.

### Empty state (`QEmptyState`, `kit.dart`)
- The mascot on a pastel disc, a title (20/700) and a line under it (`inkSecondary`), and at most one action. Centred.

---

## Figures

### Calorie gauge (`CalorieGauge`, `kit.dart`)
- **Anatomy:** on the lavender card, a thick arc a little past a half circle over the top of a white-at-a-third disc; the eaten part black on a `pastelTrack` track, filling from the start side (the right in Arabic); what is left in the middle (the hero figure, 34 in the gauge); the target under the far end. The near end carries no "0" (a lone Arabic "٠" reads as a speck).
- **Size:** `CalorieGauge.heightFor(width)` is 0.8 × the width.

### Macro tiles (`MacroTile`, `kit.dart`)
- A pastel tile per macro (protein mint, carbs lime, fat coral): its glyph in a circle at the top end, its name (16/600), a black bar, and eaten / target in figures. The figure row can carry the orb's explain mark.

### Bar (`QBar`)
- 6 tall, a capsule. On the dark, `accentInk` on a `hairline` track; on a pastel (`onPastel: true`), black on `pastelTrack`. Fills from the leading edge. Always beside its number. Over 100% it is full and the words say "over"; it never turns red.

### Hero figure (`HeroNumber`, `hero_number.dart`)
- One large figure per screen, tabular Space Grotesk (Noto Sans Arabic for Arabic-Indic digits), 56 bold (34 in the gauge), its unit beside or under it, as text. It has a spoken label ("1,240 calories left today").

### Streak ring (`StreakRingPainter`, `living_orb.dart`)
- Seven short arcs round the orb, clockwise from the top in both languages: lit days `accentInk`, today at half strength while it waits, unlit `hairline`. The arcs thicken from 3 days and again from a week.

### The moon (`LivingOrb`, `Moon`; `living_orb.dart`, `moon.dart`)
- Monochrome; its phase is the day's progress (a new moon is nothing logged, a full moon the goal met). It breathes where it is and has a soft white halo; over the goal a thin ring replaces the halo. No sparks, no drift, nothing orbiting.

### The mascot (`MoonMascot`, `mascot.dart`)
- The moon as a character in the kit's cartoon line: `mood` happy, joy or sleepy; `full: true` for the whole character (arms, a wave, sneakers, sparkles, a ground shadow; 1.2 × as tall as wide), else the face. Always on a pastel. Excluded from semantics.

### Explain mark (`ExplainMark`, `explain.dart`)
- A quiet dotted underline under a value the orb can explain (inside an `Explainable`), in the second ink on the dark and black on a pastel. A mark on a value the orb can't explain is a false promise.

---

## Page structure

### Page title (`QPageTitle`, `kit.dart`)
- A page's name at 24/700, at the top start, in a 48-tall row, with `back` when the page is under a tab and whatever the page keeps at the end (a round button, the Su chip).

### Section title (`QSectionTitle`, `kit.dart`)
- A group's heading at 20/700, with an action at the end when the group has one ("See all").

### The tab bar (`QTabBar`, `tab_bar.dart`)
- A `surfaceRaised` capsule, 66 tall, 12 above the safe area's foot: Today, Progress, [the orb], Plan, Me, as 54-point circles 8 apart. A tab's circle is `surfaceHigh` with a linear glyph; the page on show is burgundy with its bold glyph and says it is chosen. The orb's circle is black with the living moon in it (38). The orb's receipt (a credit's "+100", two seconds) and the one-time hold mark sit just above the bar's middle.
- Tab pages pad their end by `QLayout.pageBottom`; content scrolling under the bar passes under `TabBarFade`.

---

## Forms and input

- **Field:** the ground (`canvas`) inside a `hairlineStrong` edge at `control`, 14 × 16 padding; the edge white while focused and `error` red when wrong; the placeholder `inkTertiary`; a 15/500 label above when the placeholder isn't enough.
- **Validation:** inline, as the person types or on leaving the field, never only on submit. The error line sits under the field in white words (the red is the edge's).
- **Keyboard:** the right type (numbers for numbers) and action key ("Done", "Next", "Send").
- **Ask less:** one question per onboarding step; prefill what is known; anything optional is one tap to skip and never blocks.

## Feedback

| Situation | Show |
|---|---|
| Waiting under 300 ms | nothing (the result appears) |
| Waiting over 300 ms | a breathing dot and a specific phrase ("Reading your meal…") |
| Long work (over about 5 s) | the phrase and a way to cancel |
| A result the person can see | the result itself; no toast |
| A credit | the orb's receipt: the coin and "+100" over the bar for two seconds, no haptic |
| A reversible action | done at once, with a quiet **Undo** (`inkSecondary`) for 5 s |
| An error | a state line or card: what happened, what to do, one button. No codes |
| Offline | a state line ("You're offline. Changes will save when you're back.") |
