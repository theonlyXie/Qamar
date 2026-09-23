# Liquid Glass, in black and white

Apple describes Liquid Glass as "a distinct functional layer for controls and navigation elements… that floats above the content layer". It "has no inherent color, and instead takes on colors from the content directly behind it". That fits mono-glass exactly: the glass is untinted, and the only light it picks up is the page's own.

## Where it goes

| Glass | Not glass |
|---|---|
| The orb and its band | Cards, list rows, grouped lists |
| The chat composer | Chat messages, both the person's and the assistant's |
| Floating back and close circles | Numbers, charts, dot displays |
| The tree's ring buttons | Page backgrounds |
| A chip floating over content (Su balance, a receipt) | Form fields inside a card |
| The language toggle's track | Anything that is itself on glass |
| Camera controls over the viewfinder (clear, with a dim) | Toasts that sit in the content flow |

**The test:** does it float above the page, and does a finger act on it? If both answers are yes, it's glass. If either is no, it's a solid surface.

## The recipe (back to front)

1. **Clip** to the shape: a capsule for controls, a circle for icon buttons, a rounded rectangle (concentric) for a panel.
2. **Blur** what's behind it: sigma 20 for regular glass, 12–16 for small chips. The blur is what makes it read as a material instead of a hole.
3. **Fill** with a breath of white:
   - `glassFill` (white 12%);
   - `glassFillPressed` (18%) while pressed;
   - `glassFillClear` (6%) for clear glass over media.
4. **Lens:** the top 55% is a touch brighter (white 8% fading to 0), the way light catches in a curved surface.
5. **Specular edge:** a 1 pt stroke, inset half a point, running from `glassEdgeTop` (40%) at the top to `glassEdgeBottom` (8%) from halfway down.
6. **Content** on top uses `ink` for words and glyphs. It never sits on more glass, and it never uses `inkDisabled` for anything that must be read.

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

## Regular vs clear

- **Regular** is the default and the right choice almost everywhere. It works over any content, and anything can sit on it.
- **Clear** is for controls over a photo or the live camera only. It needs a 35% black dim, either local (behind the control) or over the whole photo, and the content on it must be bold and white.
- Never mix the two on one screen.

## Accessibility behaviour (hand-built, because Flutter gives us none of Apple's for free)

| Setting | What glass does |
|---|---|
| Increase Contrast (`MediaQuery.highContrastOf`) | Turns solid: `glassSolid` fill (`surfaceRaised`), a `hairlineStrong` 1 pt edge, no blur, no lens |
| Reduce Transparency (iOS; there's no Flutter flag, so it needs a platform channel if we add it) | The same solid treatment |
| Reduce Motion (`MediaQuery.disableAnimationsOf`) | No elastic morphing and no animated blur. Glass fades in and out |
| Bold Text | Its labels follow the text styles, which honour it |

## Motion

- **Glass materialises; it doesn't slide in as a flat box.** It arrives with a spring (damping 1.0, response 0.35): opacity 0 → 1 together with scale 0.96 → 1, from where it's anchored.
- **Press feedback** is `glassFillPressed` plus a 0.97 scale, on touch-down.
- **A control that opens something** (a menu or a sheet) grows from the control. The new surface starts at the control's rect.
- **Under reduce motion,** all of this becomes a 150 ms fade.

## Scroll edges

- Where content scrolls under a floating glass control, **fade the content** over about 24 pt at that edge with a `ShaderMask` (`dstIn`, black to transparent).
- Don't draw a divider or a solid bar there.
- Use one edge effect per edge, and only where something floats over it.
- At rest (scrolled to the top), nothing should sit under the glass. Pad the list so its first item starts below the floating controls.

## Performance

- **Keep about four glass surfaces on screen at once.** Each `BackdropFilter` is a save layer.
- **Nothing large scrolls under many small glass pieces.** When a list scrolls under glass, give the glass a `RepaintBoundary`.
- Blur costs roughly sigma² per pixel. Keep sigma at 20 or less, and use 12–16 for small chips.
- In widget tests, blur renders fine. In golden tests, glass over plain black looks like a grey capsule with a bright top edge, and that's expected.
