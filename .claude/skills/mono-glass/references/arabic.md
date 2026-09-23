# Arabic-first

Our products are designed in Arabic and checked in English, not the other way round. RTL is a layout mirror, not a translation pass at the end.

## Layout

- **Build with directional APIs.** Use `EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderRadiusDirectional`, `PositionedDirectional`, `TextAlign.start`/`end`, and `CrossAxisAlignment.start`. `left`/`right` appear only where the thing is physically left or right: a camera guide, or a photo.
- **Leading is the right side** in Arabic: back buttons, the first item of a row, the start of a progress bar.
- **What mirrors:** reading-direction motion (a sheet pushed from the side, a list swiped to next), horizontal scroll start, sliders, steppers ("−" leading, "+" trailing), and linear progress.
- **What doesn't mirror:**
  - rings, clocks, circular progress and the moon's phase (the moon waxes on the right in both languages, as the real moon seen from Egypt does);
  - media controls;
  - photos, logos, and the digits inside a number.
- **Mixed text:** a dish name in English inside an Arabic sentence is fine. The style's fallback stack draws each script in its own face. Keep each paragraph's alignment by its own language when it's three lines or more (chat replies); keep short lines aligned by the UI direction.

## Type

- **Faces:** Arabic is set in **Noto Sans Arabic**, the fallback on every style, at 400/500/600/700. It has true tabular ٠–٩ and all the punctuation (، ؛ ؟ ٪ ٫ ٬).
- **Never track Arabic, and never uppercase-transform it.** Arabic has no case, and spacing breaks the joins. `QText.display(ar: true)` and `QText.eyebrow(ar: true)` handle this, so pass `ar` honestly. For text that isn't the interface's own (a person's name), use `QText.arabic(text)`.
- **Line heights are explicit on every style.** Arabic fonts default to 1.9–2.1 em, which breaks rhythm. The kit sets Apple's leading, and chat uses 26 for 17.
- **Size:** Arabic next to uppercase Latin can look small. At the same size, give an Arabic eyebrow weight 600 rather than a bigger size, so the scale stays fixed.
- **No dot type for Arabic words.** Dot numerals (`DotNumber`) have Arabic-Indic digits, and that's all. Arabic sentences are always in Noto Sans Arabic.

## Digits

- **The person chooses** Arabic-Indic (٠١٢٣) or Western (0123) digits in Arabic mode, and the choice is remembered. English always uses Western digits.
- **Format through one function** (Qamar: `state.iso(value)` / `state.digits(...)`). Never concatenate raw `toString()` into Arabic copy.
- **Never reverse a number's digits.** A number reads left to right in both scripts. Sequences such as "1 of 3" and fractions follow the sentence.
- **Separators:** Arabic uses ٫ for decimals and ٬ for thousands, and ٪ for percent. Check that the font has the glyph; Noto Sans Arabic does.
- **Live values are tabular** (`QText.number`), so a changing count doesn't jiggle.
- **Arabic-Indic zero:** ٠ is a small dot-like diamond. In dot numerals, set a bare "٠" large (hero only), or write the state in words ("لسه ما شربتش") rather than showing a lonely zero.

## Words

- **Arabic copy is Egyptian Arabic,** warm and direct, the way a friend who knows nutrition would talk. It's written, not translated: "أساعدك في إيه؟", not "كيف يمكنني مساعدتك؟".
- **Short:** a button is one to three words and starts with a verb ("سجّل", "ابدأ", "أكّد وسجّل").
- **Plural and gender:** use neutral phrasings where possible. Where not, use the person's chosen form if we have it, or the masculine-plural neutral form.
- **Numbers in words:** "٣ أسئلة", "٢ لتر". Follow Arabic number agreement for 1, 2 and 3–10 (سؤال واحد، سؤالين، ٣ أسئلة، ١١ سؤال).
- **Brand names** (Qamar+, Google, Apple) stay in Latin inside Arabic.

## Checks (both languages, every screen)

- [ ] Render in Arabic. Nothing is hard-left, clipped or overlapping; the back chevron points right.
- [ ] Render in English. Nothing is hard-right.
- [ ] A long Arabic string (the longest likely) fits or wraps, and never truncates a number.
- [ ] Digits follow the setting and are never reversed. ٪ ٫ ٬ render.
- [ ] No tracked or uppercased Arabic.
- [ ] Rings are clockwise in both languages; bars fill from the right in Arabic.
