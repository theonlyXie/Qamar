# Liquid Glass, in black, white and burgundy

Apple describes Liquid Glass as "a distinct functional layer for controls and navigation elements… that floats above the content layer". It "has no inherent color, and instead takes on colors from the content directly behind it".

We go further than Apple, who keeps glass out of the content layer: in our products glass is the material of the whole interface, because black and white alone felt flat. We keep the reasons behind Apple's caution:
- **cards never blur**, so they stay cheap and their words never depend on what scrolls behind them;
- **glass never stacks**, except as an inset;
- **glass has something to take colour from:** the page's burgundy light.

## Where it goes

| Glass | Kind |
|---|---|
| Cards and grouped lists | panels: lens fill and rim, no blur |
| Sheets | frosted panels: `glassSheet` over a sigma-24 blur |
| Any other panel floating over scrolling content | panels that blur (sigma 20) |
| The orb, the composer, round header buttons, the tree's circles, the Su chip, the orb's receipt | floating controls: blur (sigma 20), fill, lens, specular edge |
| The primary button, the pill button, the send circle once there is text, a chosen chip | burgundy-tinted glass |
| Secondary buttons, unchosen chips, a turn's suggested next step, the composer's mic and stop, a segmented control's track | clear glass |
| A pressed pane, or a pane standing inside another | a raised pane: a flat `glassRaised` fill |
| A block inside a pane, such as the gesture guide's cells | an inset (`glassInset`) |

**Not glass:**
- the conversation's messages: Qamar's words are plain text on black, and the person's sit in a `surfaceHigh` bubble;
- text fields (`surfaceRaised`), where typing needs a fixed ground;
- the page itself: black, under its light.

## The page's light

- `QDecor.ambient`, painted once by the shell behind every page: `ambient` glowing from above the top of the screen, gone to black by about the middle.
- It stays still while the page scrolls. The panels move over it, so each card catches more light as it rises.
- Without it, glass over pure black has nothing to show and reads as grey plastic.
- By the top of the first card it is at most 80% of its strength, and that is where words on glass are checked (see `tokens.md`).

## Panels: cards, grouped lists, sheets

Back to front:
1. **Fill:** a vertical gradient from `glassPanelTop` (white 10%) at the top to `glassPanel` (white 7%). That's the lens, the way light catches in a curved surface.
2. **Rim:** a 1 pt edge (`QGlassRim`): `glassRim` (white 28%) along the top, fading to `hairline` (14%) by the middle and staying there down the sides and along the bottom. Something that must read as a boundary (a chosen or focused panel, a sheet) takes the stronger rim.
3. **No shadow.** On black a shadow has nothing to darken; the lens and the rim are the lift.
4. **Blur:**
   - **Cards: none.** They are content that scrolls, blur there costs frames, and what shows through them is the page's light, which is smooth anyway.
   - **Sheets: frosted.** A `glassSheet` ground (`surface` at 78%) over a sigma-24 blur, with the lens and the strong rim on top, so a sheet's words never depend on what is behind it.
   - **Any other panel floating over scrolling content: sigma 20.**
5. **Raised and inset:**
   - A pressed pane, or a pane standing inside another, is raised: a flat `glassRaised` fill (white 14%) instead of the gradient.
   - A block inside a pane, such as the gesture guide's cells, is an inset: `glassInset` (white 5%), with no rim of its own.
6. **Content** on a panel uses the ink tokens. Every readable ink holds 4.5:1 on a pane, a raised pane and an inset in the page's light (see `tokens.md`, contrast).

In Qamar, a card is `QDecor.card()`, and `QDecor.card(color: QColors.surfaceRaised)` gives the raised form. Sheets come from `QSheetSlot`.

```dart
Container(
  padding: const EdgeInsets.all(QSpace.xl),
  decoration: QDecor.card(),                    // raised: QDecor.card(color: QColors.surfaceRaised)
  child: …,
)
```

## Floating controls

Back to front:
1. **Clip** to the shape: a capsule for controls, a circle for icon buttons, a concentric rounded rectangle for a floating panel.
2. **Blur** what's behind it: sigma 20, or 12–16 for small chips. The blur is what makes it read as a material instead of a hole.
3. **Fill** with a breath of white: `glassFill` (12%), or `glassFillPressed` (18%) while pressed.
4. **Lens:** the top 55% is a touch brighter: `glassLens` (white 8%) fading to 0.
5. **Specular edge:** a 1 pt stroke, inset half a point, running from `glassEdgeTop` (40%) at the top to `glassEdgeBottom` (8%) from halfway down.
6. **Content** on top uses `ink` for words and glyphs, and never `inkDisabled` for anything that must be read.

In Qamar this is `QGlass` (`app/lib/widgets/glass.dart`):

