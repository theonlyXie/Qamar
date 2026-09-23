---
name: mono-glass
description: The house design language for our products. Black and white only, Liquid Glass for the floating controls, one icon family, spring motion, dot-matrix hero numbers, Arabic-first. Use this skill whenever you design, build, restyle, review, simplify or screenshot any screen, component, chat, onboarding step, sheet, icon, animation or colour in one of our apps (Qamar first, Flutter by default). Use it even when the request only says "make it look better", "fix the UI", "add a button", "new screen", "redesign", "make it simpler", "polish", or names a colour, a font or an icon. Also use it to review a UI diff or screenshot for consistency, simplicity, RTL or accessibility.
---

# Mono-glass

**Black canvas. White ink. Glass only where your finger goes. One thing to do per screen.**

Mono-glass combines three sources:
- **Apple's Human Interface Guidelines**: Liquid Glass, springs, Dynamic Type sizes, 44 pt targets.
- **Nothing's design language**: monochrome, grey as the hierarchy, dot-matrix numerals, light as status.
- **Our own rule**: the fastest, simplest path always wins.

It applies to every product we ship. Qamar (Flutter, Arabic-first) is the reference implementation, and its kit is described in `references/flutter.md`.

People should feel calm, fast and in control. If a screen feels busy, clever or technical, it is wrong, however good it looks.

## The six laws

1. **Two colours.**
   - Black and white, plus achromatic greys between them. No hue anywhere: no status colours, no gradients of colour, no brand accent.
   - Hierarchy comes from grey level, size, weight and space.
   - Three exceptions keep their own colours:
     - photographs, including the camera and a person's meal;
     - third-party marks whose rules require their colours, such as Google's "G";
     - nothing else.
2. **Two layers.**
   - Content (text, cards, rows, messages, numbers) sits flat on solid black surfaces.
   - Controls that float above content use Liquid Glass: the orb, the composer, floating back/close buttons, the tree's buttons, top chips.
   - Never put glass on content, and never put glass on glass.
3. **One of everything.**
   - One icon family.
   - Two type families (Inter for Latin, Noto Sans Arabic for Arabic), stacked into one style.
   - One primary (white) button per screen.
   - One expressive "hero" moment per screen.
4. **Motion is physics.**
   - Critically damped springs, with no bounce unless a finger threw it.
   - Feedback starts on touch-down.
   - Everything can be interrupted.
   - Reduce Motion turns movement into a short fade.
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
2. **Pick its one primary action** (the white button) **and its one hero** (a dot numeral, the moon, or one big number). Everything else is quiet.
3. **Build only from the kit.** Use tokens for colour, type, space and radius, and components for buttons, chips, rows, glass and states. A raw `Color(0x…)`, a raw font size, a Material `Icons.` glyph or a hand-rolled button is a bug. Tests enforce this in Qamar (see `references/flutter.md`).
4. **Count the taps** for the screen's main task, from app open. Remove every step that isn't a real decision.
5. **Check the copy.** Replace every word of jargon with what it means for the person, in both languages (see "Words" below).
6. **Render it** in English and Arabic at phone width. Look at the images, and check them against `references/review.md` before calling it done.

## Colour

Dark is the default and, in Qamar, the only mode. A light ramp for products that need one is in `references/tokens.md`.

| Token | Value | Use |
|---|---|---|
| `canvas` | `#000000` | the page |
| `surface` | `#121212` | a card |
| `surfaceRaised` | `#1E1E1E` | a raised or pressed card, a field, the solid-glass fallback |
| `surfaceHigh` | `#2C2C2C` | the user's chat bubble, tracks, a selected band |
| `ink` | `#FFFFFF` | primary text, icons, the primary button's fill |
| `inkSecondary` | `#C7C7C7` | secondary text (12.4:1 on black) |
| `inkTertiary` | `#999999` | labels and meta; ≥ 4.9:1 on every surface |
| `inkDisabled` | `#666666` | disabled or decorative only, never text that must be read |
| `onInk` | `#000000` | words on a white fill |
| `hairline` / `hairlineStrong` | white 14% / 28% | dividers and card edges / outline buttons and emphasis edges |
| `glassFill` / `glassFillPressed` / `glassFillClear` | white 12% / 18% / 6% | Liquid Glass (clear only over photos) |
| `glassEdgeTop` → `glassEdgeBottom` | white 40% → 8% | glass's specular edge |
| `scrim` | black 64% | behind a modal |

**Rules**
- About 75% of a screen is black, 20% grey and at most 5% white. White is the signal, so spend it on the one thing that matters.
- Grey is hierarchy. Use at most four text levels per screen: `ink`, `inkSecondary`, `inkTertiary`, and `inkDisabled` only when something is disabled.
- There are no shadows on content, because on black a shadow has nothing to darken. A lighter surface is the lift.
- Meaning is never carried by grey level alone. Every state also has a shape, an icon or words (see "States without colour").

## Layers and Liquid Glass

Glass is a material for things that **float and act**. It is never a decoration. The full recipe, the Flutter code, and the reduce-transparency and high-contrast behaviour are in `references/glass.md`.

