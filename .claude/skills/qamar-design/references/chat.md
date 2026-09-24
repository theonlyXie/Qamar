# The conversation: ChatGPT-style, in the kit's colours

People already know how ChatGPT works. We copy its structure, because familiarity is speed, and draw it in the Nutri AI kit's colours with Qamar's moon. Qamar's implementation is `app/lib/widgets/ask_qamar_overlay.dart`.

## Layout, top to bottom

```
┌──────────────────────────────────────────┐
│ (×)        (☾) Qamar                      │  header: a grey close circle at the start;
│           Ready when you are              │  the moon's face and the name, centred; one line
│                                           │
│      ░░ top fade: the transcript ░░       │
│                                           │
│                ┌───────────────────────┐  │  person: LAVENDER bubble, black words,
│                │ How much protein in   │  │  trailing, corner 24, 17/24
│                │ ful with an egg?      │  │
│                └───────────────────────┘  │
│  About 19 g. The ful is roughly 13 g and  │  Qamar: plain white text, full width,
│  the egg 6 g.                             │  17/26, no bubble, no avatar
│  ⧉  ↻                                     │  copy · retry
│                                           │
│  ( Log it )  ( Lighter version )          │  grey chips; the next step's words in accentInk
│ ┌───────────────────────────────────────┐ │
│ │ +   Ask Qamar anything             (●) │ │  composer: ONE grey capsule (surfaceRaised)
│ └───────────────────────────────────────┘ │  mic circle grey; send circle burgundy with text
└──────────────────────────────────────────┘
```

## Rules

**The ground.** The dark (`canvas`), and nothing on it behind the words. The transcript scrolls under the header and above the composer with a top fade; no dividers. It is drawn from the bottom up (a `reverse: true` list): a fresh line sits on the field, where the eye is.

**Burgundy in the conversation**, and nothing else:
- The send circle is burgundy only when there is something to send. The microphone beside an empty field, and stop, are the grey circle (`surfaceHigh`).
- A turn's suggested next step is a grey chip with `accentInk` words (600), not a burgundy fill.
- "Confirm and log" on a reading is the primary button.

**The header.**
- Close at the start, as a 44 grey circle.
- The moon mascot's face in a small lavender disc, and the product's name beside it, centred together.
- One status line under them, kept at its height when empty: "Listening…", "Thinking…", what was heard, the quota near the limit, or nothing.
- No menus, no model or plan names.

**The empty state.**
- The mascot on a lavender disc, and one large question under it: "What can I help with?" / "أساعدك في إيه؟" (24/700), centred.
- The suggestions above the composer, drawn from the person's real day ("What should I eat tonight?", "Log my breakfast"), as grey chips in one row that fades at its end.
- No feature list and no tutorial.

**The person's messages.** A lavender bubble on the trailing side, at most about 80% wide, corner 24, 17/24 black words (`onPastel`). A photo shows as a thumbnail above the words, corner 16.

**Qamar's messages.**
- Plain `ink` text at full width, 17/26, no bubble, avatar or name.
- Supporting lines (a breakdown, a source) at 15/22 in `inkSecondary`.
- Numbers tabular, following the digits setting.
- Under the latest reply: **copy** (`QIcons.copy`) and **retry** (`QIcons.repeat`), 48 targets with spoken labels.
- Action chips under a reply when an action is likely ("Log it"): grey; the next step's words `accentInk`.

**While waiting.** A 14-point lavender dot breathing on the 2.4 s cycle where the reply will appear, and the status line's specific words ("Reading your photo…"). Steady under reduce motion. The send becomes **stop**.

**The composer.**
- One grey capsule (`QSurface`, `surfaceRaised`, corner 24): 48 tall on one line, so exactly a capsule; more lines make it a rounded rectangle.
- **Start:** a plain **+** (a photo of a menu or a meal).
- **Middle:** the field, 17/22, up to 6 lines, placeholder "Ask Qamar anything" / "اسأل قمر أي حاجة" in `inkTertiary`.
- **End:** one 36-point circle:

  | State | Glyph | Circle | Tap does |
  |---|---|---|---|
  | Text in field | send `↑` | burgundy, white glyph | send |
  | Empty field | mic | grey | start listening |
  | Listening | stop ■ | grey | stop listening |
  | Reply generating | stop ■ | grey | stop the reply |

- The change is a short cross-fade and scale, fill and glyph together; the circle never jumps.
- The onboarding composer is the same capsule; its send is burgundy only while there is text.

**Voice.** Holding the orb starts listening at once: the fastest path. The mic in the composer does the same. The words fill the field live.

**Acting on the person's behalf.**
- When Qamar reads a meal from what was said, it offers the kit's scan result in the transcript: the four macro tiles (calories lavender, protein mint, carbs lime, fat coral) and the items, each with − / + steppers on raised grey circles; "Confirm and log" as the primary and "Cancel" as a quiet text button.
- Nothing is written until the person confirms. Then the card becomes a one-line receipt with **Undo**.

**Honesty.**
- **Disclosure:** one quiet line under the composer ("Qamar can make mistakes. Check anything medical with a doctor.").
- **Health:** never assert medical facts beyond nutrition. Allergies and conditions always win over a suggestion.
- **Limits and errors:** a state line in the transcript, in plain words, with one way on in `accentInk` ("You've used today's 3 questions. Qamar+ has no limit." and "See Qamar+"). No modal wall.
- **Offline:** the composer stays usable; messages queue, and a state line says so.

**Motion.** A new message fades and rises a few points on the settle spring; nothing else moves on send. Auto-scroll only when the person is already at the newest line.

**Accessibility.** Each message is one semantics node ("You: …" / "Qamar: …"); a reply is announced once, when it completes; the send/mic/stop label changes with its glyph.