```dart
QGlass(
  shape: QGlassShape.circle,    // capsule (default) | circle | rounded (with radius:)
  width: 44, height: 44,
  pressed: pressed,              // from QTapArea's builder
  child: Icon(QIcons.close, size: 22, color: QColors.ink),
)
```

Wrap it in `QTapArea` for the press, the 48 pt target and the spoken label. Don't build a `BackdropFilter` by hand.

## Burgundy glass: the primary, the pill, the send circle, a chosen chip

- **Recipe:** `QGlass(tint: QColors.accent)`. The fill is `accent` (`accentPressed` while pressed). The lens is drawn in `glassFill` (white 12%), and the rim is `glassRimTinted` (white 55%), brighter than clear glass's. Words and glyphs are `onAccent`.
- **It doesn't blur.** Nothing shows through burgundy, so there is nothing to blur.
- **Sizes:** the primary is 52 tall (48 in a dense card), the pill 40, and the send circle 36 inside its 48 target.
- **One burgundy action per screen:** the primary button, or in the conversation the send circle once there is something to send. Chosen chips are burgundy too, as many as are chosen, because they mark what is chosen rather than what to do.
- **The send circle is burgundy only when there is text.** Beside an empty field it is the microphone, in clear glass, and so is stop. The onboarding composer's send works the same way.
- **`accentWash`** is the gentler form: burgundy washed into a row or a panel to say it is chosen, with white words on it.

## Clear glass: secondary buttons, unchosen chips, the mic and stop

- **Clear means untinted:** white glass (`glassFill`) with the lens and the specular edge, and `ink` words.
- **A turn's suggested next step** is a clear glass chip too, with `accentInk` words at 600. It is a way on, not the screen's burgundy action.
- **On a card it doesn't blur.** Nothing moves behind it, so a blur would cost frames for nothing.
- **The thin fill is something else.** `glassFillClear` (`QGlass(clear: true)`) is for controls over a photo or the live camera. It needs a 35% black dim, either local (behind the control) or over the whole photo, and the content on it must be bold and white. Never mix the thin fill with the regular one on one screen.

## Segmented controls

- The track is clear glass. The chosen segment is a neutral raised glass pill: a step brighter than the track, with a strong edge.
- It is never burgundy. A mode (the language, a wallet tab) is not an action.
- The segment moves between choices in 200 ms.

## Glass on glass

- **A shape inside a panel is an inset** (`glassInset`) or a raised pane (`glassRaised`), never a second panel with its own rim.
- **Controls on a panel don't blur.** Clear and burgundy glass sit on cards as fills and edges only.
- **Never put a blurring layer on top of another blurring layer**, such as a blurring chip on a sheet.

## Accessibility behaviour (hand-built, because Flutter gives us none of Apple's for free)

| Setting | What glass does |
|---|---|
| Increase Contrast (`MediaQuery.highContrastOf`) | Floating glass and sheets turn solid: `glassSolid` (`surfaceRaised`), a `hairlineStrong` 1 pt edge, no blur, no lens. Burgundy glass stays burgundy, drawn solid with the strong edge, because it is still the one thing to do. Cards keep their pane: they already sit over black, and they have the rim |
| Reduce Transparency (iOS; there's no Flutter flag, so it needs a platform channel if we add it) | The same solid treatment |
| Reduce Motion (`MediaQuery.disableAnimationsOf`) | No elastic morphing and no animated blur. Glass fades in and out |
| Bold Text | Its labels follow the text styles, which honour it |

## Motion

- **Glass materialises; it doesn't slide in as a flat box.** It arrives with a spring (damping 1.0, response 0.35): opacity 0 → 1 together with scale 0.96 → 1, from where it's anchored.
- **Press feedback** is a brighter fill (`glassFillPressed`; `accentPressed` on burgundy; `glassRaised` for a pane) plus a 0.97 scale, on touch-down.
- **A control that opens something** (a menu or a sheet) grows from the control. The new surface starts at the control's rect.
- **Under reduce motion,** all of this becomes a 150 ms fade.

## Scroll edges

- Where content scrolls under a floating glass control, **fade the content** over about 24 pt at that edge with a `ShaderMask` (`dstIn`, black to transparent).
- Don't draw a divider or a solid bar there.
- Use one edge effect per edge, and only where something floats over it.
- At rest (scrolled to the top), nothing should sit under floating glass. Pad the list so its first item starts below the floating controls.

## Performance

- **Keep about four blurring surfaces on screen at once.** Each `BackdropFilter` is a save layer. Cards don't blur, so they don't count.
- **Nothing large scrolls under many small glass pieces.** When a list scrolls under glass, give the glass a `RepaintBoundary`.
- Blur costs roughly sigma² per pixel. Keep sigma at 24 or less: 24 for sheets, 20 for floating controls, 12–16 for small chips.
- In golden tests, a card over the page's light is a faintly warm grey panel with a bright top edge, and floating glass over plain black is a grey capsule with a bright top edge. Both are expected.
