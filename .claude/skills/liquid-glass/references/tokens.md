# Tokens

Every value liquid-glass uses. In Qamar these live in `app/lib/theme/` (`colors.dart`, `text_styles.dart`, `app_theme.dart`, `motion.dart`, `layout.dart`). Screens use the names, never the values.

## Contents
- Colour: dark (the default)
- The page's light
- Colour: light (for products that need it)
- Contrast table
- Type
- Space, radii, targets
- Motion

## Colour: dark (the default)

Every grey is achromatic (R = G = B). The one hue is burgundy. Alpha tokens are white (black for the scrim, the surface for a sheet) over whatever is behind.

| Token | Hex / alpha | Notes |
|---|---|---|
| `black` / `white` | `#000000` / `#FFFFFF` | the two ends; `canvas`, `onInk`, `ink` and `onAccent` are named from them |
| `canvas` | `#000000` | the page, OLED black |
| `ambient` | `#2A0912` | the page's light (see below) |
| `surface` | `#121212` | the first solid step: a solid fallback, and the colour of a sheet's frosted ground |
| `surfaceRaised` | `#1E1E1E` | a field; `glassSolid`; a state card's glyph circle |
| `surfaceHigh` | `#2C2C2C` | the person's chat bubble; a switch's track when off; a wheel's selection band; solid glass while pressed |
| `ink` | `#FFFFFF` | primary text and icons |
| `inkSecondary` | `#C7C7C7` | secondary text, a hero's unit, quiet actions (Later, Not now, Cancel, Undo) |
| `inkTertiary` | `#999999` | labels, eyebrows, meta, placeholders, legal links (underlined): the floor for readable text |
| `inkDisabled` | `#666666` | disabled labels and decorative marks only |
| `onInk` | `#000000` | words on a white fill: the camera shutter only |
| `accent` | `#8E1B34` | burgundy fill: the primary button, the send button, a chosen chip, a switch that is on. White on it is 8.9:1 |
| `accentPressed` | `#751529` | the fill while pressed: a step deeper |
| `accentInk` | `#E8768D` | burgundy as a foreground on dark: progress bars, the streak ring, a chosen radio mark, and the words of a way on (a notice's action, a turn's next step). At least 4.8:1 on a glass panel and on `surfaceRaised`, 4.5:1 on a raised pane or an inset. Never body text |
| `accentWash` | `accent` @ 28% (`0x478E1B34`) | a chosen row's wash, and tinted glass's |
| `onAccent` | `#FFFFFF` | words and glyphs on burgundy |
| `hairline` | `#FFFFFF` @ 14% (`0x24FFFFFF`) | card edge, divider, the lower part of a rim, a bar's track |
| `hairlineStrong` | `#FFFFFF` @ 28% (`0x47FFFFFF`) | emphasis edge, solid-glass edge, a sheet's grabber |
| `glassPanel` | `#FFFFFF` @ 7% (`0x12FFFFFF`) | a panel's fill, lower down |
| `glassPanelTop` | `#FFFFFF` @ 10% (`0x1AFFFFFF`) | a panel's fill at the top: the lens |
| `glassRaised` | `#FFFFFF` @ 14% (`0x24FFFFFF`), flat | a pressed pane, or a pane standing inside another |
| `glassInset` | `#FFFFFF` @ 5% (`0x0DFFFFFF`) | a block inside a pane, such as the gesture guide's cells |
| `glassRim` | `#FFFFFF` @ 28% at the top, fading to `hairline` (14%) by the middle | a panel's specular edge |
| `glassSheet` | `#121212` @ 78% (`0xC7121212`) | a sheet's frosted ground, over a sigma-24 blur |
| `glassFill` | `#FFFFFF` @ 12% (`0x1FFFFFFF`) | floating glass and clear glass controls; the lens on burgundy glass |
| `glassFillPressed` | `#FFFFFF` @ 18% (`0x2EFFFFFF`) | glass while pressed |
| `glassFillClear` | `#FFFFFF` @ 6% (`0x0FFFFFFF`) | the thin fill, for controls over a photo or the camera |
| `glassLens` | `#FFFFFF` @ 8% (`0x14FFFFFF`) | a floating control's lens: its top 55% a touch brighter |
| `glassEdgeTop` | `#FFFFFF` @ 40% (`0x66FFFFFF`) | a floating control's specular edge, top |
| `glassEdgeBottom` | `#FFFFFF` @ 8% (`0x14FFFFFF`) | the same edge, fading down the sides |
| `glassRimTinted` | `#FFFFFF` @ 55% (`0x8CFFFFFF`) | the rim of burgundy glass, catching more of the light |
| `glassSolid` | = `surfaceRaised` | the Increase Contrast fallback for floating glass and sheets |
| `scrim` | `#000000` @ 64% (`0xA3000000`) | behind a modal sheet |

