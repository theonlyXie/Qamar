# Liquid-glass in Flutter (Qamar's kit)

Qamar is the reference implementation (`app/`). Other Flutter products copy `lib/theme/` and `lib/widgets/{glass,hero_number,common}.dart` and keep the same names.

## Contents
- The kit, file by file
- Do and don't
- The tests that enforce the design
- Rendering screens to look at them
- Checks before a push

## The kit, file by file

| File | What's in it |
|---|---|
| `lib/theme/colors.dart` | `QColors`: every colour token (`black`, `white`, `canvas`, `ambient`, `surface`, `surfaceRaised`, `surfaceHigh`, `ink`, `inkSecondary`, `inkTertiary`, `inkDisabled`, `onInk`, `accent`, `accentPressed`, `accentInk`, `accentWash`, `onAccent`, `hairline`, `hairlineStrong`, `glassPanel`, `glassPanelTop`, `glassRaised`, `glassInset`, `glassRim`, `glassSheet`, `glassFill`, `glassFillPressed`, `glassFillClear`, `glassLens`, `glassEdgeTop`, `glassEdgeBottom`, `glassRimTinted`, `glassSolid`, `scrim`). `QBrandMarks`: Google's four colours, for the "G" only |
| `lib/theme/text_styles.dart` | `QText.display(size:, ar:)`, `QText.body(size:)`, `QText.number(size:)` (figures 20, 28, 34, 48, 56), `QText.eyebrow(ar:)`, `QText.eyebrowText(text, ar:)`, `QText.arabic(text)`, `QText.tracking(size)`. Sizes off the scale assert |
| `lib/theme/icons.dart` | `QIcons.*`: every glyph by meaning (Cupertino Icons) |
| `lib/theme/app_theme.dart` | `QRadii`, `QSpace`; `QDecor.card()`: a glass panel (the gradient fill plus a `QGlassRim` border), and `QDecor.card(color: QColors.surfaceRaised)` for the raised, flat `glassRaised` form; `QDecor.ambient`: the page's light, painted once by the shell; `QGlassRim`: a `BoxBorder` that paints the specular rim; `buildQamarTheme()` (the switch: a burgundy track and a white thumb when on; no splash) |
| `lib/theme/motion.dart` | `QSpring.settle` / `flick` / `drive` / `project`, `QMotion.*` durations |
| `lib/theme/layout.dart` | `QLayout.minTap` (48), `orbBand`, `pageBottom`, `pageTop` |
| `lib/widgets/glass.dart` | `QGlass(shape:, radius:, pressed:, clear:, blur:, tint:, width:, height:)`: floating glass with the high-contrast solid fallback, and, with `tint: QColors.accent`, burgundy glass |
| `lib/widgets/hero_number.dart` | `HeroNumber(text, semanticsLabel:)`: the large numeral, one per screen, at `HeroNumber.heroSize` (56) |
| `lib/widgets/common.dart` | `QTapArea` (target, label, press), `qPressed`, `QPrimaryButton` and `QPillButton` (burgundy glass), `QOutlineButton` (clear glass), `QPillChip` (chosen = burgundy), `QRoundIconButton`, `QBackButton`, `QLangToggle`, `QBar`, `QStateCard` / `QStateLine` / `QStateArea`, `QSheetSlot` / `QSheetScrim`, `QSpringIn`, `QWheelField`, `QBalancedText`, `QLegalLink`, `SuCoinIcon`, `QDisabled` |
| `lib/widgets/living_orb.dart`, `moon.dart`, `orb_nav.dart`, `tree_overlay.dart` | the orb, its moon, its band, the streak ring (`StreakRingPainter`: seven arc segments) and the tree |
| `lib/widgets/ask_qamar_overlay.dart` | the ChatGPT-style conversation |

## Do and don't

```dart
// DON'T
Container(color: const Color(0xFF3B82F6), child: Icon(Icons.send, color: Colors.white));
Text('Calories', style: const TextStyle(fontSize: 14, letterSpacing: 1.2));
ElevatedButton(onPressed: log, child: const Text('Log'));
BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: card);  // a card that blurs
Text('Over your goal', style: QText.body(size: 15, color: QColors.accentInk));  // burgundy as status

// DO
QTapArea(
  label: t.send,
  onTap: send,
  builder: (context, pressed) => qPressed(context, pressed: pressed, child: QGlass(
    shape: QGlassShape.circle,
    tint: QColors.accent,                   // the send circle: only while there is text
    pressed: pressed,
    width: 36, height: 36,
    child: const Icon(QIcons.send, size: 18, color: QColors.onAccent),
  )),
);
Text(QText.eyebrowText(t.calories, ar: isAr), style: QText.eyebrow(ar: isAr));
QPrimaryButton(label: t.logIt, onTap: log);
Container(padding: const EdgeInsets.all(QSpace.xl), decoration: QDecor.card(), child: …);
```