- **Glass (the control layer):**
  - the orb and its halo band;
  - the chat composer;
  - floating back/close circles;
  - the tree's ring buttons;
  - a floating chip over content (Su, receipt);
  - the language toggle's track;
  - a sheet's grabber area.
- **Never glass:** cards, list rows, messages, charts, numbers, dot displays, or a full page background.
- **Regular glass everywhere.** Use **clear** glass only over a photo or the camera, and only with a 35% black dim behind it.
- **Never glass on glass.** Things on glass use fills and ink, not more glass.
- **Keep it to about four glass surfaces on screen at once**, for legibility and frame rate.
- **High contrast turns glass solid.** When the phone asks for more contrast, glass becomes `glassSolid` with a strong edge and no blur. It keeps the same shape and nothing shows through.
- **Scroll edges fade; they don't draw lines.** Where content scrolls under floating controls, fade it out over about 24 pt. Don't use a divider or a solid bar.
- **Resting states don't overlap.** At the top of a page, nothing sits under glass; overlap happens only while scrolling.

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
| Figures | 20, 28, 34, 48, always tabular | 500 |

**Rules**
- **No other sizes.** Nothing is smaller than 11.
- **Weights 400, 500, 600 and 700 only.** Never thin or light.
- **Tracking comes from the size, never from the call site.** It is zero below 20, slightly negative above, and **never on Arabic**.
- **Eyebrows (small labels above a group or figure):**
  - 12/16, weight 600, `inkTertiary`;
  - in English, UPPERCASE with 0.6 pt tracking;
  - in Arabic, as written: no case, no tracking.
- **Hero numbers may be drawn in dots** (`DotNumber`, a 5×7 round-dot matrix with Western and Arabic-Indic digits).
  - One per screen, at least 40 pt tall.
  - Never for words, sentences, buttons or anything Arabic besides digits.
  - Smaller numbers use tabular Inter.
- **Headlines are bold, short and leading-aligned.** Centre only the empty state and the welcome.

## Icons

Use **one family: Cupertino Icons** (MIT, ships with Flutter, drawn after SF Symbols). SF Symbols itself is licensed for Apple platforms only, so we can't ship it on Android. Screens name glyphs **by meaning** through the kit (`QIcons.send`, never `CupertinoIcons.arrow_up` at a call site), so the family can change in one place. The full map is in `references/icons.md`.

- **Outline by default.** Use the filled form only for a selected or "on" state.
- **Sizes:** 20 in rows, 24 in controls, 28 for a hero glyph.
- **Colour:** icons take the ink of the text beside them.
- **Every icon-only control has a spoken label**, and a visible label wherever the meaning isn't obvious. A pencil can mean edit or write; a word is always better than a guess.
- **Mirror only directional glyphs in Arabic:** back, forward, send-as-arrow, reply. Clocks, checkmarks, circular arrows, media controls and real objects don't mirror.
- **No Material icons, emoji as icons, or coloured icons.**

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
| Dot sweeps | 12–20 ms per dot, in reading direction (rings: clockwise in both languages) |
| Reduce Motion | every move becomes a ≤ 150 ms fade; no breathing, orbiting, parallax or scaling |

**Rules**
- **Motion explains.** It shows where something came from and where it went. Never add it for decoration.
- **Frequent actions barely move.** Sending a message or ticking a glass of water gets a press and a fade, not a show.
- **Everything is interruptible.** Start from the current on-screen value, and never block input during a transition.
- **Don't flash** more than three times a second.

## Shape and space

- **Corners:**
  - **pill** for anything pressed: buttons, chips, the composer, toggles;
  - **circle** for icon buttons;
  - **12** inset;
  - **18** control or field;
  - **24** card or chat bubble;
  - **32** sheet top.
- **Nested corners are concentric:** the inner radius is the outer radius minus the gap between them.
- **4-pt grid:** 4 / 8 / 12 / 16 / 20 / 24 / 32. The page margin is 20.
- **Use space to group, not boxes.** Draw hairlines only in dense lists, and no zebra stripes.
- **Touch targets are at least 48×48 pt** (Android's 48 dp covers Apple's 44). Leave 8 pt or more between adjacent targets.
- **The hero gets air:** 32–48 pt around it.

## Components

The full catalogue, with anatomy, states and Flutter names, is in `references/components.md`.

| Need | Use |
|---|---|
| The one thing to do | **Primary button**: white capsule, black 17/600 label, 52 tall (48 in a dense card) |
| A second choice | **Outline button**: capsule with a `hairlineStrong` edge and a white label, 44 tall; fills `surfaceRaised` when pressed |
| A quiet action | **Text button**: `inkSecondary`, 15/500, still with a 48 pt target |
| A choice among a few | **Chips**. Selected is inverted (white fill, black text); unselected has a hairline edge |
| Icon action on content | **Round icon button**: `surfaceRaised` disc |
| Icon action floating | **Glass circle**, 44 |
| A group of facts | **Card**: `surface` with a hairline edge, radius 24, padding 20 |
| A list | **Grouped rows** in one card: 56 tall, label leading, value trailing (tabular), hairline between |
| Progress | **Bar** (white on `surfaceHigh`, 4 tall, fills from the leading edge), **dot ring** (clockwise), or the **moon** |
| On/off | **Switch** (on = white track, black thumb) with its label on the row |
| Nothing here yet, error, offline, limit | **State card**: glyph, one sentence, one button |
| A task that interrupts | **Sheet**: `surface`, top radius 32, grabber, one primary; swipe down to dismiss |