**Not tokens, and allowed only here:**
- `QBrandMarks.google*`: the four colours of Google's "G" on the account sheet's sign-in button, which Google's brand rules require.
- Pixels of a photograph.

## The page's light

- **What it is:** a radial glow of `ambient` from above the top of the screen, fading to `canvas` by about the middle. In Qamar, `QDecor.ambient` paints it once, in the shell, behind every page.
- **Why:** glass over pure black has nothing to show, so it reads as grey plastic. A little light behind it makes it read as glass.
- **It stays fixed.** The page scrolls and the panels move over it, so each card catches more light as it rises.
- **It is dim on purpose:** well under 2% luminance, a glow rather than a colour.
- **Where contrast is checked:** the glow is centred above the screen, so by the top of the first card (under the status bar and a header) it is at most 80% of its strength: about 52% on a 390 pt phone, 73% on a tablet. Words on glass are checked at 80%. Words directly on the page, above the cards, are checked on the full glow.
- **The conversation doesn't show it.** Qamar's words sit on plain black.

## Colour: light (for products that need it)

Qamar ships dark only. A product that needs a light mode uses this ramp. The values are contrast-checked and proposed, not yet used in Qamar. Don't reuse the dark alphas: the same alpha gives different contrast on white than on black.

| Token | Value | Contrast on `canvas` |
|---|---|---|
| `canvas` | `#FFFFFF` | — |
| `surface` | `#F5F5F5` | — |
| `surfaceRaised` | `#EDEDED` | — |
| `surfaceHigh` | `#E0E0E0` | — |
| `ink` | `#000000` | 21:1 |
| `inkSecondary` | `#3B3B3B` | 11.2:1 |
| `inkTertiary` | `#666666` | 5.7:1 (4.9:1 on `surfaceRaised`) |
| `inkDisabled` | `#999999` | 2.8:1: disabled only |
| `hairline` / `hairlineStrong` | black @ 10% / 22% | — |
| `glassFill` / pressed / clear | white @ 60% / 75% / 35% | plus the blur |
| `glassEdgeTop` / `glassEdgeBottom` | white @ 90% / black @ 6% | — |
| `scrim` | black @ 32% | — |

- **Burgundy carries over.** The primary is still `accent` with white words. On white, `accent` itself reads 8.9:1, so it can also be the foreground where dark mode uses `accentInk`.
- **Not worked out yet:** glass panels and the page's light in light mode. Work them out and check contrast before shipping one.

## Contrast table (dark)

These are WCAG 2 ratios. Text needs 4.5:1, or 3:1 at 18 pt+ or bold 14 pt+. `colors_test.dart` asserts them.

| Ground | `ink` | `inkSecondary` | `inkTertiary` | `inkDisabled` | `accentInk` |
|---|---|---|---|---|---|
| `canvas` | 21.0 | 12.4 | 7.4 | 3.7 | 7.4 |
| `surface` | 18.7 | 11.1 | 6.6 | 3.3 | 6.6 |
| `surfaceRaised` (and `glassSolid`) | 16.7 | 9.9 | 5.9 | 2.9 | 5.9 |
| `surfaceHigh` | 14.0 | 8.3 | 4.9 | 2.4 | 4.9 |
| the page, at the full glow | 18.3 | 10.8 | 6.4 | 3.2 | 6.5 |
| a pane's top, over black | 17.4 | 10.3 | 6.1 | 3.0 | 6.1 |
| a pane's top, in the light (80%) | 15.0 | 8.8 | 5.2 | 2.6 | 5.3 |
| a raised pane, in the light | 13.1 | 7.8 | 4.6 | 2.3 | 4.6 |
| an inset in a pane, in the light | 12.9 | 7.7 | 4.5 | 2.3 | 4.6 |
| a sheet (its lens over `glassSheet`) | 14.9 | 8.8 | 5.2 | 2.6 | 5.3 |
| floating glass over black | 16.5 | 9.8 | 5.8 | 2.9 | 5.8 |
| pressed glass over black | 13.6 | 8.0 | 4.8 | 2.4 | 4.8 |

