# Sources and reasoning

This file explains why the rules are what they are, so you can defend or adapt them. The full research notes were distilled from Apple's HIG (as of September 2026) and from Nothing's official developer kits and design press. They lived in the session scratchpad and aren't in the repo; this is their distilled evidence.

## Apple Human Interface Guidelines

**Liquid Glass** ([materials], WWDC25 "Meet Liquid Glass" and "Get to know the new design system")
- It is "a distinct functional layer for controls and navigation elements… that floats above the content layer." "Don't use Liquid Glass in the content layer."
- "Use Liquid Glass effects sparingly." "Always avoid glass on glass."
- Regular glass is the default. Clear glass is only "for components that float above media backgrounds", with "a dark dimming layer of 35% opacity" if the content is bright.
- "By default, Liquid Glass has no inherent color." Tint only primary actions, and tint the background, not the label.
- It "materializes" by modulating lensing, not by fading.
- Scroll edge effects replace dividers under floating controls. "Scroll edge effects aren't decorative."
- Accessibility: Reduced Transparency makes it frostier, Increased Contrast makes it black or white with a border, and Reduced Motion disables its elastic properties. Custom glass must copy all three by hand.

**Colour** ([color], [dark-mode], [accessibility])
- A monochrome brand accent is endorsed "in apps with primarily monochromatic content".
- Contrast: 4.5:1 for text up to 17 pt, 3:1 for larger or bold text.
- "Never rely on color alone."

**Type** ([typography])
- The default Dynamic Type sizes at Large: 34/41, 28/34, 22/28, 20/25, 17/22 (body and headline), 16/21, 15/20, 13/18, 12/16, 11/13.
- Avoid ultralight, thin and light weights.
- Minimise typefaces.
- Tracking is size-specific; there is no tracking for SF Arabic.
- Support at least 200% text.

**Icons** ([icons], [sf-symbols])
- One family, at a consistent weight and detail level.
- Outline in lists and toolbars; fill for selection.
- Label every icon, and use a word when the glyph is ambiguous.
- SF Symbols' licence restricts it to Apple platforms. That's why we use Cupertino Icons (MIT), which follows the same metaphors.

**Motion** ([motion], SwiftUI and UIKit docs, WWDC23 "Animate with springs", WWDC18 "Designing Fluid Interfaces")
- The default spring is critically damped (bounce 0). Use about 0.15 bounce only for playful moments or the end of a gesture, and never more than 0.4.
- "Make motion optional." Don't animate frequent interactions. Let people cancel motion.
- Reduce Motion: fades instead of slides, and no animated blur or depth.

**Components and flows** ([buttons], [sheets], [onboarding], [managing-accounts], [loading], [feedback], [writing])
- Hit regions are at least 44 × 44 pt; we use 48 for Android.
- Use at most one or two prominent buttons per view, and never give the primary role to a destructive action.
- Onboarding is "fast, fun, and optional". Postpone setup, and "delay sign-in for as long as possible".
- "Show something as soon as possible"; avoid "loading" wording.
- Errors are blame-free, sit near the problem, and avoid "oops" and "we".

**Generative AI** ([generative-ai], [machine-learning])
- Disclose AI use and its limits.
- Offer curated starter prompts.
- Show specific progress text.
- Offer Copy, Retry and Edit near the output.
- Confirm before acting on the person's behalf.
- Avoid AI content where a hallucination could harm; the bar is higher for health.

**Design principles** (June 2026): Purpose, Agency, Responsibility, Familiarity, Flexibility, Simplicity ("isn't minimalism"), Craft, and Delight ("don't mistake delight for decoration").

## Nothing

Evidence comes from the Glyph Matrix and Glyph developer kits (spec art measured), support pages, and press coverage of Nothing OS 1–4. The Figma community file "Nothing UI" by Zognest is a third-party concept from before Nothing OS existed, not Nothing's system, and it couldn't be opened from our environment.

**Palette:**
- The official matrix preview uses background `#000`, lit `#FFF` and unlit `#1C1C1C`.
- Measured pixel share: about 75% near-black, 20% grey, 5% white.
- Hierarchy comes from grey and size only.

**Dot type:** NDot is for clocks, widgets and hero numbers. Nothing **removed dot type from reading text in OS 3.0 "for improved readability"**, which is why ours is for hero numerals only.

**Fonts:**
- Nothing's own faces are proprietary, and none covers Arabic.
- Every popular "Nothing-look" open face (Doto, Space Mono, Space Grotesk, Geist Mono and others) has zero Arabic letters and digits.
- So we hand-drew our 5×7 dot digits, including Arabic-Indic, and use Inter plus Noto Sans Arabic for text. Noto Sans Arabic has true tabular ٠–٩.

**Light as status:** steady means on, a slow breath (Nothing's SDK sample is 3 s) means active, and a pulse-then-drain means a timer. Progress is quantised into dots or segments and paired with a number.

**Motion:** "light, not travel": short, decelerating, no bounce. Dots move in waves and breaths.

**What we didn't borrow:**
- the red accent and every status hue;
- proprietary fonts;
- dot type for reading or for Arabic words;
- tracking or uppercasing Arabic;
- low-contrast decorative greys for text;
- hardware light features;
- "[BRACKET]" text, which mirrors in RTL;
- the "no blur ever" dogma, because glass is our floating layer.

## Our own rule

The user's direction for our products: "black and white as our colors only, liquid glass, icons… make sure of the animation… chat should look like ChatGPT with simple icons… keep the orb, remove out of scope colors and make it simple to use, no extra steps, no more tech complication, the faster the simpler always the better." Laws 1, 2, 3, 4 and 5 in `SKILL.md` are that sentence, made operational.
