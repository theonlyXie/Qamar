# Tokens

Every value mono-glass uses. In Qamar these live in `app/lib/theme/` (`colors.dart`, `text_styles.dart`, `app_theme.dart`, `motion.dart`, `layout.dart`). Screens use the names, never the values.

## Contents
- Colour: dark (the default)
- Colour: light (for products that need it)
- Contrast table
- Type
- Space, radii, targets
- Motion
- Dot matrix

## Colour: dark (the default)

Every grey is achromatic (R = G = B). Alpha tokens are white over whatever is behind.

| Token | Hex / alpha | Notes |
|---|---|---|
| `black` / `canvas` | `#000000` | page background, OLED black |
| `surface` | `#121212` | cards |
| `surfaceRaised` | `#1E1E1E` | pressed card, field, solid glass (`glassSolid`), round icon button |
| `surfaceHigh` | `#2C2C2C` | user bubble, bar track, switch-off track, selected band |
| `white` / `ink` | `#FFFFFF` | primary text, icons, primary button fill |
| `inkSecondary` | `#C7C7C7` | secondary text |
| `inkTertiary` | `#999999` | labels, eyebrows, meta, placeholders |
| `inkDisabled` | `#666666` | disabled labels and decorative marks only |
| `onInk` | `#000000` | text and icons on a white fill |
| `hairline` | `#FFFFFF` @ 14% (`0x24FFFFFF`) | card edge, divider |
| `hairlineStrong` | `#FFFFFF` @ 28% (`0x47FFFFFF`) | outline button, emphasis edge, solid-glass edge |
| `glassFill` | `#FFFFFF` @ 12% (`0x1FFFFFFF`) | regular glass |
| `glassFillPressed` | `#FFFFFF` @ 18% (`0x2EFFFFFF`) | glass while pressed (the third ink still passes AA on it) |
| `glassFillClear` | `#FFFFFF` @ 6% (`0x0FFFFFFF`) | clear glass, over photos only |
| `glassEdgeTop` | `#FFFFFF` @ 40% (`0x66FFFFFF`) | specular edge, top |
| `glassEdgeBottom` | `#FFFFFF` @ 8% (`0x14FFFFFF`) | specular edge, fading down the sides |
| `scrim` | `#000000` @ 64% (`0xA3000000`) | behind a modal sheet |
| `dotOff` | `#FFFFFF` @ 11% (≈ `#1C1C1C`) | an unlit dot in a ring or matrix (Nothing's own value) |

**Not tokens, and allowed only here:**
- `QBrandMarks.google*`: the four colours of Google's "G" on the sign-in button, which Google's brand rules require.
- Pixels of a photograph.

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
| `onInk` | `#FFFFFF` | on a black fill |
| `hairline` / `hairlineStrong` | black @ 10% / 22% | — |
| `glassFill` / pressed / clear | white @ 60% / 75% / 35% | plus the blur |
| `glassEdgeTop` / `glassEdgeBottom` | white @ 90% / black @ 6% | — |
| `scrim` | black @ 32% | — |

In light mode the primary button is **black with white words**. The rule is inversion: the brightest-contrast fill is the one thing to do.

## Contrast table (dark)

These are WCAG 2 ratios. Text needs 4.5:1, or 3:1 at 18 pt+ or bold 14 pt+.

| Ink ↓ on → | `canvas` #000 | `surface` #121212 | `surfaceRaised` #1E1E1E | `surfaceHigh` #2C2C2C |
|---|---|---|---|---|
| `ink` #FFF | 21.0 | 18.7 | 16.7 | 14.0 |
| `inkSecondary` #C7C7C7 | 12.4 | 11.1 | 9.9 | 8.3 |
| `inkTertiary` #999 | 7.4 | 6.6 | 5.9 | 4.9 |
| `inkDisabled` #666 | 3.7 | 3.3 | 2.9 | 2.4, never for text that must be read |

On glass, the effective background is the blurred page plus 12% white. Over the black canvas that is about `#1F1F1F`, so the `surfaceRaised` column applies. Over a photo, use clear glass with the 35% dim, and put only `ink` on it.

## Type

Families: **Inter** (Latin), with **Noto Sans Arabic** as the fallback on every style (Arabic letters and ٠–٩). Both are bundled at 400/500/600/700. Noto Sans Arabic has true tabular Arabic-Indic digits.

| Builder (Qamar) | Sizes : line heights | Default weight | Tracking |
|---|---|---|---|
| `QText.display(size:, ar:)` | 20:25, 22:28, 28:34, 34:41 | 700 | by size; 0 when `ar` |
| `QText.body(size:)` | 11:13, 12:16, 13:18, 15:20, 16:21, 17:22 | 400 | always 0 (it carries both scripts) |
| `QText.number(size:)` | text sizes, or figures 20, 28, 34, 48 | 500 | by size; tabular figures |
| `QText.eyebrow(ar:)` | 12:16 | 600 | 0.6 pt Latin (uppercase); 0 Arabic |

**Tracking:**
- Latin tracking is `size × (−0.0223 + 0.185·e^(−0.1745·size))` from size 20 up, and 0 below: about −1.7% at 20 and −2.2% at 34.
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
| dot stagger | 12–20 ms per dot |
| reduce motion | ≤ 150 ms cross-fade; no breath, orbit, parallax, scale or blur animation |

## Dot matrix

- **`DotNumber`:** a 5 × 7 grid per glyph, with round dots. The pitch is height ÷ 7 and the dot radius is 0.36 × pitch (about 0.72 × pitch across, close to Nothing's 0.74). There is one column of gap between glyphs.
- **Glyphs:** 0–9, ٠–٩, and ` . , ٫ ٬ : / - + % ٪ ×`.
- **Use:** at most one per screen, at least 40 pt tall, `ink` on `canvas` or `surface`.
- **Dot rings:** 24 dots (compact) or 36 (≥ 120 pt), clockwise from 12 o'clock in both languages. Three brightness levels at most: lit 100%, half 50%, off `dotOff`.
