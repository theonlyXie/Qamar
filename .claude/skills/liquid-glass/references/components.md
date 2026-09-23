# Components

Each entry gives what the component is for, its anatomy, its states and its name in Qamar's kit (`app/lib/widgets/common.dart` unless noted). Every component has a press state, a spoken label and a 48 × 48 target. Colours are tokens (`references/tokens.md`), and glass is described in `references/glass.md`.

## Contents
- Buttons: primary, secondary, text, burgundy words, legal links, pill, round icon, glass icon, back/close
- Choices: chips, segmented control, switch, radio rows, wheel
- Containers: card, grouped list, sheet, state card, state line
- Progress and figures: bar, streak ring, moon, hero numeral, explain mark
- Forms and input
- Feedback: loading, success, errors, undo

---

## Buttons

### Primary: the one thing to do (`QPrimaryButton`)
- **Anatomy:** a burgundy glass capsule (`accent`, with the lens and a brighter rim), a white label (`onAccent`, 17/600) and an optional leading glyph. It's 52 tall, or 48 in a dense card, and spans the content width or hugs its label with 24 of side padding.
- **States:**
  - Pressed: `accentPressed` and scale 0.97, on touch-down.
  - Disabled: not burgundy, because there's nothing to act on. `QDisabled.fill` with `QDisabled.label` and no press response. Say why nearby if it isn't obvious.
  - Busy: the label becomes a specific present-tense phrase ("Logging…"), and the width stays the same.
- **Rules:**
  - One per screen, or one per sheet while it's open: the screen's one burgundy action. (In the conversation, the send circle is burgundy once there is text, and "Confirm and log" on a reading is the primary.)
  - Never destructive: a destructive action is a secondary button with an explicit verb.
  - Its label starts with a verb ("Log it", "Start", "Confirm and log").

### Secondary: a second choice (`QOutlineButton`)
- **Anatomy:** a clear glass capsule (white glass, the lens and the specular edge, no tint) with an `ink` label (15/500), drawn 44 tall, or 32 beside a figure, with the touch always 48. It can carry a leading glyph. On a card it doesn't blur.
- **Pressed:** a brighter fill (`glassFillPressed`) and a 0.97 scale.
- **Use:** "Swap", "Why?", "Add 250 ml", and a destructive action with an explicit verb.
- **The name is historical.** It is drawn as glass now, not as an outline.

### Text: a quiet action
- **Anatomy:** `inkSecondary` 15/500 with no container, but still a 48 pt target (`QTapArea`).
- **Use:** "Later", "Not now", "Cancel", "Skip", "Undo".

### Burgundy words: a way on
- **Anatomy:** `accentInk` 15/600 with no fill, and still a 48 pt target.
- **Use:** a notice's way on (`QStateLine`'s action, such as "See Qamar+"), and a turn's suggested next step in the conversation, on a clear glass chip.
- **Rule:** `accentInk` colours the action's own words, never the sentence around them.

### Legal links (`QLegalLink`)
- **Anatomy:** `inkTertiary` with an underline.
- **Why not burgundy:** Terms and Privacy are not actions in the flow.

### Pill (`QPillButton`)
- **Anatomy:** a burgundy glass capsule, 40 tall, with a white 15/600 label.
- **Use:** a compact primary inside a card, such as "Try it" on a quest. It still counts as the screen's one primary.

### Round icon, on content (`QRoundIconButton`)
- **Anatomy:** a clear glass disc, without blur, with an `ink` glyph about half the disc's size.
- **Use:** steppers (− / +), inline edits. The disc may be as small as 32, but the target is always 48.

### Glass icon, floating (`QGlass(shape: circle)` in a `QTapArea`)
- **Anatomy:** a 44 glass circle that blurs what's behind it, with a 22 `ink` glyph.
- **Use:** close/back over a page, the chat header, camera controls (the thin fill over the viewfinder, with a dim).

### Back and close (`QBackButton`, glass close)
- **Placement:** always on the leading edge. Back uses `QIcons.back`, which mirrors in Arabic; close uses `QIcons.close`.
- **Labels:** no "Back" text. The spoken labels are "Back" and "Close".
- **One of each at most:** never Cancel, Done and Back together. A sheet has close (leading) and a primary.

