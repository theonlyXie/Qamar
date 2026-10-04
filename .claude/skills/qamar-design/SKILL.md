---
name: qamar-design
description: The house design language for our products, built on the Nutri AI kit and carrying Qamar's own brand. A near-black ground with flat grey cards and controls, four pastel cards (lavender, lime, mint, coral) with black words where the figures that matter sit, one burgundy for the thing to do, Space Grotesk with Noto Sans Arabic, Iconsax icons, a floating tab bar with the living moon in its middle, a Log sheet, and the moon mascot. Arabic-first, spring motion, the fastest path always wins. Use this skill whenever you design, build, restyle, review, simplify or screenshot any screen, component, card, chat, onboarding step, sheet, tab, icon, animation, illustration or colour in one of our apps (Qamar first, Flutter by default). Use it even when the request only says "make it look better", "fix the UI", "add a button", "new screen", "redesign", "make it simpler", "polish", "it feels lifeless", or names a colour (burgundy, a pastel), a font, an icon, the orb, the mascot or the tab bar. Also use it to review a UI diff or screenshot for consistency, simplicity, RTL or accessibility.
---

# Qamar design

**A dark ground, flat grey shapes on it, a pastel card for what matters, one burgundy thing to do. The moon is the brand.**

This is our design language. It takes its look from the **Nutri AI kit** (a community Figma kit for a food and calorie tracker: dark, flat, rounded, pastel cards with black words, a cartoon line for characters) and keeps what is ours:
- **the moon**: the living orb in the tab bar, and the moon mascot where the kit draws its fruit characters;
- **burgundy**, where the kit has its orange;
- **the name, Qamar / قمر**, and the voice: Egyptian Arabic first.

It serves the owner's standing rule: **no extra steps, no tech complication; the faster and simpler, always the better.** People should feel calm, fast and in control. A screen that feels busy, clever or technical is wrong, however good it looks.

Qamar (Flutter, Arabic-first) is the reference implementation; its kit is described in `references/flutter.md`.

## The six laws

1. **The dark, four pastels and one burgundy.**
   - The ground is one near-black (`canvas`). What sits on it is a step lighter: a card (`surface`), a control (`surfaceRaised`), a control's circle (`surfaceHigh`).
   - A **pastel** (lavender, lime, mint, coral) is always a whole card's ground, or a band or tile inside one, with **black words** on it. Never a word, a line or a border on the dark.
   - Where macros are shown, the pastels mean the macros everywhere: calories lavender, protein mint, carbs lime, fat coral. Elsewhere they are decoration, one pastel to a card.
   - **Burgundy** marks the one thing to do and what has been chosen: the primary button, the send circle, a chosen chip or segment, a switch that is on, the tab the person is on. One burgundy fill to a screen, the tab bar aside. It never shows status.
   - There are no success, warning or error colours. A glyph and words carry state; a field that is wrong has a red edge only, with its words in white.
2. **Flat.** No glass, no blur on a surface, no shadow, no gradient. A surface says what it is by its grey step and its shape. The only drawing with depth is the moon (the orb and the mascot) and photographs. Sheets and dialogs dim and soften the page behind them (a 50% scrim over an 8 sigma blur); that is the only blur.
3. **One of everything.**
   - One icon family: **Iconsax**, linear at rest, bold only for what is chosen or on.
   - One face: **Space Grotesk** for Latin, **Noto Sans Arabic** for Arabic, stacked into one style with Inter as the last fallback.
   - One primary button per screen. One hero per screen: the calorie gauge, a large figure, or the mascot.
4. **Motion is physics.** Critically damped springs, no bounce unless a finger threw it. Feedback on touch-down. Everything interruptible. Reduce Motion turns movement into a short fade and stops every loop.
5. **The fastest path wins.** Default instead of asking, act instead of confirming, offer undo instead of warning. No jargon. Every common task is at most two taps from where the person is: the orb's tap is the Log sheet, with every way to log on it.
6. **Arabic is not a translation.** Every screen is designed right to left first and checked left to right. Arabic is never tracked. Arabic-Indic digits are a setting, never an accident.

When a rule here conflicts with a request, follow the request but say which rule it breaks and why. When two rules conflict, the earlier law wins.

## How to work