## States without colour

| State | Encoding |
|---|---|
| Selected | Inverted (white fill, black content), or a dot beside or under it |
| Pressed | 0.97 scale plus a brighter fill |
| Disabled | `inkDisabled` label, `hairline` edge, no press response, and a reason nearby if it isn't obvious |
| Focus | a 2 pt white ring |
| Loading | a breathing dot plus **specific words**, e.g. "Reading the photo…", never "Loading…" |
| Success | a check plus one breath, or simply the result appearing. No toast for something the person can see |
| Warning or over the limit | a hollow dot, a dashed line or an outline, **plus words** |
| Error | an icon plus a plain sentence (what happened and what to do) plus one button to fix it. No blame, no "oops", no "we" |

## The ChatGPT-style chat

The full pattern is in `references/chat.md`. In short:
- **The page** is solid black, with no glass on messages.
- **The header** has a glass close button on the leading side and a centred name, with one status line under it.
- **The empty state** is one large question ("What can I help with?") above three or four suggestion chips.
- **Messages:**
  - The person's message is a `surfaceHigh` bubble on the trailing side (radius 24, the card corner).
  - The assistant's reply is plain full-width text at 17/26, with no bubble, no avatar and no name.
- **The composer** is one glass capsule:
  - a **+** on the leading side (camera or photo);
  - a text field that grows to 6 lines;
  - one white circle on the trailing side. It shows **send** (↑) when there's text, **mic** when the field is empty, and **stop** while listening or generating.
- **While waiting**, show a breathing dot and specific status words.
- **Under a reply**, offer copy and retry.
- **Anything done on the person's behalf** (logging a meal, changing a goal) appears as a proposal card with a single "Confirm" primary button. Never act silently.
- **Disclose once, quietly,** that answers come from AI and can be wrong.

## The orb (Qamar)

The orb is the product's signature and navigation, not a page's hero, so a page may have its own hero as well.
- **It stays:** a monochrome moon on glass, whose phase is the day's progress, with a soft white halo.
- **The streak** is seven dots around it; the day at risk shows at half brightness.
- **Gestures:** tap for the tree, hold to talk.
- Never recolour it or give it a coloured glow. Never let content rest under its band: pages pad by the band height.

## Simplicity: no extra steps, no tech talk

The person came to do one thing. Every screen, sheet and word either helps them do it faster or goes.

1. **Default, don't ask.** Infer from context or pick the common answer, and let people change it later where it lives. Ask a question only when a wrong guess would hurt, such as allergies, fasting or medical limits.
2. **Act, then offer undo.** Confirm only what is irreversible, costs money, or is done on the person's behalf. Everything else just happens, with Undo nearby.
3. **One screen, one job, one white button.** Other actions are quieter: outline, text or icon.
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

- **Contrast:** text meets 4.5:1 (3:1 for 18 pt+ or bold 14 pt+). `inkTertiary` is the floor for readable text.
- **Labels:** every control has a spoken label in the current language, and custom controls expose their role (button, toggle, selected).
- **Text size:** layouts survive 200% text. Restack instead of truncating.
- **Accessibility settings:**
  - Reduce Motion gives fades.
  - Increase Contrast gives solid glass and stronger edges.
  - Bold Text works.
- **Announcements:** announce milestones and completions, not every change. A chat reply is announced once, when it finishes.

## Before you call it done

Run the checklist in `references/review.md`: colour, layers, type, icons, motion, simplicity, RTL, accessibility and renders. In Qamar, `flutter analyze` and `flutter test` must be clean. The design tests (tokens, icons, radii, type scale, contrast) are part of the suite and encode these rules; don't loosen a test to get green.

## Reference files

| File | Read it when |
|---|---|
| `references/tokens.md` | you need an exact value: colours (dark, and light for other products), type, space, radii, motion |
| `references/glass.md` | building or reviewing anything floating: the recipe, Flutter code, clear vs regular, accessibility fallbacks, performance |
| `references/components.md` | building any control, card, row, sheet, state or form |
| `references/chat.md` | touching any conversational surface |
| `references/motion.md` | animating anything, including the orb, sheets, dots and reduce motion |
| `references/icons.md` | choosing a glyph; the meaning → glyph map; RTL mirroring |
| `references/arabic.md` | RTL layout, Arabic type, digits, Egyptian copy |
| `references/flutter.md` | writing Flutter in Qamar: the kit's classes, the tests that enforce it, the render harness |
| `references/review.md` | reviewing a screen, a diff or a screenshot |
| `references/sources.md` | you need the reasoning or evidence behind a rule (Apple HIG and Nothing) |
