# Tokens

Every value qamar-design uses. In Qamar these live in `app/lib/theme/` (`colors.dart`, `text_styles.dart`, `app_theme.dart`, `motion.dart`, `layout.dart`, `icons.dart`). Screens use the names, never the values: no hex, no radius number and no raw `Icon(Icons.…)` is written outside `lib/theme/` (tests hold all three).

## Contents
- Colour: the ground and what sits on it
- Colour: the pastels
- Colour: burgundy
- Contrast table
- Type
- Space, radii, targets
- The tab bar
- Motion

## Colour: the ground and what sits on it

The Nutri AI kit's greys. The ground is one near-black, and everything that sits on it is a step lighter: a card, then a control, then a control's circle. Flat: no shadow, no glass, no gradient.

| Token | Hex | What it is |
|---|---|---|
| `canvas` | `#121212` | the page's ground (the kit's grey 600); also the black of a pastel's words and of the kit's black buttons |
| `surface` | `#232220` | a card, a grouped list, a sheet, a dialog, a meal card (grey 500) |
| `surfaceRaised` | `#2F2F2F` | a control on the ground or on a card: the tab bar's pill, a back circle, a sign-in button, a secondary button, a chip, the composer, an item inside a card (grey 400) |
| `surfaceHigh` | `#474747` | a circle on a control: the tab bar's circles, the microphone beside the field, a stepper on an item; a switch's track when off; a pressed control (grey 300) |
| `ink` | `#FFFFFF` | the words and glyphs on the dark |
| `inkSecondary` | `#C3C3C3` | what supports them: a sub-line, a value at a row's end, an eyebrow, a footer (grey 200) |
| `inkTertiary` | `#9A9A9A` | a caption, a placeholder, the estimate note; the floor for readable text |
| `inkDisabled` | `#7A7A7A` | a label with nothing to do: below AA on purpose, at least 3:1 on the card and the control |
| `onInk` | = `canvas` | words on white: the segmented track, a white bubble, the shutter's ring |
| `hairline` | = `surfaceRaised` | a card's edge, a divider, a bar's track on the dark |
| `hairlineStrong` | = `surfaceHigh` | a field's edge, the grabber, a chosen card's edge |
| `error` | `#C93838` | a field's edge when something is wrong with it; its words stay in `ink` |
| `scrim` | `#000000` @ 50% | what a sheet or a dialog dims (and, with an 8 sigma blur, softens) the page with |
| `overPhoto` / `overPhotoPressed` | `#121212` @ 50% / 70% | a control over a photo or the camera |

## Colour: the pastels

