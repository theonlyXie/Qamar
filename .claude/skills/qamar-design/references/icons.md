# Icons

## The family

- **Iconsax** (the `iconsax_plus` package, MIT), the Nutri AI kit's own family (vuesax). Its linear and bold weights are bundled with the package; the broken weight is not used.
- **Linear at rest, bold for chosen or on**: the tab the person is on, a done mark, a full drop of water. Never bold for emphasis alone.
- The one exception: other people's marks on the sign-in buttons (Apple's and Facebook's, from Material; Google's "G", drawn by `GoogleMark` in its own colours). They are named once in `QIcons` and nowhere else.

**Rules**
- **Screens name glyphs by meaning** (`QIcons.send`), defined once in `app/lib/theme/icons.dart`, and **draw them through `QIcon`** (`QIcon(QIcons.send, size: 20, color: …)`), never a bare `Icon`. `icons_test.dart` fails on any `Icons.`, `IconsaxPlus*.` or `CupertinoIcons.` glyph, or a bare `Icon(`, outside the theme.
- **Close is the add, turned.** Iconsax draws no plain ×, so `QIcons.close` is the family's add glyph as a constant of its own, and `QIcon` turns it an eighth and scales it a fifth larger. Drawn any other way it would be a plus.
- **Sizes:** 20 in rows and inline, 22–24 in controls, 24 in the tab bar, 18–20 in a pastel glyph circle (`PastelGlyph`, half its circle).
- **Colour:** the ink of the words beside it; `onPastel` on a pastel; `onAccent` on burgundy; `accentInk` beside a way on. Never a colour of its own.
- **Labels:** every icon-only control has a spoken label. If a glyph could be misread, show a word too; a word is always better than a clever glyph.
- **One glyph, one meaning.** Don't use one glyph for two actions on a screen, or two glyphs for one action across screens.

## Meaning → glyph (Qamar)

| Meaning | `QIcons.` | Iconsax glyph (linear unless noted) | Mirrors in RTL |
|---|---|---|---|
| Back / forward | `back` / `forward` | `arrow_left_1` / `arrow_right_3` | yes |
| Close | `close` | `add`, turned by `QIcon` | — (a cross) |
| Expand / up | `down` / `up` | `arrow_down` / `arrow_up_1` | no |
| More / opens elsewhere | `more` / `external` | `more` / `export_3` | no |
| Send | `send` | `arrow_up` | no (points up) |
| Mic / mic off / voice / stop | `mic` / `micOff` / `voice` / `stop` | `microphone_2` / `microphone_slash_1` / `voice_cricle` / bold `stop` | no |
| Attach / camera / photo / keyboard | `attach` / `camera` / `photo` / `keyboard` | `add` / `camera` / `gallery` / `keyboard` | no |
| Copy / ask | `copy` / `ask` | `copy` / `magic_star` | no |
| Add / remove | `add` / `remove` | `add` / `minus` | no |
| Check / done | `check` / `done` | `tick_circle` / bold `tick_circle` | no |
| Edit / repeat / share / swap / scan | `edit` / `repeat` / `share` / `swap` / `scan` | `edit_2` / `repeat` / `export` / `refresh_2` / `scan` | no |
| The tabs: Today / Progress / Plan / Me | `today` / `review` / `plan` / `me` | `home` / `activity` / `reserve` / `profile`, bold when chosen (`QIcons.onFor`) | no |
| Log | `log` | `note_2` | no |
| Water (empty / full), glass, bottle, tea | `water` / `waterFull`, `glass`, `bottle`, `tea` | `drop` / bold `drop`, `drop`, `milk`, `coffee` | no |
| Moon (Ramadan) | `moon` / `moonFull` | `moon` / bold `moon` | no |
| Calories / protein / carbs / fat | `calories` / `protein` / `carbs` / `fat` | `flash` / `record_circle` / `cake` / `drop` | no |
| Walk / run / football / gym / other | `walk` / `run` / `football` / `gym` / `other` | `routing` / `flash` / `cup` / `weight_1` / `more_circle` | no |
| Info / warning / error | `info` / `warning` / `error` | `info_circle` / `warning_2` / `danger` | no |
| Offline / locked / unlocked / limit | `offline` / `locked` / `unlocked` / `limit` | `cloud_cross` / `lock` / `unlock` / `timer_1` | no |
| Empty / good / gift / Qamar+ | `empty` / `good` / `gift` / `plus` | `moon` / `tick_circle` / `gift` / `crown` | no |
| Safety / time / gesture / trend / idea / shield | `safety` / `time` / `gesture` / `trend` / `idea` / `shield` | `heart` / `clock` / `finger_cricle` / `trend_up` / `lamp_on` / `shield_tick` | no |
| One of several: chosen / not | `chosen` / `unchosen` | bold `record_circle` / `record` | no |
| Settings, bell, language, trash, friends, account | `settings`, `bell`, `language`, `trash`, `friends`, `account` | `setting_2`, `notification`, `language_square`, `trash`, `profile_2user`, `profile_circle` | no |
| Sign out | `signOut` | `logout` | yes |

To add a glyph:
1. Pick the Iconsax glyph the kit uses for that meaning (the kit's screens name them), or the nearest one in the family.
2. Add it to `QIcons` under a meaning name, linear; add its bold form to `QIcons.onFor` only if it has a chosen state.
3. Give it `matchTextDirection: true` only if it points along the reading direction (write it as an `IconData(codePoint, fontFamily: _linear, fontPackage: _pkg, matchTextDirection: true)` constant, as `back` is).

## RTL mirroring

- **Mirror** anything that points along the reading direction: back and forward chevrons, sign out, a "next" arrow.
- **Don't mirror:** clocks and circular arrows (repeat, refresh), ticks, send-as-up-arrow, real objects (camera, cart, drop, moon), logos, anything with text or digits. The close mark is a cross, the same either way.
