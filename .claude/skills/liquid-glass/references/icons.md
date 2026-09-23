# Icons

## The family

- **Cupertino Icons** (the `cupertino_icons` package, MIT) is drawn after SF Symbols and ships with Flutter.
- We can't ship SF Symbols itself: its licence covers Apple platforms, and we ship on Android too.
- Phosphor and Lucide are good, but they would add a second visual language next to the SF-like system controls on iOS.

**Rules**
- **Screens name glyphs by meaning** (`QIcons.send`), defined once in `app/lib/theme/icons.dart`. A call site never writes `CupertinoIcons.x` or `Icons.x`. `icons_test.dart` fails the build on any `Icons.` (Material) glyph in `lib/`.
- **Outline at rest, filled only for selected or "on"** (`water` → `waterFull`, `moon` → `moonFull`). Never fill for emphasis alone.
- **Sizes:** 20 in rows and inline, 22–24 in controls, 28 for a hero glyph in a state card. The size matches the neighbouring text's optical weight.
- **Colour:** the ink of the adjacent text (`accentInk` beside a way on), and `onAccent` on burgundy. Never a colour of its own.
- **Labels:** every icon-only control has a spoken label. If people might misread the glyph, show a visible word too; a word is always better than a clever glyph.
- **One glyph, one meaning.** Don't reuse a glyph for two different actions on one screen, and don't use two glyphs for one action across screens.

## Meaning → glyph (Qamar)

| Meaning | `QIcons.` | Cupertino glyph | Mirrors in RTL |
|---|---|---|---|
| Back / forward | `back` / `forward` | `chevron_back` / `chevron_forward` | yes |
| Close | `close` | `xmark` | no |
| Expand | `down` | `chevron_down` | no |
| More (overflow only) | `more` | `ellipsis` | no |
| Opens elsewhere | `external` | `arrow_up_right` | no |
| Send | `send` | `arrow_up` | no (points up) |
| Mic / mic off / voice | `mic` / `micOff` / `voice` | `mic` / `mic_slash` / `waveform` | no |
| Stop | `stop` | `stop_fill` | no |
| Attach / add | `attach` / `add` | `plus` | no |
| Camera / photo | `camera` / `photo` | `camera` / `photo` | no |
| Copy | `copy` | `doc_on_doc` | no |
| Remove | `remove` | `minus` | no |
| Check / done | `check` / `done` | `checkmark` / `checkmark_circle_fill` | no |
| Edit | `edit` | `pencil` | no |
| Repeat / retry | `repeat` | `arrow_counterclockwise` | no |
| Share | `share` | `square_arrow_up` | no |
| Swap | `swap` | `arrow_2_circlepath` | no |
| Scan | `scan` | `viewfinder` | no |
| Log a meal | `log` | `square_pencil` | no |
| Plan | `plan` | `square_list` | no |
| Water (empty / full) | `water` / `waterFull` | `drop` / `drop_fill` | no |
| Review | `review` | `chart_bar` | no |
| Me | `me` | `person` | no |
| Moon | `moon` / `moonFull` | `moon` / `moon_fill` | no |
| Streak / energy | `flame` | `flame` | no |
| Shop | `shop` | `cart` | no |
| Walk / run / football / gym / other | `walk` / `run` / `football` / `gym` / `other` | `person` / `hare` / `sportscourt` / `bolt` / `ellipsis_circle` | no |
| Info / warning / error | `info` / `warning` / `error` | `info_circle` / `exclamationmark_circle` / `exclamationmark_triangle` | no |
| Offline / locked / limit | `offline` / `locked` / `limit` | `wifi_slash` / `lock` / `hourglass` | no |
| Empty | `empty` | `moon_stars` | no |
| Good / gift / Qamar+ | `good` / `gift` / `plus` | `checkmark_circle` / `gift` / `sparkles` | no |
| Safety / time / gesture / trend | `safety` / `time` / `gesture` / `trend` | `heart` / `clock` / `hand_draw` / `graph_square` | no |

To add a glyph:
1. Find the SF Symbol Apple uses for that meaning, in the HIG's standard icons table.
2. Pick the Cupertino glyph that draws it.
3. Add it to `QIcons` under a meaning name.
4. Give it `matchTextDirection: true` only if it points along the reading direction.

## RTL mirroring

- **Mirror** anything that points along the reading direction: back and forward chevrons, "next" arrows, reply, list indent, and a progress arrow.
- **Don't mirror:**
  - clocks and circular arrows (repeat, refresh);
  - checkmarks;
  - media playback;
  - send-as-up-arrow;
  - real objects (camera, cart, drop, moon);
  - logos;
  - anything with text or digits.
