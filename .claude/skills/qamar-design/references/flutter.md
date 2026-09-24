# qamar-design in Flutter (Qamar's kit)

Qamar is the reference implementation (`app/`). Other Flutter products copy `lib/theme/` and `lib/widgets/{surface,kit,common,hero_number,mascot}.dart` and keep the same names.

## Contents
- The kit, file by file
- Do and don't
- The tests that enforce the design
- Rendering screens to look at them
- Checks before a push

## The kit, file by file

| File | What's in it |
|---|---|
| `lib/theme/colors.dart` | `QColors`: every colour token — the greys (`canvas`, `surface`, `surfaceRaised`, `surfaceHigh`), the inks (`ink`, `inkSecondary`, `inkTertiary`, `inkDisabled`, `onInk`), the pastels (`lavender`, `lime`, `mint`, `coral`, `onPastel`, `onPastelSecondary`, `pastelTrack`), burgundy (`accent`, `accentPressed`, `accentInk`, `accentWash`, `onAccent`), edges (`hairline`, `hairlineStrong`), `error`, `overPhoto`, `overPhotoPressed`, `scrim`. `QBrandMarks`: Google's four colours, for the "G" only |
| `lib/theme/text_styles.dart` | `QText.display(size:, ar:)` (20, 24, 28, 34), `QText.body(size:)` (12, 13, 15, 16, 17, 18), `QText.number(size:)` (and figures 20, 24, 28, 34, 48, 56), `QText.eyebrow(ar:)`, `QText.arabic(text)`. Space Grotesk, then Noto Sans Arabic, then Inter. Sizes off the scale assert; nothing is tracked |
| `lib/theme/icons.dart` | `QIcons.*`: every glyph by meaning (Iconsax), `QIcons.onFor` for a chosen tab's bold glyph; `QIcon`, which draws every glyph and turns the close mark |
| `lib/theme/app_theme.dart` | `QRadii` (`control` 12, `inset` 16, `card` 24, `sheet` 32, `pill`, `inside`), `QSpace`; `QDecor.card()` (the card grey and its edge), `QDecor.pastel(color)`, `QDecor.capsule()`, `QDecor.segmentTrack` / `segmentThumb` / `segmentRest`; `buildQamarTheme()` (fields, the switch, the selection; no splash) |
| `lib/theme/motion.dart` | `QSpring.settle` / `flick` / `drive` / `project`, `QMotion.*` durations |
| `lib/theme/layout.dart` | `QLayout.minTap` (48), `tabBar` (66), `tabBarGap` (12), `tabBand` (78), `pageBottom`, `pageTop` |
| `lib/widgets/surface.dart` | `QSurface(shape:, radius:, pressed:, clear:, tint:, width:, height:)`: a control's flat fill — the control grey, a step lighter pressed, burgundy with `tint: QColors.accent`, the dark at half over a photo with `clear: true` |
| `lib/widgets/kit.dart` | the Nutri AI kit's pieces: `QPageTitle`, `QSectionTitle`, `PastelCard`, `PastelGlyph`, `QPastelButton`, `QSegmented`, `QListGroup` / `QListRow`, `CalorieGauge`, `MacroTile`, `QEmptyState` |
| `lib/widgets/common.dart` | `QTapArea` (target, label, press), `qPressed`, `QPrimaryButton`, `QPillButton`, `QOutlineButton`, `QPillChip`, `QRoundIconButton`, `QBackButton`, `QLangToggle`, `QBar`, `QStateCard` / `QStateLine` / `QStateArea`, `QSheetSlot` / `QSheetScrim` / `QSheetPanel` (`scrolls:`), `QSpringIn`, `QWheelField`, `QBalancedText`, `QLegalLink`, `SuCoinIcon`, `QDisabled` |
| `lib/widgets/tab_bar.dart` | `QTabBar` (the bar, its tabs and the orb with its three gestures), `kTabs`, `TabBarFade`, `SuReceiptChip` |
| `lib/widgets/log_sheet.dart` | `LogSheet`, the orb's tap: `kLogMethods`, `kWaterChoices`, `kActivityChoices` |
| `lib/widgets/living_orb.dart`, `moon.dart` | the orb's moon, its breath and halo, the streak ring (`StreakRingPainter`) |
| `lib/widgets/mascot.dart` | `MoonMascot(size:, mood:, full:)`: the moon as the kit's cartoon character |
| `lib/widgets/hero_number.dart` | `HeroNumber`: the large figure, one per screen |
| `lib/widgets/ask_qamar_overlay.dart` | the ChatGPT-style conversation |

## Do and don't

