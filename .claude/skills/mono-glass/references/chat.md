# The conversation: ChatGPT-style

People already know how ChatGPT works. We copy its structure exactly, because familiarity is speed. We then make it ours with black and white, glass controls and the moon. Qamar's implementation is `app/lib/widgets/ask_qamar_overlay.dart`.

## Layout, top to bottom

```
┌──────────────────────────────────────────┐
│ (×)            Qamar                      │  header: glass close on the leading edge,
│           Ready when you are              │  centred name 17/600, one status line 12/18
│                                           │
│      ░░ top fade: the transcript ░░       │
│                                           │
│                ┌───────────────────────┐  │  person: surfaceHigh bubble, radius 24,
│                │ How much protein in   │  │  trailing, max 80% width, 17/24
│                │ ful with an egg?      │  │
│                └───────────────────────┘  │
│  About 19 g. The ful is roughly 13 g and  │  assistant: plain text, full width,
│  the egg 6 g.                             │  17/26, no bubble, no avatar
│  ⧉  ↻                                     │  copy · retry (20 pt, inkTertiary)
│                                           │
│  ( Log it )  ( Lighter version )          │  suggestion chips (optional)
│ ┌───────────────────────────────────────┐ │
│ │ +   Ask Qamar anything             (↑) │ │  composer: ONE glass panel, radius 26
│ └───────────────────────────────────────┘ │
└──────────────────────────────────────────┘
```

## Rules

**The ground.**
- A solid black page, no glass behind the transcript, and a spring fade-and-rise when the chat opens.
- The transcript scrolls under the header and above the composer with a top edge fade. There are no dividers.

**The header.**
- Close on the leading side, as a 44 glass circle.
- The product's name in the centre.
- One status line: "Ready when you are", "Listening…", "Thinking…" or "Offline".
- Nothing on the trailing side except, optionally, one glass icon for a new chat.
- No menus, and no model or plan names.

**The empty state.**
- One large question, centred: "What can I help with?" / "أساعدك في إيه؟", at 28/34, weight 600.
- Under it, three or four suggestion chips drawn from the person's real day ("What should I eat tonight?", "Log my breakfast", "Is koshari okay today?").
- No feature list and no tutorial.

**The person's messages.**
- A `surfaceHigh` bubble on the trailing side, at most about 80% wide, radius 24 (the card corner, so one line reads as a capsule), 17/24 `ink`.
- Attachments (photos) show as a thumbnail above the text, radius 16.

**The assistant's messages.**
- Plain `ink` text at full width, 17/26, with no bubble, avatar or name.
- Supporting lines (a breakdown, a source) use 15/22 `inkSecondary`.
- Numbers are tabular and follow the digits setting.
- Under the last reply, small actions (20 pt glyphs, 48 targets): **copy** (`QIcons.copy`) and **retry** (`QIcons.repeat`), with spoken labels.
- Optional action chips go under a reply when an action is likely ("Log it"). The likely one is white, the rest outline.

**While waiting.**
- A 14 pt white dot breathing on the 2.4 s cycle, where the reply will appear.
- The status line gives specific words ("Reading your photo…", "Working out your protein…").
- Under reduce motion, the dot is steady.
- Any wait can be stopped: the send button becomes **stop**.

**The composer.**
- One glass rounded panel, radius 26, 20 from the sides, sitting above the keyboard.
- **Leading:** a plain **+** glyph (attach). It offers "Take a photo" and "Choose a photo" in a small glass menu that grows from the +.
- **Middle:** a multiline field, 17/22, up to 6 lines, placeholder "Ask Qamar anything" / "اسأل قمر أي حاجة" in `inkTertiary`.
- **Trailing:** a 36 white circle with a black glyph. It changes with state:

  | State | Glyph | Tap does |
  |---|---|---|
  | Text in field | send `↑` | send |
  | Empty field | mic | start listening |
  | Listening | stop ■ | stop listening |
  | Reply generating | stop ■ | stop the reply |

- The glyph change is a 150 ms cross-fade and scale (0.8 → 1). The circle never jumps.
- Return inserts a newline on mobile. Send is the button.

**Voice.** Holding the orb starts listening directly; that's the fastest path. Tapping the mic in the composer does the same. The transcript fills the field live, and the person sends it or lets it auto-send on a pause.

**Acting on the person's behalf.**
- When the assistant would change something (log a meal, set a goal), it shows a **proposal card** in the transcript:
  - a `surface` card with a `hairlineStrong` edge;
  - the items, with − / + steppers;
  - the totals;
  - one primary "Confirm and log", and "Cancel" as a text button.
- Nothing is written until the person confirms.
- After confirming, the card collapses to a one-line receipt ("Logged · 540 kcal") with **Undo**.

**Honesty.**
- **Disclosure:** show one quiet line under the empty state the first time ("Qamar can make mistakes. Check anything medical with your doctor."), and keep it reachable from the header.
- **Health:** never assert medical facts beyond nutrition. Allergies and conditions always win over a suggestion.
- **Limits and errors:** a state line in the transcript, in plain words, with one action ("You've used today's 3 questions. Qamar+ has no limit." plus "See Qamar+"). Don't use a modal wall.
- **Offline:** the composer stays usable. Messages queue, and a state line says so.

**Motion.**
- A new message fades and rises about 8 pt with the settle spring. Nothing else animates on send, because chat is high-frequency.
- Auto-scroll to the newest message only if the person is already at the bottom. Otherwise show a small glass "↓" circle above the composer.

**Accessibility.**
- Each message is one semantics node ("You: …" / "Qamar: …").
- A reply is announced once, when it completes.
- The send/mic/stop button's label changes with its glyph.
