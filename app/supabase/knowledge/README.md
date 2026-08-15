# The knowledge base

The assistant answers only from what is retrieved out of `kb_chunks` and looked
up in the food databases. It refuses when it finds nothing. That makes this
folder the ceiling on every answer the app will ever give.

## What belongs here, and what does not

**Here: guidance and structure.** Dietary targets from named authorities,
training principles, how an Egyptian dish is built, what a household portion
means in Cairo, how Ramadan reshapes a day, when to stop and refer to a doctor.

**Not here: per-dish calorie numbers.** Search the web for the calories in a
plate of koshari and you get 350 in one place and 600 in another. Writing
either into this folder would launder a guess into a citation — the app would
state it with total confidence and no way for anyone to notice it was wrong.

Composition comes from the food databases instead, at query time:

- **USDA FoodData Central** — Foundation and SR Legacy entries for ingredients
  (cooked lentils, cooked rice, fava beans, tahini). These are laboratory
  analyses, not crowd-sourced.
- **Open Food Facts** — packaged products with a barcode, which is where the
  brands on an Egyptian supermarket shelf live.

Neither has "koshari". Neither ever will — it is a dish, not an ingredient or a
product. So `05-egyptian-dishes.md` describes koshari as the ingredients it is
made from and the amount of each in a typical medium bowl, and the model prices
those ingredients against USDA. The number the user sees is then traceable to a
laboratory figure and a stated portion, and both can be argued with.

That is the whole design: this folder supplies structure and judgement, the
APIs supply numbers, and nothing supplies confidence it has not earned.

## Format

One markdown file per document. The header block becomes the `kb_documents`
row; everything after it is chunked and embedded.

```
---
source: WHO
title: Healthy diet — quantitative targets for adults
url: https://www.who.int/news-room/fact-sheets/detail/healthy-diet
licence: CC BY-NC-SA 3.0 IGO
domain: nutrition
---
```

`domain` is `nutrition` or `training`; the gateway's scope guard routes a
question to one or the other before retrieving.

## Building and ingesting

```sh
deno run --allow-read --allow-write build_sources.ts   # folder -> sources.json
deno run --allow-net --allow-env --allow-read functions/ai-gateway/ingest.ts sources.json
```

## Expanding it

This is a seed, not a finished library. It covers the questions an Egyptian
adult asks in their first month. Worth adding next: the Egyptian National
Nutrition Institute's food composition tables for local dishes measured
locally, guidance on diabetes and hypertension nutrition (both common in Egypt,
both places where the app must defer rather than advise), and regional dishes
from Upper Egypt and the coast that Cairo-centric lists miss.

Every document needs a real source. A document without a URL is an opinion
wearing a citation's clothes.