**Layout:**
- Use `EdgeInsetsDirectional` and `AlignmentDirectional` everywhere.
- Pad orb screens with `QLayout.pageBottom`, and pages from `QLayout.pageTop`.
- Keep the page margin at `QSpace.page`.

**Glass:**
- A card is `QDecor.card()`. It is never a `QGlass`, and never gets a `BackdropFilter`.
- The page's light belongs to the shell (`QDecor.ambient`). Screens leave their background clear so it shows; only the conversation covers it, with black.
- Burgundy comes through the kit (`QPrimaryButton`, `QPillButton`, `QPillChip`, the switch theme, `QGlass(tint:)` for the send circle once there is text). A screen never paints `accent` itself.
- Quiet actions are `inkSecondary`. A way on (`QStateLine`'s action, a turn's next step) is `accentInk` at 600. `QLegalLink` stays `inkTertiary`, underlined.

**Text:**
- Every `Text` gets a `QText` style.
- Numbers go through `state.iso(...)` (digits setting plus bidi isolate) or `state.formatSu(...)`.
- Strings live in `lib/l10n/strings.dart`, in both languages, with Arabic written first.

**State:**
- Screens read `context.watch<AppState>()` and call its methods.
- A design change never changes a method's behaviour. Keep keys (`ValueKey`s) that tests use, or update those tests to the new design's intent.

**Semantics:**
- `QTapArea(label:)` for every tappable.
- `Semantics(label:)` on custom paint and on the hero (the moon, `HeroNumber`, the streak ring).
- Exclude decorative paint (`ExcludeSemantics`).

**Performance:**
- Put a `RepaintBoundary` around anything animating (the orb, breathing dots) and around glass over scrolling content.
- Don't use more than about four blurring surfaces on screen. Cards don't blur, so they don't count.

## The tests that enforce the design

These live in `app/test/`. They are part of the suite, so a design regression fails CI.

| Test | Guards |
|---|---|
| `colors_test.dart` | every token is achromatic or burgundy; no `Color(0x…)` literal outside `lib/theme/` (the moon's greys aside); Google's G only on the account sheet; each ink passes AA on every surface, on glass, on a sheet, on the page at the full glow, and on a pane, a raised pane and an inset at 80% of the glow; white passes on burgundy, under its lens and pressed; `accentInk` passes 4.5:1 on panes and 3:1 as a bar on its track; every solid value is written in this skill's `references/tokens.md` |
| `icons_test.dart` | no Material `Icons.` in `lib/`; no `CupertinoIcons.` outside `lib/theme/icons.dart`; directional glyphs mirror |
| `type_scale_test.dart`, `typography_test.dart` | every font size in `lib/` is on the scale; Arabic is never tracked |
| `radii_test.dart` | only the kit's radii; nested corners are concentric |
| `tap_target_test.dart` | every tappable is at least 48 × 48 |
| `ground_test.dart`, `depth_test.dart` | what covers the screen reaches its edges; no surface casts a shadow |
| `controls_test.dart` | buttons, chips, switches and segments draw as specified |

When a redesign changes what a test pins, **update the test to the new design's intent**. Never delete it, and never loosen a guard to get green. If you change a colour token, change `references/tokens.md` with it: `colors_test.dart` reads it.

## Rendering screens to look at them

`scripts/render_screens_test.dart` (in this skill) draws every screen in English and Arabic to PNGs:

```bash
cp .claude/skills/liquid-glass/scripts/render_screens_test.dart app/test/zz_render_tmp_test.dart
cd app && flutter test --update-goldens test/zz_render_tmp_test.dart \
  --dart-define=OUT=$PWD/../renders --dart-define=SHOT=after --dart-define=ONLY=today
rm -f test/zz_render_tmp_test.dart; rm -rf test/failures
```

Look at every image you produced (for example with the Read tool) before calling a screen done. Compare `before` and `after` side by side for a redesign. Cards render as faintly warm grey panels over the page's light, and floating glass over black as a grey capsule with a bright top edge; both are correct. The harness file is never committed.

## Checks before a push (Qamar)

```bash
cd app
flutter analyze --no-fatal-infos      # no errors or warnings
flutter test                          # everything green
TZ=Africa/Cairo flutter test test/cairo_days_test.dart --dart-define=REQUIRE_CAIRO=true
```
