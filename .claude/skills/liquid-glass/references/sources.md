# Sources and reasoning

This file explains why the rules are what they are, so you can defend or adapt them. The research notes were distilled from Apple's Human Interface Guidelines (as of September 2026). They lived in the session scratchpad and aren't in the repo; this is their distilled evidence, plus the owner's own direction.

## Apple Human Interface Guidelines

**Liquid Glass** ([materials], WWDC25 "Meet Liquid Glass" and "Get to know the new design system")
- It is "a distinct functional layer for controls and navigation elements… that floats above the content layer." "Don't use Liquid Glass in the content layer."
- "Use Liquid Glass effects sparingly." "Always avoid glass on glass."
- Regular glass is the default. Clear glass is only "for components that float above media backgrounds", with "a dark dimming layer of 35% opacity" if the content is bright.
- "By default, Liquid Glass has no inherent color." Tint only primary actions, and tint the background, not the label.
- It "materializes" by modulating lensing, not by fading.
- Scroll edge effects replace dividers under floating controls. "Scroll edge effects aren't decorative."
- Accessibility: Reduced Transparency makes it frostier, Increased Contrast makes it black or white with a border, and Reduced Motion disables its elastic properties. Custom glass must copy all three by hand.

**Where we depart, and why.** Apple keeps glass out of the content layer; we make cards and sheets glass panels, because the owner asked for glass as the material. We keep what Apple's caution protects:
- cards don't blur, so they cost no frames and their words never depend on what scrolls behind them;
- glass never stacks, except as an inset;
- tint stays on the primary action, as Apple asks, and on what is chosen.

**Colour** ([color], [dark-mode], [accessibility])
- One tint colour for what's interactive is the platform's own model: controls take the app's accent colour. Burgundy is ours.
- Don't use one colour for two meanings. That's why burgundy means "act" or "chosen" and never status.
- Contrast: 4.5:1 for text up to 17 pt, 3:1 for larger or bold text.
- "Never rely on color alone."

**Type** ([typography])
- The default Dynamic Type sizes at Large: 34/41, 28/34, 22/28, 20/25, 17/22 (body and headline), 16/21, 15/20, 13/18, 12/16, 11/13.
- Avoid ultralight, thin and light weights.
- Minimise typefaces.
- Tracking is size-specific; there is no tracking for SF Arabic.
- Support at least 200% text.
- SF's licence covers Apple platforms only, and we ship on Android too. So Latin is Inter, the open face closest to SF, and Arabic is Noto Sans Arabic, which has true tabular Arabic-Indic digits. The hero numeral uses the same faces, so it reads the same in both languages.

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

## Our own rule

The owner's first direction for our products: "black and white as our colors only, liquid glass, icons… make sure of the animation… chat should look like ChatGPT with simple icons… keep the orb, remove out of scope colors and make it simple to use, no extra steps, no more tech complication, the faster the simpler always the better."

The second changed the palette and the material: "add Burgundy to the colors because black and white alone doesn't feel good, use Liquid Glass".

The six laws in `SKILL.md` are those two directions, made operational:
- burgundy is the one colour added, and it goes where it helps most, on what you can do;
- glass is the material;
- the rest (the icons, the animation, the ChatGPT-like chat, the orb, and "the faster the simpler") is unchanged.
