# Components

Each entry gives what the component is for, its anatomy, its states and its name in Qamar's kit (`app/lib/widgets/common.dart` unless noted). Every component has a press state, a spoken label and a 48 × 48 target. Colours are tokens (`references/tokens.md`).

## Contents
- Buttons: primary, outline, text, pill, round icon, glass icon, back/close
- Choices: chips, segmented toggle, switch, wheel
- Containers: card, grouped list, sheet, state card, state line
- Progress: bar, dot ring, moon, dot number
- Forms and input
- Feedback: loading, success, errors, undo

---

## Buttons

### Primary: the one thing to do (`QPrimaryButton`)
- **Anatomy:** a white capsule (`ink`), a black label (`onInk`, 17/600) and an optional leading 20 pt glyph. It's 52 tall, or 48 in a dense card, and spans the content width or hugs its label with 24 of side padding.
- **States:**
  - Pressed: scale 0.97 on touch-down.
  - Disabled: `QDisabled.fill` with `QDisabled.label` and no press response. Say why nearby if it isn't obvious.
  - Busy: the label becomes a specific present-tense phrase ("Logging…"), and the width stays the same.
- **Rules:**
  - One per screen, or one per sheet while it's open.
  - Never destructive: a destructive action is an outline button with an explicit verb.
  - Its label starts with a verb ("Log it", "Start", "Confirm and log").

### Outline: a second choice (`QOutlineButton`)
- **Anatomy:** a transparent capsule with a `hairlineStrong` edge and an `ink` label (15/500), drawn 44 tall, or 32 beside a figure, with the touch always 48. It can carry a leading glyph.
- **Pressed:** a `surfaceRaised` fill and a 0.97 scale.
- **Use:** "Swap", "Why?", "Add 250 ml", and a destructive action with an explicit verb.

### Text: a quiet action
- **Anatomy:** `inkSecondary` 15/500 with no container, but still a 48 pt target (`QTapArea`).
- **Use:** "Not now", "Cancel", "Skip", and legal links (`QLegalLink`).

### Pill (`QPillButton`)
- **Anatomy:** a white capsule, 40 tall, with a black 15/600 label.
- **Use:** a compact primary inside a card, such as "Try it" on a quest. It still counts as the screen's one primary.

### Round icon, on content (`QRoundIconButton`)
- **Anatomy:** a `surfaceRaised` disc (`surfaceHigh` when pressed) with an `ink` glyph at 0.55 × size.
- **Use:** steppers (− / +), inline edits. The disc may be as small as 32, but the target is always 48.

### Glass icon, floating (`QGlass(shape: circle)` in a `QTapArea`)
- **Anatomy:** a 44 glass circle with a 22 `ink` glyph.
- **Use:** close/back over a page, the chat header, camera controls (clear glass over the viewfinder).

### Back and close (`QBackButton`, glass close)
- **Placement:** always on the leading edge. Back uses `QIcons.back`, which mirrors in Arabic; close uses `QIcons.close`.
- **Labels:** no "Back" text. The spoken labels are "Back" and "Close".
- **One of each at most:** never Cancel, Done and Back together. A sheet has close (leading) and a primary.

---

## Choices

### Chips (`QPillChip`)
- **Anatomy:** a capsule, 36–40 tall with a 48 target, and a 15/500 label.
- **States:** selected is **inverted** (white fill, black label); unselected has a `hairline` edge and an `ink` label; pressed scales to 0.97.
- **Use:** picking one or a few of up to about 6 options (goals, activity kinds, suggestions).
- **Chat suggestions** are chips too: `surfaceRaised` fill with a `hairline` edge, in one scrolling row with an end fade.

### Segmented toggle (`QLangToggle`)
- **Anatomy:** a glass capsule track; the selected segment is white with a black label.
- **Motion:** 200 ms between segments.
- **Use:** two or three mutually exclusive modes (English / العربية).