1. **Name the screen's job in one sentence.** If you can't, the screen does too much; split it or cut it.
2. **Pick its one primary action** (the burgundy button) **and its one hero** (the gauge, a figure, the mascot). Put the figures that matter on a pastel card. Everything else is grey and quiet.
3. **Build only from the kit.** Tokens for colour, type, space and radius; components for buttons, chips, rows, cards, sheets and states. A raw `Color(0x…)`, an off-scale font size, a radius written as a number, a Material `Icons.` glyph or a hand-rolled button is a bug. Tests enforce this in Qamar (`references/flutter.md`).
4. **Count the taps** for the screen's main task, from app open. Remove every step that isn't a real decision.
5. **Check the copy** in both languages: every word of jargon becomes what it means for the person ("Words" below).
6. **Render it** in English and Arabic at phone width, and a short phone (375 × 667). Look at the images and check them against `references/review.md` before calling it done.

## Colour

Dark is the only mode. The exact values, the contrast table and what each token is for are in `references/tokens.md`.

| Token | Value | Use |
|---|---|---|
| `canvas` | `#121212` | the page's ground; the black of a pastel's words |
| `surface` | `#232220` | a card, a grouped list, a sheet, a dialog |
| `surfaceRaised` | `#2F2F2F` | a control: the tab bar, a button, a chip, a field, the composer; an item inside a card |
| `surfaceHigh` | `#474747` | a circle on a control: the tab bar's circles, a stepper; a pressed control |
| `ink` / `inkSecondary` / `inkTertiary` / `inkDisabled` | `#FFFFFF` / `#C3C3C3` / `#9A9A9A` / `#7A7A7A` | words on the dark / what supports them / captions, placeholders (the floor for text) / nothing to do |
| `lavender` / `lime` / `mint` / `coral` | `#DDC0FF` / `#F5F378` / `#45C588` / `#FF6F43` | pastel card grounds: calories / carbs / protein / fat, and the kit's decoration |
| `onPastel` / `onPastelSecondary` / `pastelTrack` | `canvas` / black 80% / black 12% | words on a pastel / what supports them / a bar's track and a glyph's circle on a pastel |
| `accent` / `accentPressed` | `#8E1B34` / `#751529` | the burgundy fill, and pressed. White on it is 8.9:1 |
| `accentInk` | `#E8768D` | burgundy as a word or line on the dark: a way on ("Got it", "See Qamar+"), the streak line, the orb's streak ring. Never body text |
| `accentWash` | burgundy 28% | a chosen row; the text selection |
| `hairline` / `hairlineStrong` | = `surfaceRaised` / = `surfaceHigh` | a card's edge, a divider / a field's edge, the grabber |
| `error` | `#C93838` | a field's edge when it is wrong; never words |
| `scrim` | black 50% | what a sheet or dialog dims the page with |

**Rules**
- **Grey is hierarchy.** At most four text levels on a screen. `inkTertiary` is the floor for anything to be read.
- **A pastel card is where the eye goes.** Put the day's figures there (the calorie card, the macro tiles, the week's figure); don't spend a pastel on chrome.
- **Two burgundies, two jobs.** `accent` is a fill with white on it; on the dark it is too dim to read as a word, so burgundy words and lines are `accentInk`.
- **Quiet actions stay grey.** Later, Not now, Cancel, Undo are `inkSecondary`. Legal links are `inkTertiary`, underlined.
- **Meaning is never colour alone.** Every state also has a glyph, a shape or words.
- **The only other colours** are photographs, the moon's own drawing, and Google's "G" on the sign-in button.

## Surfaces

- **Cards** (`QDecor.card()`, `PastelCard`): `surface` with a one-point `hairline` edge, or a pastel with no edge; corner 24; padding 20 (16 in a tight tile). No shadow.
- **Controls** sit on the ground or on a card as `surfaceRaised` (`QSurface`): a button, a chip, a field, a back circle. A control on a control is `surfaceHigh`. Pressed is a step lighter.
- **Inside a pastel**, a nested tile is another pastel or white at a third; a glyph sits in a `pastelTrack` circle (`PastelGlyph`); a bar's track is `pastelTrack` and its fill black.
- **Sheets** (`QSheetPanel` in a `QSheetScrim`): `surface`, top corners 32, a grabber, rising from the bottom over the scrim. Content that could be taller than a short phone scrolls (`scrolls: true`).
- **Over a photo or the camera**, controls are `overPhoto` (the dark at half), so the picture still shows.
- **Where content scrolls under the tab bar**, it passes under a fade (`TabBarFade`), never a line.

## Type

Space Grotesk (SIL OFL) at 400/500/600/700 for Latin; Noto Sans Arabic for Arabic and its digits; Inter last. All bundled.

