---
name: liquid-glass
description: The house design language for our products. Black, white and one burgundy accent; Liquid Glass as the material; one icon family; spring motion; large clean numerals; Arabic-first. Use this skill whenever you design, build, restyle, review, simplify or screenshot any screen, component, card, chat, onboarding step, sheet, icon, animation or colour in one of our apps (Qamar first, Flutter by default). Use it even when the request only says "make it look better", "fix the UI", "add a button", "new screen", "redesign", "make it simpler", "polish", or names a colour (burgundy included), a font, an icon or glass. Also use it to review a UI diff or screenshot for consistency, simplicity, RTL or accessibility.
---

# Liquid-glass

**Black canvas, white ink, one burgundy. Cards and controls are glass. One thing to do per screen.**

Liquid-glass is our design language. Liquid Glass (capitals, no hyphen) is Apple's material, and ours is built on it. It combines two sources:
- **Apple's Human Interface Guidelines**: Liquid Glass, springs, Dynamic Type sizes, 44 pt targets, one tint for what's interactive.
- **Our own rule**: the fastest, simplest path always wins.

It applies to every product we ship. Qamar (Flutter, Arabic-first) is the reference implementation, and its kit is described in `references/flutter.md`.

People should feel calm, fast and in control. If a screen feels busy, clever or technical, it is wrong, however good it looks.

## The six laws