```dart
// DON'T
Container(color: const Color(0xFF3B82F6), child: Icon(Icons.send, color: Colors.white));
Text('Calories', style: const TextStyle(fontSize: 14, letterSpacing: 1.2));
ElevatedButton(onPressed: log, child: const Text('Log'));
BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [...]);   // a number for a corner, a shadow
Text('Over your goal', style: QText.body(size: 15, color: QColors.accentInk)); // burgundy as status
Text('340 kcal', style: QText.body(size: 16, color: QColors.lavender));      // a pastel as a word on the dark

// DO
QTapArea(
  label: t.send,
  onTap: send,
  builder: (context, pressed) => qPressed(context, pressed: pressed, child: QSurface(
    shape: QSurfaceShape.circle,
    tint: QColors.accent,                    // the send circle: only while there is text
    pressed: pressed,
    width: 36, height: 36,
    child: const Center(child: QIcon(QIcons.send, size: 18, color: QColors.onAccent)),
  )),
);
Text(t.calories, style: QText.eyebrow(ar: isAr));
QPrimaryButton(label: t.logIt, onTap: log);
Container(padding: const EdgeInsets.all(QSpace.xl), decoration: QDecor.card(), child: …);
PastelCard(color: QColors.mint, child: …);   // the week's figure, black words on it
```

**Layout:**
- `EdgeInsetsDirectional` and `AlignmentDirectional` everywhere.
- A tab page pads its end by `QLayout.pageBottom` (the bar floats over the band), and starts at `QLayout.pageTop`. The page margin is `QSpace.page` (20).
- A tab page has a `QPageTitle` and no back; a page under a tab has `QPageTitle(back: state.back)` and no bar.

**Surfaces:**
- A card is `QDecor.card()` or a `PastelCard`; a control is a `QSurface`. Nothing casts a shadow, nothing is a gradient, nothing blurs but a sheet's scrim.
- Burgundy comes through the kit (`QPrimaryButton`, `QPillButton`, `QPillChip`, `QSegmented`, the switch theme, the tab bar, `QSurface(tint:)` for the send circle). A screen never paints `accent` itself.
- A pastel only as a card's ground (or a tile inside one), with `onPastel` words.

**Text:**
- Every `Text` gets a `QText` style.
- Numbers go through `state.iso(...)` (digits setting plus bidi isolate) or `state.formatSu(...)`. In Arabic keep spaces round a slash between two numbers ("٢٠ / ١٤٨"): joined, the bidi algorithm makes one number of them.
- Strings live in `lib/l10n/strings.dart`, in both languages, Arabic first; a string no screen reads is removed (`strings_test.dart`).

**State:**
- Screens read `context.watch<AppState>()` and call its methods.
- A design change never changes a method's behaviour. Keep the `ValueKey`s tests use, or update those tests to the new design's intent.

**Semantics:**
- `QTapArea(label:)` for every tappable; a tab's circle says it is selected.
- `Semantics(label:)` on custom paint and the hero; `ExcludeSemantics` on pictures (the mascot).

**Performance:**
- A `RepaintBoundary` round anything animating (the orb, a breathing dot).

## The tests that enforce the design

These live in `app/test/`, part of the suite: a design regression fails CI.

| Test | Guards |
|---|---|
| `colors_test.dart` | every token a grey, burgundy, one of the four pastels or the error red; no `Color(0x…)` outside `lib/theme/` (the moon's greys aside); Google's G only on the account sheet; every ink passes AA on every ground it sits on, pastels included; every value is written in this skill's `references/tokens.md` |
| `icons_test.dart` | no Material, Iconsax or Cupertino glyph by name and no bare `Icon` outside `lib/theme/icons.dart`; the family is Iconsax; directional glyphs mirror; close is turned by `QIcon` |
| `type_scale_test.dart`, `typography_test.dart` | every size on the scale; nothing tracked; every character drawn by a bundled face |
| `radii_test.dart` | only the kit's radii, none written as a number |
| `tap_target_test.dart` | every tappable at least 48 × 48, and a control with nothing to do says so |
| `ground_test.dart`, `depth_test.dart` | what covers the screen reaches its edges; no surface casts a shadow |
| `controls_test.dart` | switches, segments, disabled spends drawn as specified |
| `tab_bar_test.dart`, `log_sheet_test.dart` | the bar's layout, its tabs, the orb's three gestures and spring; the Log sheet's rows, under the bar, scrolling on a short phone |
| `today_layout_test.dart`, `composition_test.dart` | Today's zones and height budgets above the fold; the welcome's and the paywall's compositions at four phone sizes |

When a redesign changes what a test pins, **update the test to the new design's intent**. Never delete it, and never loosen a guard to get green. If you change a colour token, change `references/tokens.md` with it: `colors_test.dart` reads it.

## Rendering screens to look at them

`scripts/render_screens_test.dart` (in this skill) draws every screen in English and Arabic to PNGs:

```bash
cp .claude/skills/qamar-design/scripts/render_screens_test.dart app/test/zz_render_tmp_test.dart
cd app && flutter test test/zz_render_tmp_test.dart \
  --dart-define=OUT=$PWD/../renders --dart-define=SHOT=after --dart-define=ONLY=today
rm -f test/zz_render_tmp_test.dart
```

Look at every image you produced (for example with the Read tool) before calling a screen done, and compare `before` with `after` for a redesign. The harness file is never committed.

## Checks before a push (Qamar)

```bash
cd app
flutter analyze --no-fatal-infos      # no errors or warnings
flutter test                          # everything green
TZ=Africa/Cairo flutter test test/cairo_days_test.dart --dart-define=REQUIRE_CAIRO=true
```