| Role | Size / line | Weight |
|---|---|---|
| Large title | 34/51 | 700 |
| Title 1 | 28/42 | 700 |
| Title 2: a page's or a sheet's name | 24/36 | 700 |
| Title 3: a group's heading, a card's name | 20/30 | 700 |
| Headline: a title on a pastel | 18/27 | 600 |
| Body | 17/24 | 400 |
| Callout: a button, a row | 16/24 | 500–600 |
| Subheadline, body 2, the eyebrow | 15/22 | 400–600 |
| Footnote: a sub-line, a caption | 13/19 | 400 |
| Badge | 12/16 | 500–600 |
| Figures (tabular) | 20, 24, 28, 34, 48, 56 | 500–700 |

**Rules**
- **No other sizes;** nothing under 12. Weights 400 to 700 only.
- **Nothing is tracked,** in either language, and nothing is uppercased: the eyebrow is 15/600 in sentence case.
- **One hero figure per screen** (`HeroNumber`, 56; 34 inside the gauge), its unit beside or under it in the second ink.
- **Titles lead** (start-aligned). Centre only the welcome and an empty state.

## Icons

**Iconsax** (the `iconsax_plus` package, MIT), the kit's own family. Screens name glyphs **by meaning** through `QIcons` and draw them through `QIcon`, never the family directly. The map is in `references/icons.md`.

- **Linear at rest; bold only for chosen or on** (the tab the person is on, a done mark).
- **Sizes:** 20 in rows, 22–24 in controls, 24 in the tab bar.
- **Colour:** the ink of the words beside them; `onPastel` on a pastel; `onAccent` on burgundy. Never a colour of its own.
- **Every icon-only control has a spoken label,** and a visible word wherever a glyph could be misread.
- **Mirror only what points along the reading:** back, forward, sign out.
- **No Material icons, no emoji as icons.** (The Apple and Facebook sign-in marks are the one exception, named in `QIcons`.)

## The tab bar and the orb (Qamar)

The orb is the product's signature. It lives in the middle of a floating tab bar:

- **The bar:** a `surfaceRaised` capsule, 66 tall, 12 above the safe area's foot, holding five 54-point circles 8 apart: **Today, Progress, [the orb], Plan, Me**. A tab's circle is `surfaceHigh` with its linear glyph; the page on show is `accent` with its bold glyph. The orb's circle is black, the living moon in it.
- **The orb's gestures**, none of them a swipe:
  - **tap** — the **Log sheet** rises under the bar;
  - **hold** (350 ms) — the conversation opens, already listening. The one gesture people have to learn;
  - **drag** — the moon leaves the bar under the finger; dropped on a number with the dotted mark, it explains it; let go, it springs back into its circle.
- **The Log sheet** is every way to log, one tap each, nothing a level down: the title and today's photo count; three pastel tiles (Speak, Type, Photo); Repeat (recent meals as chips); water (glass, bottle, tea); movement (five kinds, then how long); and "Ask Qamar anything", which says once, "or hold the moon to talk". It rises **under** the bar, so the moon that opened it stays in view and answers: a tap puts the sheet away, a hold talks, a tab goes to its page.
- **The moon** is monochrome; its phase is the day's progress, and it breathes where it is. Nothing orbits it, nothing drifts, no sparks: calm is the point. Its only company is the streak ring (seven short arcs in `accentInk`).
- **Pages under a tab** (the wallet, Qamar+, Ramadan) have one back control at the top start instead of the bar.
- A tab page pads its end by `QLayout.pageBottom`, so nothing the person needs rests under the bar.

## The mascot (Qamar)