- **Every readable ink passes on every ground here.** `inkDisabled` is below AA on purpose, and is never used for text that must be read.
- **Marks are graphics.** A bar on its track, the streak ring and a radio mark are held to WCAG's 3:1 for graphics, not 4.5. `accentInk` against a bar's `hairline` track on a pane in the light is 3.4:1.
- **Words on burgundy:** white on `accent` is 8.9:1, under burgundy glass's lens (`accent` plus `glassFill`) about 6.8:1, and on `accentPressed` 11.1:1. White on a chosen row (`accentWash` over black) is 18.6:1.
- **Over a photo,** use the thin fill with the 35% dim, and put only `ink` on it.

## Type

Families: **Inter** (Latin), with **Noto Sans Arabic** as the fallback on every style (Arabic letters and ٠–٩). Both are bundled at 400/500/600/700. Noto Sans Arabic has true tabular Arabic-Indic digits.

| Builder (Qamar) | Sizes : line heights | Default weight | Tracking |
|---|---|---|---|
| `QText.display(size:, ar:)` | 20:25, 22:28, 28:34, 34:41 | 700 | by size; 0 when `ar` |
| `QText.body(size:)` | 11:13, 12:16, 13:18, 15:20, 16:21, 17:22 | 400 | always 0 (it carries both scripts) |
| `QText.number(size:)` | text sizes, or figures 20, 28, 34, 48, 56 | 500 | by size; tabular figures |
| `QText.eyebrow(ar:)` | 12:16 | 600 | 0.6 pt Latin (uppercase); 0 Arabic |
| `HeroNumber(text)` | 56 (`HeroNumber.heroSize`), tight leading | 700 | by size; tabular figures |

**Tracking:**
- Latin tracking is `size × (−0.0223 + 0.185·e^(−0.1745·size))` from size 20 up, and 0 below: about −1.7% at 20 and −2.2% at 34 and above.
- Arabic is never tracked.

**Reading and emphasis:**
- Chat reading text is 17 with a 24–26 line height; long Arabic reads better at 26.
- Emphasis is weight (600), never italics. Italic Arabic doesn't exist.

## Space, radii, targets

| Token | Value |
|---|---|
| `QSpace.xs` / `sm` / `md` / `lg` / `xl` / `xxl` / `xxxl` | 4 / 8 / 12 / 16 / 20 / 24 / 32 |
| `QSpace.page` | 20 (side margin) |
| `QRadii.pill` | capsule (StadiumBorder) |
| `QRadii.inset` | 12 |
| `QRadii.control` | 18 (field, notice) |
| `QRadii.card` | 24 (card, chat bubble) |
| `QRadii.sheet` | 32 (top corners) |
| `QRadii.inside(outer, gap)` | concentric inner corner |
| `QLayout.minTap` | 48 × 48 |
| `QLayout.orbBand` / `pageBottom` / `pageTop` | 72 / 96 / 16 |

## Motion

| Token | Value |
|---|---|
| `QSpring.settle` | damping 1.0, response 0.35 s: all arrivals and moves |
| `QSpring.flick` | damping 0.8, response 0.35 s: only after a thrown gesture (release > 700 pt/s) |
| press | scale 0.97, 100–120 ms, on touch-down; reduce motion: opacity 0.7 |
| state change | 200–250 ms, `Curves.easeOutCubic` |
| arrive (duration-based, when a spring won't do) | 320–400 ms, `Cubic(0.22, 1, 0.36, 1)` (ease-out quint) |
| leave | 200–250 ms, `Cubic(0.16, 1, 0.3, 1)` (ease-out expo), same path as arrival |
| active breath (waiting, listening) | 2.4 s period, sine, 100% ↔ 50% (`QMotion.ring`) |
| idle breath (the orb at rest) | 4.6 s period (`QMotion.breath`) |
| attention | two 150 ms dips to 30%, once |
| reduce motion | ≤ 150 ms cross-fade; no breath, orbit, parallax, scale or blur animation; every loop stopped |
