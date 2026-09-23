# Mono-glass in Flutter (Qamar's kit)

Qamar is the reference implementation (`app/`). Other Flutter products copy `lib/theme/` and `lib/widgets/{glass,dot_number,common}.dart` and keep the same names.

## Contents
- The kit, file by file
- Do and don't
- The tests that enforce the design
- Rendering screens to look at them
- Checks before a push

## The kit, file by file

| File | What's in it |
|---|---|
| `lib/theme/colors.dart` | `QColors`: every colour token (`canvas`, `surface`, `surfaceRaised`, `surfaceHigh`, `ink`, `inkSecondary`, `inkTertiary`, `inkDisabled`, `onInk`, `hairline`, `hairlineStrong`, `glass*`, `dotOff`, `scrim`). `QBrandMarks`: Google's four colours, for the "G" only |
| `lib/theme/text_styles.dart` | `QText.display(size:, ar:)`, `QText.body(size:)`, `QText.number(size:)`, `QText.eyebrow(ar:)`, `QText.eyebrowText(text, ar:)`, `QText.arabic(text)`, `QText.tracking(size)`. Sizes off the scale assert |
| `lib/theme/icons.dart` | `QIcons.*`: every glyph by meaning (Cupertino Icons) |
| `lib/theme/app_theme.dart` | `QRadii`, `QSpace`, `QDecor.card()` / `pillOutline()` / `inkButton`, `buildQamarTheme()` (monochrome scheme, inverted switch, no splash) |
| `lib/theme/motion.dart` | `QSpring.settle` / `flick` / `drive` / `project`, `QMotion.*` durations |
| `lib/theme/layout.dart` | `QLayout.minTap` (48), `orbBand`, `pageBottom`, `pageTop` |
| `lib/widgets/glass.dart` | `QGlass(shape:, radius:, pressed:, clear:, blur:, width:, height:)`: Liquid Glass with the high-contrast solid fallback |
| `lib/widgets/dot_number.dart` | `DotNumber(text, height:, color:, semanticsLabel:)`, `DotGlyphs.widthOf` |
| `lib/widgets/common.dart` | `QTapArea` (target, label, press), `qPressed`, `QPrimaryButton`, `QOutlineButton`, `QPillButton`, `QPillChip`, `QRoundIconButton`, `QBackButton`, `QLangToggle`, `QBar`, `QStateCard` / `QStateLine` / `QStateArea`, `QSheetSlot` / `QSheetScrim`, `QSpringIn`, `QWheelField`, `QBalancedText`, `QLegalLink`, `SuCoinIcon`, `QDisabled` |
| `lib/widgets/living_orb.dart`, `moon.dart`, `orb_nav.dart`, `tree_overlay.dart` | the orb, its moon, its band and the tree |
| `lib/widgets/ask_qamar_overlay.dart` | the ChatGPT-style conversation |

## Do and don't

```dart
// DON'T
Container(color: const Color(0xFF3B82F6), child: Icon(Icons.send, color: Colors.white));
Text('Calories', style: const TextStyle(fontSize: 14, letterSpacing: 1.2));
ElevatedButton(onPressed: log, child: const Text('Log'));

// DO
QTapArea(
  label: t.send,
  onTap: send,
  builder: (context, pressed) => qPressed(context, pressed: pressed, child: const DecoratedBox(
    decoration: ShapeDecoration(color: QColors.ink, shape: CircleBorder()),
    child: SizedBox(width: 36, height: 36, child: Icon(QIcons.send, size: 20, color: QColors.onInk)),
  )),
);
Text(QText.eyebrowText(t.calories, ar: isAr), style: QText.eyebrow(ar: isAr));
QPrimaryButton(label: t.logIt, onTap: log);
```

**Layout:**
- Use `EdgeInsetsDirectional` and `AlignmentDirectional` everywhere.
- Pad orb screens with `QLayout.pageBottom`, and pages from `QLayout.pageTop`.
- Keep the page margin at `QSpace.page`.

**Text:**
- Every `Text` gets a `QText` style.
- Numbers go through `state.iso(...)` (digits setting plus bidi isolate) or `state.formatSu(...)`.
- Strings live in `lib/l10n/strings.dart`, in both languages, with Arabic written first.

**State:**
- Screens read `context.watch<AppState>()` and call its methods.
- A design change never changes a method's behaviour. Keep keys (`ValueKey`s) that tests use, or update those tests to the new design's intent.

**Semantics:**
- `QTapArea(label:)` for every tappable.
- `Semantics(label:)` on custom paint (the moon, dot numbers, rings).
- Exclude decorative paint (`ExcludeSemantics`).

**Performance:**
- Put a `RepaintBoundary` around anything animating (the orb, breathing dots) and around glass over scrolling content.
- Don't use more than about four `QGlass` on screen.

## The tests that enforce the design

These live in `app/test/`. They are part of the suite, so a design regression fails CI.

| Test | Guards |
|---|---|
| `colors_test.dart` | every `QColors` token is achromatic; no `Color(0x…)` literal outside `lib/theme/` (except `QBrandMarks` use in the Google button); ink on each surface meets 4.5:1; `inkTertiary` ≥ 4.5:1 on every surface |
| `icons_test.dart` | no Material `Icons.` in `lib/`; no `CupertinoIcons.` outside `lib/theme/icons.dart`; directional glyphs mirror |
| `type_scale_test.dart`, `typography_test.dart` | every font size in `lib/` is on the scale; Arabic is never tracked |
| `radii_test.dart` | only the kit's radii; nested corners are concentric |
| `tap_target_test.dart` | every tappable is at least 48 × 48 |
| `ground_test.dart`, `depth_test.dart` | the canvas is black; no shadows or gradients on content |
| `controls_test.dart` | primary and outline buttons draw as specified |

When a redesign changes what a test pins, **update the test to the new design's intent**. Never delete it, and never loosen a guard to get green.

## Rendering screens to look at them

`scripts/render_screens_test.dart` (in this skill) draws every screen in English and Arabic to PNGs:

```bash
cp .claude/skills/mono-glass/scripts/render_screens_test.dart app/test/zz_render_tmp_test.dart
cd app && flutter test --update-goldens test/zz_render_tmp_test.dart \
  --dart-define=OUT=$PWD/../renders --dart-define=SHOT=after --dart-define=ONLY=today
rm -f test/zz_render_tmp_test.dart; rm -rf test/failures
```

Look at every image you produced (for example with the Read tool) before calling a screen done. Compare `before` and `after` side by side for a redesign. Glass over plain black renders as a grey capsule with a bright top edge, and that's correct. The harness file is never committed.

## Checks before a push (Qamar)

```bash
cd app
flutter analyze --no-fatal-infos      # no errors or warnings
flutter test                          # everything green
TZ=Africa/Cairo flutter test test/cairo_days_test.dart --dart-define=REQUIRE_CAIRO=true
```
