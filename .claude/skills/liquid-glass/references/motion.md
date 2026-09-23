# Motion

Motion in liquid-glass does three jobs:
- it says **where things come from and go**;
- it gives **instant feedback** under the finger;
- it shows **that something is alive or waiting**, with a slow breath.

It never decorates. Apple's model is physics: springs that start from where a thing is and carry the finger's speed.

## Tokens (Qamar: `app/lib/theme/motion.dart`)

| Use | Token or value |
|---|---|
| Anything that moves or arrives | `QSpring.settle`: damping 1.0, response 0.35 s |
| Only after a flick (release > `QSpring.flickSpeed`, 700 pt/s) | `QSpring.flick`: damping 0.8 |
| Driving a controller | `QSpring.drive(controller, to, still: reduceMotion, velocity: v)` |
| Where a flick lands | `QSpring.project(velocity)`, then snap to the nearest stop |
| Press | scale 0.97, 100–120 ms (`qPressed`), on touch-down |
| State change | 200–250 ms, ease-out cubic |
| Arrive (fixed duration) | `QMotion.fadeIn` 240 / `riseIn` 340 / `growIn` 280 ms, ease-out |
| Leave | about 200 ms, along the arrival path, faster than arrival |
| Active breath | 2.4 s sine, opacity 1.0 ↔ 0.5 |
| Idle breath (the orb) | `QMotion.breath` 4.6 s |

## Recipes

**Press (every control):** let `QTapArea` give you `pressed`, and wrap the visual in `qPressed(context, pressed: pressed, child: …)`. Under reduce motion that becomes opacity 0.7, with no scale.

**Arrive:** `QSpringIn(arrive: QArrive.rise, child: …)`.
- `fade` is for text swaps, `rise` for cards and messages, `grow` for things that come out of a control.
- It animates from opacity 0 and offset 8 pt (rise) or scale 0.96 (grow), on the settle spring.

**Swap content in place:** use `AnimatedSwitcher` with 200 ms, a fade, and scale 0.96 → 1 for glyphs. Key the child by its state, and never animate layout size and content at once.

**Sheets:** `QSheetSlot` / `QSheetScrim`.
- A sheet rises from the bottom on the settle spring, and the scrim fades in 200 ms.
- Dragging tracks the finger 1:1. On release, project the velocity: past the midpoint, or on a downward flick, it dismisses.
- It leaves the way it came.

**Breath (waiting, listening):**

```dart
final t = controller.value; // repeating 0→1 over 2.4 s
final alpha = 0.75 + 0.25 * math.cos(2 * math.pi * t); // 1.0 ↔ 0.5
```

Under reduce motion: stop the controller and hold at 1.0.

**Attention (once, never looping):** two dips to 30% brightness, 150 ms each, then words. Never flash more than three times a second.

## Rules

1. **Feedback starts on touch-down.** Don't wait for the tap to finish to show the press.
2. **Interruptible always.** A spring re-targets from the current value and velocity. Never lock input during a transition, and never make someone wait for an animation to finish before acting.
3. **Same path in and out.** Something that rose from the bottom sinks to the bottom. Something that grew from a button shrinks back into it.
4. **No bounce on things that simply appear.** Bounce (damping 0.8) is only for something the finger threw.
5. **Frequent means quiet.** Sending a message, ticking water or toggling a switch gets a press and a fade, no more.
6. **One moving thing at a time.** Two simultaneous large motions read as chaos. Stagger them or choose one.
7. **The orb is alive, but gently.** Its idle breath and float are slow (4.6 s, 9–11 s) and small in amplitude. Listening speeds the breath to 2.4 s. Under reduce motion, the orb is still.
8. **A control never drifts.** Nothing a finger has to hit moves on its own: no bobbing buttons, no floating chips. On the tree, nothing on the ring moves on its own; the circles hold still. A moving target is harder to hit, and an automated tap (a test, an accessibility tool) waits for it to stop.

## Reduce Motion (`MediaQuery.disableAnimationsOf(context)`)

- Every translate, scale or rotate becomes a fade of 150 ms or less.
- Every loop stops: no breathing, orbiting, float, parallax or blur animation. That includes the slow ones, the orb's breathing and the moon's phase drift: stop the controller in `didChangeDependencies` and draw the rest pose, so the screen settles and schedules no frames.
- Springs become `QSpring.drive(…, still: true)`, a plain 150 ms tween that the caller draws as a fade.
- Meaning must survive: if motion said "listening", the words must say it too.
