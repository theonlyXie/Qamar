# Motion

Motion in qamar-design does three jobs:
- it says **where things come from and go**;
- it gives **instant feedback** under the finger;
- it shows **that something is alive or waiting**, with a slow breath.

It never decorates. The model is physics: springs that start from where a thing is and carry the finger's speed. The kit is flat and calm, and so is its motion: nothing orbits, sparkles or drifts.

## Tokens (Qamar: `app/lib/theme/motion.dart`)

| Use | Token or value |
|---|---|
| Anything that moves or arrives | `QSpring.settle`: damping 1.0, response 0.35 s |
| Only after a flick (release > `QSpring.flickSpeed`, 700 pt/s) | `QSpring.flick`: damping 0.8 |
| Driving a controller | `QSpring.drive(controller, to, still: reduceMotion, velocity: v)` |
| Where a flick lands | `QSpring.project(velocity)` |
| Press | scale 0.97, 120 ms (`qPressed`), on touch-down |
| State change (a segment, a tab's circle) | 180–220 ms, ease-out |
| Arrive (fixed duration) | `QMotion.fadeIn` 240 / `riseIn` 340 / `growIn` 280 ms, ease-out |
| Leave | along the arrival path, a little faster |
| Active breath (waiting, listening) | 2.4 s (`QMotion.ring`), opacity 1.0 ↔ 0.5 |
| The orb's idle breath and halo | `QMotion.breath` 4.6 s, `QMotion.halo` 5.2 s |

## Recipes

**Press (every control):** `QTapArea` gives you `pressed`; wrap the visual in `qPressed(context, pressed: pressed, child: …)`. Under reduce motion that becomes opacity 0.7, with no scale.

**Arrive:** `QSpringIn(arrive: QArrive.rise, child: …)`: `fade` for text swaps, `rise` for cards and messages, `grow` for something coming out of a control (the welcome's mascot).

**Swap content in place:** `AnimatedSwitcher`, 180–200 ms, a fade. Key the child by its state; never animate layout size and content at once.

**Sheets:** `QSheetSlot` / `QSheetScrim`.
- A sheet rises from below its own height on the settle spring; the scrim fades in with it.
- A drag tracks the finger 1:1; on release, the velocity is projected: past the midpoint, or a downward flick, and it goes.
- It leaves the way it came. The Log sheet rises under the tab bar, from the orb that opened it.

**The orb (`QTabBar`):**
- At rest it breathes in its circle in the middle of the bar. Nothing orbits it, it doesn't wander, and no sparks come off it.
- A drag takes it out of the bar under the finger (1:1, from where it was grabbed); let go, it springs back into its circle from where it was left, carrying the finger's speed on two springs, one per axis. Grabbed mid-spring, it is taken from where it is on screen, so it never jumps.
- Under reduce motion there is no spring: it is home on the next frame and fades in.

**Breath (waiting, listening):**

```dart
final t = controller.value; // repeating 0→1 over 2.4 s
final alpha = 0.75 + 0.25 * math.cos(2 * math.pi * t); // 1.0 ↔ 0.5
```

Under reduce motion: stop the controller and hold at 1.0.

**The receipt (a credit):** the coin and "+100" rise the last 5 points into place above the bar's middle with an ease-out, hold, and fade with an ease-in, two seconds in all. No bounce, no haptic.

## Rules

1. **Feedback starts on touch-down.**
2. **Interruptible always.** A spring re-targets from the current value and velocity; never lock input during a transition.
3. **Same path in and out.** What rose from the bottom sinks to the bottom; what grew from a button shrinks back into it.
4. **No bounce on things that simply appear.** Bounce (damping 0.8) is only for something the finger threw.
5. **Frequent means quiet.** Sending a message, adding a glass of water or toggling a switch gets a press and a fade, no more.
6. **One moving thing at a time.**
7. **Nothing a finger must hit moves on its own:** no bobbing buttons, no floating chips, no drifting tiles; the tab bar and its orb hold their place. A moving target is harder to hit, and a test or an accessibility tool waits for it to stop.

## Reduce Motion (`MediaQuery.disableAnimationsOf(context)`)

- Every translate, scale or rotate becomes a fade of 150 ms or less.
- Every loop stops: the orb's breath and halo, the breathing dot, the moon's phase drift. Stop the controller in `didChangeDependencies` and draw the rest pose, so the screen settles and schedules no frames (a widget test's `pumpAndSettle` returns).
- Springs become `QSpring.drive(…, still: true)`, a plain 150 ms tween drawn as a fade.
- Meaning must survive: if motion said "listening", the words say it too.