1. **Black, white and one burgundy.**
   - The palette is black, white, the achromatic greys between them, and one accent: burgundy.
   - Burgundy marks what you can act on and what is chosen, never status. A reading over target is not red, and there are no success, warning or error colours. Glyphs and words carry state.
   - One burgundy action per screen: the primary button, or in the conversation the send circle once there is something to send. Chosen chips are burgundy too, as many as are chosen, because they mark what is chosen rather than what to do.
   - Burgundy is never body text. Hierarchy comes from grey level, size, weight and space.
   - Two exceptions keep their own colours: photographs (the camera, a person's meal), and third-party marks whose rules require their colours, such as Google's "G".
2. **Liquid Glass is the material.**
   - Cards, grouped lists and sheets are glass panels over the page's burgundy light. Floating controls are glass that blurs what's behind it.
   - The primary action is burgundy-tinted glass. Secondary buttons and unchosen chips are clear glass.
   - Glass on glass only as a nested inset, and never blur on top of blur.
   - The conversation stays plain: words on black.
3. **One of everything.**
   - One icon family.
   - Two type families (Inter for Latin, Noto Sans Arabic for Arabic), stacked into one style.
   - One primary (burgundy) button per screen.
   - One hero per screen: the large numeral or the moon.
4. **Motion is physics.**
   - Critically damped springs, with no bounce unless a finger threw it.
   - Feedback starts on touch-down.
   - Everything can be interrupted.
   - Reduce Motion turns movement into a short fade and stops every loop.
5. **The fastest path wins.**
   - Default instead of asking, act instead of confirming, offer undo instead of warning.
   - No jargon.
   - Every common task is at most two taps from where the person already is.
6. **Arabic is not a translation.**
   - Every screen is designed right-to-left first and checked left-to-right.
   - Arabic is never tracked or uppercased.
   - Arabic-Indic digits are a setting, never an accident.

When a rule here conflicts with a request, follow the request but say which rule it breaks and why. When two rules conflict, the earlier law wins.

## How to work

1. **Name the screen's job in one sentence.** If you can't, the screen does too much; split it or cut it.
2. **Pick its one primary action** (the burgundy button) **and its one hero** (the large numeral, or the moon). Everything else is quiet.
3. **Build only from the kit.** Use tokens for colour, type, space and radius, and components for buttons, chips, rows, glass and states. A raw `Color(0x…)`, a raw font size, a Material `Icons.` glyph or a hand-rolled button is a bug. Tests enforce this in Qamar (see `references/flutter.md`).
4. **Count the taps** for the screen's main task, from app open. Remove every step that isn't a real decision.
5. **Check the copy.** Replace every word of jargon with what it means for the person, in both languages (see "Words" below).
6. **Render it** in English and Arabic at phone width. Look at the images, and check them against `references/review.md` before calling it done.

## Colour

Dark is the default and, in Qamar, the only mode. A light ramp for products that need one is in `references/tokens.md`.

| Token | Value | Use |
|---|---|---|
| `black` / `white` | `#000000` / `#FFFFFF` | the two ends, which the tokens below are named from |
| `canvas` | `#000000` | the page |
| `ambient` | `#2A0912` | the page's light: a radial burgundy glow from above the top of the screen, fading to black by about the middle. Fixed behind the pages; cards scroll over it. Keeps `inkTertiary` ≥ 4.5:1 on the brightest glass panel where content sits |
| `surface` / `surfaceRaised` / `surfaceHigh` | `#121212` / `#1E1E1E` / `#2C2C2C` | solid fallbacks, fields, the person's chat bubble, tracks |
| `ink` / `inkSecondary` / `inkTertiary` / `inkDisabled` | `#FFFFFF` / `#C7C7C7` / `#999999` / `#666666` | primary text and icons / secondary text and quiet actions / labels and meta, the floor for readable text / disabled or decorative only |
| `onInk` | `#000000` | words on a white fill: the camera shutter only |
| `accent` | `#8E1B34` | burgundy fill: the primary button, the send button, a chosen chip, a switch that is on. White on it is 8.9:1 |
| `accentPressed` | `#751529` | the fill while pressed |
| `accentInk` | `#E8768D` | burgundy as a foreground on dark: progress bars, the streak ring, a chosen radio mark, and the words of a way on (a notice's action, a turn's next step). At least 4.8:1 on a glass panel and on `surfaceRaised`, 4.5:1 on a raised pane or an inset. Never body text |
| `accentWash` | `accent` at 28% | a chosen row's or tinted glass's wash |
| `onAccent` | `#FFFFFF` | words and glyphs on burgundy |
| `hairline` / `hairlineStrong` | white 14% / 28% | edges |
| `glassPanel` → `glassPanelTop` | white 7% → white 10% at the top | a glass panel's fill: cards and sheets |
| `glassRaised` | white 14%, flat | a pressed pane, or a pane standing inside another |
| `glassInset` | white 5% | a block inside a pane, such as the gesture guide's cells |
| `glassRim` | white 28% at the top, fading to `hairline` 14% by the middle | a panel's specular edge |
| `glassSheet` | `#121212` at 78% | a sheet's frosted ground, over a sigma-24 blur |
| `glassFill` / `glassFillPressed` / `glassFillClear` | white 12% / 18% / 6% | floating glass controls |
| `glassLens` | white 8% | a floating control's lens |
| `glassEdgeTop` → `glassEdgeBottom` | white 40% → 8% | a floating control's specular edge |
| `glassRimTinted` | white 55% | the rim of burgundy glass |
| `glassSolid` | `surfaceRaised` | the Increase Contrast fallback |
| `scrim` | black 64% | behind a modal |

The Google "G" is the one third-party hue, and it appears on the account sheet only.

**Rules**
- **Burgundy is the signal.** Most of a screen is black, grey and glass, so the one warm thing is the thing to do. Spend it there, and on what the person has chosen.
- **Two burgundies, two jobs.** `accent` is a fill with white words on it. On black it is too dark to read as a line or a word (2.4:1), so burgundy as a foreground is the lighter `accentInk`.
- **Burgundy words, grey words.** `accentInk` colours the words of a way on: a notice's action, a turn's next step. Quiet actions (Later, Not now, Cancel, Undo) stay `inkSecondary`. Legal links (Terms, Privacy) stay `inkTertiary` with an underline, because they are not actions in the flow.
- **Grey is hierarchy.** Use at most four text levels per screen: `ink`, `inkSecondary`, `inkTertiary`, and `inkDisabled` only when something is disabled.
- **No shadows.** On black a shadow has nothing to darken. A panel's lens and rim are the lift.
- **Meaning is never carried by colour or grey level alone.** Every state also has a shape, an icon or words (see "States").

## Liquid Glass

Glass is the material, not a decoration. The full recipe, the Flutter code, and the Increase Contrast and performance rules are in `references/glass.md`.

- **Panels:** cards, grouped lists and sheets.
  - A translucent white fill that is brighter at the top (the lens), a specular rim that is bright at the top and fades down the sides, and no shadow. They sit over the page's burgundy light, so the glass has something to show and reads as glass.
  - A pressed pane, or a pane standing inside another, is raised: a flat `glassRaised` fill.
  - **Cards don't blur.** They are content that scrolls, and blur there costs frames.
  - **Sheets blur what's behind them** (sigma 24) under a frosted ground (`glassSheet`), so their words never depend on the page. Anything else floating over scrolling content blurs at sigma 20.
- **Floating controls are glass with blur** (sigma 20): the orb, the composer, round header buttons, the tree's circles, the Su chip and the orb's receipt.
- **The primary action is burgundy-tinted glass:** a burgundy capsule with the same lens (`glassFill`, white 12%) and a brighter rim (`glassRimTinted`), white words, 52 tall. The send circle is the same glass, once there is text to send.
- **Secondary buttons and unchosen chips are clear glass capsules.** A chosen chip is filled burgundy. A segmented control's chosen segment (the language toggle, the wallet tabs) is a neutral raised glass pill, not burgundy, because a mode is not an action.
- **Glass on glass only as a nested inset:** `glassInset` inside a panel. Never put a blurring layer on top of another blurring layer.
- **Keep to about four blurring surfaces on screen at once**, for legibility and frame rate. Cards don't count; they don't blur.
- **Increase Contrast turns floating glass and sheets solid:** `glassSolid` (`surfaceRaised`) with a strong edge and no blur. Cards keep their pane: they already sit over black, and they have the rim.
- **Over a photo or the camera**, floating controls take the thin fill (`glassFillClear`) with a 35% black dim behind them.
- **Scroll edges fade; they don't draw lines.** Where content scrolls under floating controls, fade it out over about 24 pt; don't use a divider or a solid bar. At the top of a page nothing sits under floating glass: overlap happens only while scrolling.
- **The conversation stays ChatGPT-like.** Qamar's words are plain text on black, and the person's words sit in a `surfaceHigh` bubble. The composer is glass, and its send circle turns burgundy once there is text.

## Type

Latin is set in **Inter**, the open face closest to SF. Arabic and Arabic-Indic digits are set in **Noto Sans Arabic**, the fallback on every style. Both are bundled, so nothing waits on a download.

| Role | Size / line height | Weight |
|---|---|---|
| Large title (a page's name) | 34/41 | 700 |
| Title 1 / hero line | 28/34 | 600–700 |
| Title 2 (a sheet's name) | 22/28 | 700 |
| Title 3 (a card's lead line) | 20/25 | 600 |
| Body, headline, buttons | 17/22 (chat reading 17/24–26) | 400 / 600 |
| Callout | 16/21 | 400–500 |
| Subheadline (rows, secondary) | 15/20 | 400–500 |
| Footnote | 13/18 | 400 |
| Caption / eyebrow | 12/16 | 400 / 600 |
| Caption 2 (the floor) | 11/13 | 400–500 |
| Figures | 20, 28, 34, 48, 56, always tabular | 500 (the hero, 56, is 700) |

**Rules**
- **No other sizes.** Nothing is smaller than 11.
- **Weights 400, 500, 600 and 700 only.** Never thin or light.
- **Tracking comes from the size, never from the call site.** It is zero below 20, slightly negative above, and **never on Arabic**.
- **Eyebrows (small labels above a group or figure):**
  - 12/16, weight 600, `inkTertiary`;
  - in English, UPPERCASE with 0.6 pt tracking;
  - in Arabic, as written: no case, no tracking.
- **The hero is one large numeral per screen** (`HeroNumber`), set in the UI face: Inter, with Arabic-Indic digits from Noto Sans Arabic.
  - 56 pt (`HeroNumber.heroSize`), bold, tabular figures, tight leading, in `ink`.
  - Its unit sits beside or under it in `inkSecondary`, as text, so it can be read and translated.
  - Every other number is tabular Inter at a figure or text size.
- **Headlines are bold, short and leading-aligned.** Centre only the empty state and the welcome.

## Icons

Use **one family: Cupertino Icons** (MIT, ships with Flutter, drawn after SF Symbols). SF Symbols itself is licensed for Apple platforms only, so we can't ship it on Android. Screens name glyphs **by meaning** through the kit (`QIcons.send`, never `CupertinoIcons.arrow_up` at a call site), so the family can change in one place. The full map is in `references/icons.md`.

- **Outline by default.** Use the filled form only for a selected or "on" state.
- **Sizes:** 20 in rows, 24 in controls, 28 for a hero glyph.
- **Colour:** icons take the ink of the text beside them, and `onAccent` on burgundy.
- **Every icon-only control has a spoken label**, and a visible label wherever the meaning isn't obvious. A pencil can mean edit or write; a word is always better than a guess.
- **Mirror only directional glyphs in Arabic:** back, forward, send-as-arrow, reply. Clocks, checkmarks, circular arrows, media controls and real objects don't mirror.
- **No Material icons, no emoji as icons, and no icon with a colour of its own.**

## Motion

The tokens and Flutter recipes are in `references/motion.md`.

| Moment | Motion |
|---|---|
| Press (any control) | scale 0.97 and a brighter fill **on touch-down**, 100–120 ms |
| State change (toggle, segment, selection) | 200–250 ms, ease-out |
| Arrive (sheet, card, message, overlay) | spring, damping 1.0, response 0.35 s: fade plus a short rise or grow from its source |
| Leave | faster than arrive (≈ 200 ms), along the same path it came in |
| After a flick | spring damping 0.8: the only bounce allowed |
| Waiting, listening, "thinking" | a slow breath: 2.4–3 s, 100% → 50% brightness, never a spinner alone |
| Reduce Motion | every move becomes a ≤ 150 ms fade. Every loop stops, including the orb's breathing and the moon's phase drift, and the screen settles |

**Rules**
- **Motion explains.** It shows where something came from and where it went. Never add it for decoration.
- **Frequent actions barely move.** Sending a message or ticking a glass of water gets a press and a fade, not a show.
- **Everything is interruptible.** Start from the current on-screen value, and never block input during a transition.
- **Nothing a finger must hit drifts.** Buttons, chips and the tree's circles hold still.
- **Don't flash** more than three times a second.

## Shape and space

- **Corners:** **pill** for anything pressed (buttons, chips, the composer, toggles), **circle** for icon buttons, **12** inset, **18** control or field, **24** card or chat bubble, **32** sheet top.
- **Nested corners are concentric:** the inner radius is the outer radius minus the gap between them.
- **4-pt grid:** 4 / 8 / 12 / 16 / 20 / 24 / 32. The page margin is 20.
- **Use space to group, not boxes.** Draw hairlines only in dense lists, and no zebra stripes.
- **Touch targets are at least 48×48 pt** (Android's 48 dp covers Apple's 44). Leave 8 pt or more between adjacent targets.
- **The hero gets air:** 32–48 pt around it.

## Components

The full catalogue, with anatomy, states and Flutter names, is in `references/components.md`.

| Need | Use |
|---|---|
| The one thing to do | **Primary button**: burgundy glass capsule, white 17/600 label, 52 tall (48 in a dense card) |
| A second choice | **Secondary button** (`QOutlineButton`): clear glass capsule, `ink` 15/500 label, 44 tall |
| A quiet action | **Text button**: `inkSecondary`, 15/500 (Later, Not now, Cancel, Undo), still with a 48 pt target |
| A way on | **Burgundy words**: `accentInk` 15/600, no fill: a notice's action, a turn's next step |
| A choice among a few | **Chips**: chosen is filled burgundy with white words, as many as are chosen; unchosen is clear glass |
| A mode among two or three | **Segmented control**: glass track; the chosen segment is a neutral raised glass pill |
| Icon action | **Glass circle**: 44 floating, as small as 32 on content, always a 48 target |
| A group of facts | **Card**: a glass panel, radius 24, padding 20 |
| A list | **Grouped rows** in one panel: 56 tall, label leading, value trailing (tabular), hairline between. A chosen row takes `accentWash` |
| A value the orb can explain | **Explain mark**: a quiet dotted underline, the classic "has a definition" mark |
| Progress | **Bar** (`accentInk`, 4 tall, fills from the leading edge), or the **moon** |
| On/off | **Switch** (on = burgundy track, white thumb) with its label on the row |
| Nothing here yet, error, offline, limit | **State card**: glyph, one sentence, one button |
| A task that interrupts | **Sheet**: frosted glass (`glassSheet` over a sigma-24 blur), top radius 32, grabber, one primary; swipe down to dismiss |

## States

Burgundy says "you can do this" or "you chose this". It never says how something went.

| State | Encoding |
|---|---|
| Selected | burgundy plus a shape: a filled chip, or a washed row (`accentWash`) with its mark in `accentInk`. A chosen segment is a raised glass pill |
| Pressed | 0.97 scale plus a brighter fill (`glassFillPressed`, `accentPressed` on burgundy, `glassRaised` for a pane) |
| Disabled | `inkDisabled` label, `hairline` edge, no press response, and a reason nearby if it isn't obvious. A disabled primary isn't burgundy: there's nothing to act on |
| Focus | a 2 pt white ring |
| Loading | a breathing dot plus **specific words**, e.g. "Reading the photo…", never "Loading…" |
| Success | a check plus one breath, or simply the result appearing. No toast for something the person can see |
| Warning or over the limit | an outline or the warning glyph, **plus words**. Never red, never burgundy |
| Error | an icon plus a plain sentence (what happened and what to do) plus one button to fix it. No blame, no "oops", no "we" |

## The ChatGPT-style chat

The full pattern is in `references/chat.md`. In short:
- **The page** is black, and Qamar's words sit on it as plain text. There is no glass behind the transcript.
- **The header** has a glass close button on the leading side and a centred name, with one status line under it.
- **The empty state** is one large question ("What can I help with?") above three or four clear glass suggestion chips.
- **Messages:** the person's is a `surfaceHigh` bubble on the trailing side (radius 24, the card corner). Qamar's reply is plain full-width text at 17/26, with no bubble, no avatar and no name.
- **The composer** is one glass capsule: a **+** on the leading side (camera or photo), a text field that grows to 6 lines, and one circle on the trailing side.
- **Burgundy in the conversation**, and nothing else:
  - The send circle (↑) is burgundy only when there is text. The **mic** beside an empty field, and **stop**, are clear glass. The onboarding composer's send works the same way.
  - A turn's suggested next step is a clear glass chip with `accentInk` words (600), not a burgundy fill.
  - "Confirm and log" on a reading is the primary button.
- **While waiting**, show a breathing dot and specific status words.
- **Under a reply**, offer copy and retry.
- **Anything done on the person's behalf** (logging a meal, changing a goal) appears as a proposal card, confirmed with its primary button. Never act silently.
- **Disclose once, quietly,** that answers come from AI and can be wrong.

## The orb (Qamar)

The orb is the product's signature and navigation, not a page's hero, so a page may have its own hero as well.
- **It stays:** a monochrome moon on glass, whose phase is the day's progress, with a soft white halo.
- **The streak ring** is seven short arc segments around it, clockwise from the top. Lit days are `accentInk`, today is at half strength while it is still waiting, and unlit days are `hairline`. The ring thickens a little from 3 days and again from a full week, so a longer run shows without a new colour.
- **Gestures:** tap for the tree, hold to talk.
- **The tree** (the moon's radial menu) is glass circles around the moon, each labelled with the title of the screen it opens. There are no connecting lines. A soft burgundy glow (`accent` at about 35%, radial) sits behind the centre moon. Nothing on the ring moves on its own.
- **The moon itself is never recoloured.** Its only burgundy company is the streak ring and, in the tree, the glow behind it. Never let content rest under the orb's band: pages pad by the band height.

## Simplicity: no extra steps, no tech talk

The person came to do one thing. Every screen, sheet and word either helps them do it faster or goes.

1. **Default, don't ask.** Infer from context or pick the common answer, and let people change it later where it lives. Ask a question only when a wrong guess would hurt, such as allergies, fasting or medical limits.
2. **Act, then offer undo.** Confirm only what is irreversible, costs money, or is done on the person's behalf. Everything else just happens, with Undo nearby.
3. **One screen, one job, one burgundy button.** Other actions are quieter: clear glass, text or icon.
4. **Two taps.** Every common task (log a meal, add water, ask a question, see today) is at most two taps from where the person is. Count them.
5. **Show the result, not the machinery.** Never show model names, tokens, confidence scores, "sync", "API", "server", error codes, IDs or percentages of certainty. Turn a technical state into what it means ("Couldn't reach Qamar. Try again.").
6. **One sheet at a time.** Don't nest modals or open a sheet from a sheet. Back always goes back.
7. **Teach in place, once.** Show a one-line hint at the moment it's useful. Never show a tutorial wall, and never show the same tip twice.
8. **Show something immediately.** Update optimistically. Any wait over about 300 ms gets specific words, and a long wait can be cancelled.
9. **Cut before you add.** A feature that can't justify its tap is removed. Visible clutter costs more than a missing edge case.
10. **Sign-in, payment and permissions come last.** Ask for them only when the value is already felt, in context, with one sentence saying why.

**Words**
- Say it the way a person would: short, warm and concrete. Put verbs on buttons ("Log it", "Add water").
- Arabic copy is natural Egyptian Arabic, not a translation of the English.
- Use sentence case, and don't end single-line labels with punctuation.
- The same thing has the same name everywhere.

## Arabic-first

Details, digits and edge cases are in `references/arabic.md`.

- **Build with directional APIs** (`EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`). Never hard-code left or right.
- **Leading is the right side in Arabic.** Back arrows, progress bars, sliders and swipe directions all follow reading direction. **Rings and clocks run clockwise in both languages.**
- **Digits:** show Arabic-Indic (٠١٢٣) or Western (0123) according to the person's setting, through one formatter. Never reverse a number's digits, and keep live values tabular.
- **Arabic is never tracked or uppercased, and always has an explicit line height.**
- **Mixed-direction text** (a dish name in the other script) needs no special handling: the fallback stack draws each script in its own face. Check it anyway in renders.

## Accessibility (never optional)

- **Contrast:** text meets 4.5:1 (3:1 for 18 pt+ or bold 14 pt+), on glass as well as on solid surfaces. `inkTertiary` is the floor for readable text.
- **Labels:** every control has a spoken label in the current language, and custom controls expose their role (button, toggle, selected).
- **Text size:** layouts survive 200% text. Restack instead of truncating.
- **Accessibility settings:**
  - Reduce Motion gives fades and stops every loop.
  - Increase Contrast makes floating glass and sheets solid, with stronger edges. Cards keep their pane.
  - Bold Text works.
- **Announcements:** announce milestones and completions, not every change. A chat reply is announced once, when it finishes.

## Before you call it done

Run the checklist in `references/review.md`: colour, glass, type, icons, motion, simplicity, RTL, accessibility and renders. In Qamar, `flutter analyze` and `flutter test` must be clean. The design tests (tokens, icons, radii, type scale, contrast) are part of the suite and encode these rules; don't loosen a test to get green.

## Reference files

| File | Read it when |
|---|---|
| `references/tokens.md` | you need an exact value: colours (dark, and light for other products), contrast on glass, type, space, radii, motion |
| `references/glass.md` | building or reviewing any glass: panels, floating controls, burgundy glass, the page's light, accessibility fallbacks, performance |
| `references/components.md` | building any control, card, row, sheet, state or form |
| `references/chat.md` | touching any conversational surface |
| `references/motion.md` | animating anything, including the orb, sheets and reduce motion |
| `references/icons.md` | choosing a glyph; the meaning → glyph map; RTL mirroring |
| `references/arabic.md` | RTL layout, Arabic type, digits, Egyptian copy |
| `references/flutter.md` | writing Flutter in Qamar: the kit's classes, the tests that enforce it, the render harness |
| `references/review.md` | reviewing a screen, a diff or a screenshot |
| `references/sources.md` | you need the reasoning or evidence behind a rule (Apple's HIG and our own rule) |