---

## Choices

### Chips (`QPillChip`)
- **Anatomy:** a capsule, 36–40 tall with a 48 target, and a 15/500 label.
- **States:** chosen is **burgundy glass** (`accent`, white label), as many as are chosen, because a chosen chip marks what is chosen rather than what to do; unchosen is clear glass with an `ink` label; pressed scales to 0.97 with a brighter fill.
- **Use:** picking one or a few of up to about 6 options (goals, activity kinds, suggestions).
- **Chat suggestions** are chips too: clear glass, in one scrolling row with an end fade.
- **A turn's suggested next step** in the conversation is a clear glass chip with `accentInk` words (600), not a burgundy fill.

### Segmented control (`QLangToggle`, the wallet's tabs)
- **Anatomy:** a clear glass capsule track. The chosen segment is a neutral raised glass pill (a step brighter, with a strong edge) under `ink` words; the others read in `inkSecondary`.
- **Never burgundy:** a mode is not an action.
- **Motion:** 200 ms between segments.
- **Use:** two or three mutually exclusive modes (English / العربية, the wallet's tabs).

### Switch
- **Style:** the theme's switch. On is a burgundy track (`accent`) with a white thumb; off is a `surfaceHigh` track with a `hairlineStrong` edge and a white thumb.
- **Rules:**
  - The whole row is the target, and the label sits on the row.
  - Never let the switch alone say what it controls.

### Radio rows (one of several, in a grouped list)
- **Anatomy:** the chosen row takes `accentWash`, and its mark is filled in `accentInk`. The others have no mark.
- **Why a mark as well as the wash:** a choice never rests on colour alone.

### Wheel (`QWheelField`)
- **Anatomy:** a numeric wheel with its unit; the selection band is `surfaceHigh` with an inset radius.
- **Use:** height, weight, age, and anything with a physical range.

---

## Containers

### Card (`QDecor.card()`)
- **Anatomy:** a glass panel: the `glassPanelTop` → `glassPanel` fill, the `QGlassRim` edge, radius 24, 20 padding. No shadow and no blur.
- **Raised form:** `QDecor.card(color: QColors.surfaceRaised)` gives a flat `glassRaised` fill, for a pressed card or a pane standing inside another.
- **Increase Contrast:** a card keeps its pane. It already sits over black and has the rim.
- **Content order:**
  - an eyebrow (optional);
  - a lead line or the hero numeral;
  - supporting text (`inkSecondary`, 15/20);
  - at most one action row.
- **Rules:**
  - One job per card. If a card needs two buttons of equal weight, it's two cards, or one is the page's primary.
  - A card never holds a card. Group with space and hairline dividers, or set a block into it as an inset (`glassInset`).

### Grouped list
- **Anatomy:** one glass panel holding 56 tall rows.
  - Leading: a 20 glyph (optional), then the label (17/400 `ink`).
  - Trailing: the value (15/400 `inkSecondary`, tabular), then a chevron (`QIcons.forward`) if it navigates.
- **Dividers:** hairlines between rows, inset to the label's start.
- **A chosen row** takes `accentWash`, with its mark (see "Radio rows").
- **Destructive rows** read in `ink` with an explicit verb ("Delete my account") and open a confirmation.

### Sheet (`QSheetSlot` + `QSheetScrim`)
- **Anatomy:**
  - It rises from the bottom with the `scrim` behind it.
  - The panel is frosted glass: a `glassSheet` ground over a sigma-24 blur, with the pane's lens, the strong rim, a top radius of 32 and a 36 × 5 `hairlineStrong` grabber. Under Increase Contrast it turns solid (`glassSolid`).
  - The title is 22/700.
  - Content scrolls, and there is one primary at the bottom.
- **Dismissal:** swipe down, tap the scrim, or close. All three do the same thing.
- **Unsaved changes:** confirm only if dismissing loses real input.
- **One sheet at a time.** A sheet never opens another sheet; it replaces its content or pushes a step inside itself.

### State card (`QStateCard`) and state line (`QStateLine`)
- **State card anatomy:** for empty, error, offline or a limit reached, where the state fills the space:
  - a 48 glyph circle (`surfaceRaised` with a `hairlineStrong` edge);
  - one sentence (17/22);
  - an optional second line (`inkSecondary`);
  - one button.
- **State line anatomy:** a single-row inline notice with a glyph, a sentence and an optional way on in `accentInk` words (600).
- **Glyphs:** `QIcons.empty`, `error`, `offline`, `locked`, `limit`. The glyph and the words carry the meaning, never a colour: an error isn't red, and nothing turns burgundy to warn.

---

## Progress and figures

### Bar (`QBar`)
- **Anatomy:** 4 tall, a capsule; an `accentInk` fill on a quiet `hairline` track.
- **Direction:** fills from the leading edge (right in Arabic).
- **Rules:**
  - Always next to its number.
  - Over 100%, the bar is full and the words say "over". It keeps its colour: a reading over target is not red.

### Streak ring (`StreakRingPainter`, `app/lib/widgets/living_orb.dart`)
- **Anatomy:** seven short arc segments around the orb, one per day of the current week of the run, clockwise from the top in both languages, with a small gap between them.
- **States:**
  - Lit days: `accentInk`.
  - Today, while it is still waiting for its meal: `accentInk` at half strength.
  - Unlit days: `hairline`.
- **Weight:** the arcs thicken a little from 3 days and again from a full week, so a longer run shows by weight, not by a new colour. At seven every arc is lit, and the week starts over.

### Moon (`Moon`, `LivingOrb`, `app/lib/widgets/moon.dart` and `living_orb.dart`)
- **Anatomy:** a monochrome moon. Its phase is the day's progress (new moon means nothing logged; full moon means the goal is met).
- **Glow:** a white halo with no colour. Over the goal, the halo is replaced by a 1.5 pt ring at 1.18× the orb's size.
- **In the tree,** a soft burgundy glow (`accent` at about 35%, radial) sits behind the centre moon. The moon itself is never recoloured.

### Hero numeral (`HeroNumber`, `app/lib/widgets/hero_number.dart`)
- **Anatomy:** one large numeral in the UI face (Inter, with Arabic-Indic digits from Noto Sans Arabic): 56 (`HeroNumber.heroSize`), bold, tabular figures, tight leading, `ink`.
- **Unit:** beside or under it in `inkSecondary`, as text, in reading order.
- **Use:** the one hero figure on a screen, with 32–48 of air around it.
- **Semantics:** it has a label ("1,240 calories left today").

### Explain mark (`ExplainMark`, `app/lib/widgets/explain.dart`)
- **Anatomy:** a quiet dotted underline under a value, in softened `inkSecondary`: the classic mark for "this has a definition".
- **Use:** only on a value the orb can explain (inside an `Explainable`). A mark on a value the orb can't explain is a false promise.

---

## Forms and input

- **Field anatomy:**
  - `surfaceRaised` fill, radius 18, 52 tall;
  - label above in the eyebrow style, or the placeholder (`inkTertiary`) when the meaning is obvious;
  - `accentInk` cursor and handles, `accentWash` selection;
  - focus ring 1.5 pt `hairlineStrong`.
- **Validation:**
  - Inline, as the person types or on leaving the field, never only on submit.
  - The error line sits under the field: glyph plus sentence, in `ink`.
- **Keyboard:** use the right keyboard type (numbers for numbers) and the right action key ("Done", "Next", "Send").
- **Ask less:**
  - One question per screen in onboarding.
  - Prefill everything known.
  - Anything optional is skippable with one tap and never blocks.

## Feedback

| Situation | Show |
|---|---|
| Waiting under 300 ms | nothing (the result appears) |
| Waiting over 300 ms | a breathing dot plus a specific phrase ("Reading your meal…") |
| Long work (over about 5 s) | the phrase plus a way to cancel |
| A result the person can see | the result itself; no toast |
| A background result | a small glass capsule at the top or bottom for about 3 s, with glyph and words |
| A reversible action | done at once, with a quiet **Undo** (`inkSecondary`) in a capsule for 5 s |
| An error | a state line or card: what happened, what to do, one button. No codes |
| Offline | a state line ("You're offline. Changes will save when you're back.") |