### Switch
- **Style:** the theme's switch. On is a white track with a black thumb; off is a `surfaceHigh` track with a `hairlineStrong` edge and a white thumb.
- **Rules:**
  - The whole row is the target, and the label sits on the row.
  - Never let the switch alone say what it controls.

### Wheel (`QWheelField`)
- **Anatomy:** a numeric wheel with its unit; the selection band is `surfaceHigh` with an inset radius.
- **Use:** height, weight, age, and anything with a physical range.

---

## Containers

### Card (`QDecor.card()`)
- **Anatomy:** `surface` fill, `hairline` edge, radius 24, 20 padding. No shadow and no gradient.
- **Content order:**
  - an eyebrow (optional);
  - a lead line or figure;
  - supporting text (`inkSecondary`, 15/20);
  - at most one action row.
- **Rules:**
  - One job per card. If a card needs two buttons of equal weight, it's two cards, or one is the page's primary.
  - A card never holds a card. Group with space and hairline dividers.

### Grouped list
- **Anatomy:** one card holding 56 tall rows.
  - Leading: a 20 glyph (optional), then the label (17/400 `ink`).
  - Trailing: the value (15/400 `inkSecondary`, tabular), then a chevron (`QIcons.forward`) if it navigates.
- **Dividers:** hairlines between rows, inset to the label's start.
- **Destructive rows** read in `ink` with an explicit verb ("Delete my account") and open a confirmation.

### Sheet (`QSheetSlot` + `QSheetScrim`)
- **Anatomy:**
  - It rises from the bottom with the `scrim` behind it.
  - The panel is `surface` with a top radius of 32 and a 36 × 5 `hairlineStrong` grabber.
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
- **State line anatomy:** a single-row inline notice with a glyph, a sentence and an optional text action.
- **Glyphs:** `QIcons.empty`, `error`, `offline`, `locked`, `limit`. The glyph and the words carry the meaning, never a colour.

---

## Progress

### Bar (`QBar`)
- **Anatomy:** 4 tall, a capsule; white fill on a `surfaceHigh` track.
- **Direction:** fills from the leading edge (right in Arabic).
- **Rules:**
  - Always next to its number.
  - Over 100%, the bar is full and the words say "over". A hollow dot or an outline can mark the excess, but it's never red.

### Dot ring
- **Anatomy:**
  - 24 or 36 round dots, clockwise from 12 o'clock in both languages;
  - lit = `ink`, half = 50%, off = `dotOff`;
  - lit count = round(p × N), with at least 1 dot when p > 0.
- **States:**
  - Complete: one outward breath, staggered 12 ms per dot.
  - Over target: hollow dots continue in an outer orbit.
- **The orb's streak ring** is seven larger dots, one per day. Today's dot is at 50% while at risk.

### Moon (`Moon`, `LivingOrb`, `app/lib/widgets/moon.dart` and `living_orb.dart`)
- **Anatomy:** a monochrome moon. Its phase is the day's progress (new moon means nothing logged; full moon means the goal is met).
- **Glow:** a white halo with no colour. Over the goal, the halo is replaced by a 1.5 pt ring at 1.18× the orb's size.

### Dot number (`DotNumber`, `app/lib/widgets/dot_number.dart`)
- **Use:** the one hero numeral on a screen, at least 40 tall, with its unit beside it in the eyebrow style on the same baseline, in reading order.
- **Semantics:** it has a label ("1,240 calories left today").

---

## Forms and input

- **Field anatomy:**
  - `surfaceRaised` fill, radius 18, 52 tall;
  - label above in the eyebrow style, or the placeholder (`inkTertiary`) when the meaning is obvious;
  - `ink` cursor;
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
| A reversible action | done at once, with **Undo** in a capsule for 5 s |
| An error | a state line or card: what happened, what to do, one button. No codes |
| Offline | a state line ("You're offline. Changes will save when you're back.") |