The kit's four accents. A pastel is always a card's whole ground (or a band across a card's top, or a tile nested in another pastel) with black words on it. Never a word, a line or a border on the dark.

| Token | Hex | Where |
|---|---|---|
| `lavender` | `#DDC0FF` | calories: the calorie card and its gauge; the welcome; the person's chat bubble; the week's card; the plan's day card; Qamar+'s headline card; Ramadan's time |
| `lime` | `#F5F378` | carbs; a gift (the earned month, the free week); the wallet's balance; the streak; the plan card on Qamar+; the explain sheet's "what to do" |
| `mint` | `#45C588` | protein; the week's figure on Progress; the quest; a dish on the reveal; the nudge question |
| `coral` | `#FF6F43` | fat; the billing moment, the one card whose time runs out |
| `onPastel` | = `canvas` | words and glyphs on a pastel |
| `onPastelSecondary` | `#121212` @ 80% | what supports them on a pastel |
| `pastelTrack` | `#121212` @ 12% | a bar's unlit track on a pastel; the circle behind a glyph on a pastel (`PastelGlyph`) |

When a macro is shown the colours mean the macro: calories lavender, protein mint, carbs lime, fat coral, everywhere (Today, the proposal, the reveal). Elsewhere they are the kit's decoration, one pastel to a card.

## Colour: burgundy

Qamar's own colour, where the kit has its orange. It marks what a finger does and what has been chosen. It never says how something went.

| Token | Hex | Where |
|---|---|---|
| `accent` | `#8E1B34` | the fill of the one thing to do: the primary button, the send circle, a chosen chip, the chosen segment, a switch that is on, the tab the person is on. White on it is 8.9:1. One burgundy fill to a screen, the tab bar aside |
| `accentPressed` | `#751529` | the fill while it is pressed |
| `accentInk` | `#E8768D` | burgundy as a word or a line on the dark: a text action (Got it, Restore purchase, a code link), the streak line, a bar filling on a dark card, the orb's streak ring. Never body text |
| `accentWash` | `#8E1B34` @ 28% | a chosen row, the text selection |
| `onAccent` | `#FFFFFF` | words and glyphs on burgundy |

**Not tokens, and allowed only here:** `QBrandMarks.google*`, the four colours of Google's "G" on the account sheet's sign-in button; the moon's own greys in `widgets/moon.dart`; pixels of a photograph.

## Contrast table

WCAG 2.x, the text colour on each ground (4.5:1 is AA for text, 3:1 for marks and large text).

| on | canvas | surface | surfaceRaised | surfaceHigh |
|---|---|---|---|---|
| `ink` | 18.7 | 15.9 | 13.4 | 9.3 |
| `inkSecondary` | 10.6 | 9.0 | 7.6 | 5.3 |
| `inkTertiary` | 6.7 | 5.6 | 4.8 | 3.3 (not for text) |
| `inkDisabled` | 4.4 | 3.7 | 3.1 | 2.2 |
| `accentInk` | 6.6 | 5.6 | 4.7 | 3.3 (not for text) |
| `error` | 3.7 | 3.1 | 2.6 | — (a mark, not text) |

On the pastels, black (`onPastel`) is 11.6:1 on lavender, 16.0 on lime, 8.6 on mint and 6.8 on coral; `onPastelSecondary` is at least 5.1:1 on all four. White on `accent` is 8.9:1, on `accentPressed` 11.1:1. `onInk` on white is 18.7:1.

## Type

Space Grotesk (the kit's face, SIL OFL, bundled at 400/500/600/700) for Latin; Noto Sans Arabic for Arabic and the Arabic-Indic digits; Inter last, for the odd mark Space Grotesk does not draw. Every style names all three. Nothing is tracked.

| Role | Size / line | Weight | Builder |
|---|---|---|---|
| Large title | 34 / 51 | 700 | `QText.display(size: 34)` |
| Title 1 | 28 / 42 | 700 | `display(28)` |
| Title 2: a page's or a sheet's name | 24 / 36 | 700 | `display(24)` |
| Title 3: a group's heading, a card's name | 20 / 30 | 700 | `display(20)` |
| Headline: a card's title on a pastel | 18 / 27 | 600 | `body(18, w600)` |
| Body | 17 / 24 | 400 | `body(17)` |
| Callout: a button's label, a row's name | 16 / 24 | 500–600 | `body(16)` |
| Subheadline, body 2 | 15 / 22 | 400–600 | `body(15)`; the eyebrow is 15 / 22 w600, sentence case |
| Footnote: a sub-line, a caption | 13 / 19 | 400 | `body(13)` |
| Badge | 12 / 16 | 500–600 | `body(12)`; nothing under 12 |
| Figures | 20, 24, 28, 34, 48, 56 | 500–700, tabular | `QText.number`; `HeroNumber` for a screen's one hero (56, or 34 inside the gauge) |

## Space, radii, targets

- **Spacing** on a 4-point grid: 4, 8, 12, 16, 20, 24, 32. The page's side margin is 20; cards on a page are 12–16 apart; Today's zones 12.
- **Radii** (`QRadii`), four and the pill: `control` 12 (a button, a field, a notice, a wheel's band), `inset` 16 (a tile nested in a card, a photo, a chat bubble's neighbour, an item inside a card), `card` 24 (a card, a dialog, a chat bubble), `sheet` 32 (a sheet's top corners), `pill` (chips, the segmented control, the tab bar, a capsule). No corner is written as a number outside the theme.
- **Buttons**: rounded rectangles at `control`. Large 50 tall (the primary), medium 44 (a secondary), small 36–40 (a compact action in a card). Every touch is at least 48 × 48 whatever is drawn (`QTapArea`).
- **Fields**: the ground inside a `hairlineStrong` edge at `control`, white while focused, `error` when wrong; a 15 w500 label above; the placeholder in `inkTertiary`.

## The tab bar

A floating pill of `surfaceRaised`, 66 tall, 12 above the safe area's foot, holding five 54-point circles 8 apart: Today, Progress, the orb, Plan, Me. A tab's circle is `surfaceHigh` with its linear glyph; the page on show is `accent` with the bold glyph. The orb's circle is black, the living moon inside it at 38. The band it floats in (`QLayout.tabBand`, 78) is what a tab page pads its list by; content scrolling under it passes under a fade.

## Motion

Unchanged from the springs every screen already uses (`QSpring`): critically damped settle (response 0.35 s) for everything, a little bounce only after a flick; sheets rise on the settle spring and follow a drag; the orb springs back into its circle from wherever the finger let it go. Press: scale 0.97 over 120 ms (a dim to 70% with reduce-motion). A state change (a segment, a tab) is 180–220 ms ease-out. Reduce-motion turns every movement into a 150 ms cross-fade.