Where the kit draws a fruit character, Qamar draws **the moon as a character** (`MoonMascot`): a white full moon with a black crescent of shadow down one side (the phase, the brand's mark), a face, a crater or two and a blush, in the kit's heavy black line. The whole character (arms, a wave, sneakers, sparkles, a ground shadow) is for the welcome and empty pages; the face alone for a card or a row. It **always stands on a pastel**: on the dark its line would be lost. It is a picture and says nothing to a screen reader.

## Motion

The tokens and Flutter recipes are in `references/motion.md`.

| Moment | Motion |
|---|---|
| Press (any control) | scale 0.97 **on touch-down**, 120 ms; a dim to 70% under Reduce Motion |
| State change (a segment, a tab, a toggle) | 180–220 ms, ease-out |
| Arrive (a sheet, a card, a message) | the settle spring (damping 1.0, response 0.35 s): a rise from below its own height, or a fade |
| Leave | along the path it came in |
| After a flick | damping 0.8: the only bounce allowed |
| Waiting, listening | a slow breath, never a spinner alone, with specific words |
| Reduce Motion | every move becomes a fade of 150 ms or less; every loop stops, the orb's breath included; the screen settles |

**Rules**
- **Motion explains** where something came from and went. Never decoration.
- **Frequent actions barely move.** Sending a message or adding a glass gets a press and a fade.
- **Interruptible always:** start from the on-screen value; never lock input during a transition.
- **Nothing a finger must hit drifts.** Buttons, chips, tiles and the tab bar hold still.

## Shape and space

- **Corners** (`QRadii`): `control` 12 (a button, a field, a notice), `inset` 16 (a tile or an item inside a card, a photo), `card` 24 (a card, a dialog, a chat bubble), `sheet` 32 (a sheet's top), `pill` (chips, the segmented control, the tab bar, a capsule), circles for round buttons. Nested corners are concentric (`QRadii.inside`). No corner is a number outside the theme.
- **Buttons are rounded rectangles** at `control`: the primary 50 tall, a secondary 44, a compact one in a card 36–40. Chips and segments are capsules.
- **4-point grid:** 4, 8, 12, 16, 20, 24, 32. The page margin is 20; cards on a page are 12–16 apart.
- **Touch targets are at least 48 × 48** (`QTapArea`), whatever is drawn.
- **Use space to group,** not boxes; no zebra stripes.

## Components

The full catalogue, with anatomy, states and Flutter names, is in `references/components.md`.

| Need | Use |
|---|---|
| The one thing to do | **Primary button** (`QPrimaryButton`): burgundy, white 16/600, 50 tall |
| A second choice | **Secondary button** (`QOutlineButton`): `surfaceRaised`, white 15/500, 44 tall |
| A compact action in a card | **Pill button** (`QPillButton`, burgundy, 40) or, on a pastel, **the black button** (`QPastelButton`) |
| A quiet action | **Text button**: `inkSecondary` 15/500, still a 48 target |
| A way on | **Burgundy words**: `accentInk` 15/600 |
| A choice among a few | **Chips** (`QPillChip`): chosen burgundy with white words; the rest `surfaceRaised` |
| A mode among two or three | **Segmented control** (`QSegmented`, `QLangToggle`): a white track, the chosen segment burgundy |
| An icon action | **Round button** (`QRoundIconButton`, `QBackButton`): a grey circle, 34–44, a 48 target |
| The figures that matter | **Pastel card** (`PastelCard`), the **calorie gauge** (`CalorieGauge`), the **macro tiles** (`MacroTile`) |
| A group of facts | **Card** (`QDecor.card()`): `surface`, 24, padding 20 |
| A list, settings | **Grouped rows** (`QListGroup` of `QListRow`): one card, rows 56 tall at least, no lines |
| A page's name | **Page title** (`QPageTitle`, 24/700), a group's (`QSectionTitle`, 20/700) |
| Nothing yet | **Empty state** (`QEmptyState`): the mascot on a pastel disc, a title, a line, one action |
| Error, offline, limit | **State card** (`QStateCard`) or **state line** (`QStateLine`): a glyph, a sentence, one way on |
| A value the orb explains | **Explain mark** (`ExplainMark`): a quiet dotted underline, and only there |
| Progress | **Bar** (`QBar`): `accentInk` on the dark, black on a pastel; or the moon |
| On/off | **Switch**: a burgundy track when on, the row's label beside it |
| A task that interrupts | **Sheet** (`QSheetSlot` + `QSheetScrim` + `QSheetPanel`) |

## States

Burgundy says "you can do this" or "you chose this". It never says how something went.

| State | Encoding |
|---|---|
| Selected | burgundy plus a shape: a filled chip or segment, the tab's burgundy circle with its bold glyph, or a washed row with a round mark |
| Pressed | 0.97 scale and a step lighter (`accentPressed` on burgundy) |
| Disabled | `inkDisabled` words on the control grey, no press, and a reason nearby. A disabled primary isn't burgundy |
| Focus | a white edge (a field), a 2-point white ring (a control) |
| Loading | a breathing dot and **specific words** ("Reading the photo…"), never "Loading…" |
| Success | the result appearing, or a check and one breath. No toast for what the person can see |
| Over the limit, a warning | a glyph plus words. Never red, never burgundy |
| Error | a glyph, a plain sentence (what happened, what to do) and one button. No blame, no "oops", no codes |

## The conversation

ChatGPT's structure, in the kit's colours; the full pattern is in `references/chat.md`.
- **The ground** is the dark. Qamar's words are plain text across the page (17/24), no bubble, no avatar.
- **The person's words** sit in a **lavender bubble** with black words, on their side, corner 24.
- **The composer** is one grey field: a **+** for a photo, the words, and one round button: the **microphone** (a grey circle) while the field is empty, the **burgundy send arrow** once there is something to send, **stop** while listening or replying.
- **Under a reply:** copy and retry. A suggested next step is a grey chip with `accentInk` words.
- **A meal read off what was said** comes back as the kit's scan result: the four macro tiles and the items with − / + steppers, confirmed with the primary ("Confirm and log"). Nothing is written until the person confirms; then Undo.
- **Waiting:** a breathing lavender dot and the status line's specific words.
- **Disclose once, quietly,** that answers come from AI and can be wrong.

## Simplicity: no extra steps, no tech talk

1. **Default, don't ask.** Infer or pick the common answer; let people change it where it lives. Ask only when a wrong guess would hurt (allergies, fasting, medical limits).
2. **Act, then offer undo.** Confirm only what is irreversible, costs money, or is done on the person's behalf.
3. **One screen, one job, one burgundy button.**
4. **Two taps** for every common task (log a meal, add water, ask a question, see today). Count them.
5. **Show the result, not the machinery.** No model names, tokens, confidence scores, "sync", "API", "server", codes or IDs.
6. **One sheet at a time.** Never a sheet from a sheet. Back always goes back.
7. **Teach in place, once.** A one-line hint at the moment it's useful; never a tutorial wall, never the same tip twice.
8. **Show something immediately.** Update optimistically; any wait over about 300 ms gets specific words.
9. **Cut before you add.** Visible clutter costs more than a missing edge case.
10. **Sign-in, payment and permissions come last,** when the value is already felt, with one sentence saying why.

**Words:** short, warm and concrete, the way a person would say it. Verbs on buttons ("Log it", "Add water"). Arabic is natural Egyptian Arabic, written, not translated. Sentence case; no full stop on a one-line label. The same thing has the same name everywhere (the Log sheet's "Repeat" is the night note's "under Log → Repeat").

## Arabic-first

Details, digits and edge cases are in `references/arabic.md`.
- **Directional APIs only** (`EdgeInsetsDirectional`, `AlignmentDirectional`, start/end).
- **Leading is the right in Arabic:** back points right, bars and the calorie gauge fill from the right, the tab bar reads Today first from the right. Rings, clocks and the moon's phase run the same in both languages.
- **Digits** follow the person's setting through one formatter (`state.iso`); never reversed; live values tabular.
- **Never tracked,** and every style has an explicit line height.

## Accessibility (never optional)

- **Contrast:** text 4.5:1 (3:1 for 18 pt+ or bold 14 pt+) on every ground it sits on, pastels included; marks 3:1. The table is in `references/tokens.md`.
- **Labels:** every control has a spoken label in the current language; tabs say which is chosen; custom paint is labelled or excluded.
- **Text size:** layouts survive 200% text; restack instead of truncating; a tall sheet scrolls.
- **Reduce Motion:** fades, every loop stopped, the screen settles.
- **Announcements:** a chat reply once, when it finishes; milestones, not every change.

## Before you call it done

Run the checklist in `references/review.md`. In Qamar, `flutter analyze` and `flutter test` must be clean. The design tests (tokens, icons, radii, type scale, contrast, targets) are part of the suite and encode these rules; when a redesign changes what one pins, update it to the new intent, and never loosen a guard to get green.

## Reference files

| File | Read it when |
|---|---|
| `references/tokens.md` | you need an exact value: colours, contrast, type, space, radii, the tab bar, motion |
| `references/components.md` | building any control, card, row, sheet, state or form |
| `references/chat.md` | touching any conversational surface |
| `references/motion.md` | animating anything: the orb, sheets, reduce motion |
| `references/icons.md` | choosing a glyph; the meaning → glyph map; RTL mirroring |
| `references/arabic.md` | RTL layout, Arabic type, digits, Egyptian copy |
| `references/flutter.md` | writing Flutter in Qamar: the kit's classes, the tests that enforce it, the render harness |
| `references/review.md` | reviewing a screen, a diff or a screenshot |
| `references/sources.md` | you need the reasoning behind a rule: the kit, Apple's HIG and the owner's direction |
