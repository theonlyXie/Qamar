# Sources and reasoning

Why the rules are what they are, so you can defend or adapt them.

## The Nutri AI kit

"Nutri AI – Food Calorie Tracker App (Community)", a Figma community kit, is where the look comes from. What we took, and what it gave:
- **A dark, flat ground** with greys a step apart (its grey 600 to 200: `canvas`, `surface`, `surfaceRaised`, `surfaceHigh`, `inkSecondary`). No glass, no shadow: a surface says what it is by its grey and its shape.
- **Four pastels** (lavender `#DDC0FF`, lime `#F5F378`, mint `#45C588`, coral `#FF6F43`) as whole-card grounds with black words: its calorie card, its macro cards, its onboarding pages. That is what brings the app to life without making it busy: the colour is where the figures are.
- **Space Grotesk** on its type scale (titles 20–34 at one and a half, text 12–18), set as drawn.
- **Iconsax**, linear at rest and bold for the active tab.
- **Components:** the calorie gauge over a pastel, the macro tiles, the floating tab bar with a round middle button, the white segmented control, the grouped settings list without lines, the round black onboarding button in its white bump, the scan result with steppers, the cartoon characters for empty and welcome states.

**Where we depart, and why:**
- **Burgundy for the kit's orange.** Qamar's own colour stays the one thing to do and what is chosen.
- **The moon for the kit's fruit characters** (`MoonMascot`), in the kit's heavy black line, lit on the right as the app's moons are: the brand's mark is the moon.
- **The orb in the tab bar's middle**, where the kit has a plus: the living moon keeps its three gestures (tap the Log sheet, hold to talk, drag to explain), and the Log sheet replaces the radial tree the orb used to bloom.
- **Noto Sans Arabic** beside Space Grotesk: the kit has no Arabic, and Qamar is Arabic-first.
- **The error red is an edge, never words**: the kit's red fails AA as text on its greys.

## Apple Human Interface Guidelines

Still the reference for behaviour, where the kit is silent:
- **Motion** (WWDC18 "Designing Fluid Interfaces", WWDC23 "Animate with springs"): critically damped springs by default, a little bounce only after a flick, everything interruptible, velocity handed from the finger to the spring, Reduce Motion as fades.
- **Targets:** 44 × 44 pt minimum; we use 48 for Android.
- **Buttons:** at most one prominent button per view; never a destructive primary.
- **Onboarding** "fast, fun, and optional"; sign-in delayed as long as possible.
- **Feedback:** "show something as soon as possible"; errors blame-free, near the problem, without "oops" or "we".
- **Generative AI:** disclose AI use and its limits; curated starter prompts; specific progress text; copy and retry near the output; confirm before acting on the person's behalf; a higher bar for health.
- **Colour and contrast:** 4.5:1 for text, 3:1 for large text and marks; never colour alone.
- **Principles** (June 2026): Purpose, Agency, Responsibility, Familiarity, Flexibility, Simplicity ("isn't minimalism"), Craft, Delight ("don't mistake delight for decoration").

## The owner's direction

In order:
1. "…black and white as our colors only, liquid glass, icons… make sure of the animation… chat should look like ChatGPT with simple icons… keep the orb, remove out of scope colors and make it simple to use no extra steps, no more tech complication, the faster the simpler always the better."
2. "add Burgundy to the colors because black and white alone doesn't feel good, use Liquid Glass and drop the nothing branding."
3. "I feel that our app is out of life… this design is much better than ours, keep the core app features while redesigning the app to this" (the Nutri AI kit), with "Do not forget our branding".
4. "rethink the orb tree, if you can make it in a better way less noise, it would be better."

The six laws in `SKILL.md` are these, made operational: the kit's look (3) with Qamar's brand kept (the moon, burgundy, the name); the orb kept and its tree rethought as the Log sheet under a calm tab bar (4); the ChatGPT-like chat, simple icons, spring motion and "the faster the simpler" unchanged from (1) and (2). Liquid Glass gave way to the kit's flat surfaces in (3).
