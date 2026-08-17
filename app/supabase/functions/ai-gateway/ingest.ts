// Knowledge-base ingestion.
//
// The gateway refuses to answer without retrieved guidance, so nothing works
// until this has been run at least once.
//
//   deno run --allow-net --allow-env --allow-read ingest.ts sources.json
//
// sources.json:
// [
//   {
//     "source": "WHO",
//     "title": "Healthy diet fact sheet",
//     "url": "https://www.who.int/...",
//     "licence": "CC BY-NC-SA 3.0 IGO",
//     "domain": "nutrition",
//     "text": "full document text..."
//   }
// ]
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and VOYAGE_API_KEY or
// OPENAI_API_KEY (the same provider the gateway uses — mixing them makes the
// stored vectors meaningless).

interface SourceDoc {
  source: string;
  title: string;
  url?: string;
  licence?: string;
  domain: "nutrition" | "training";
  text: string;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/**
 * Splits on paragraph boundaries, packing up to ~700 words per chunk with a
 * one-paragraph overlap. Retrieval works far better on whole thoughts than on
 * fixed-width slices that cut sentences in half.
 */
function chunk(text: string, targetWords = 700): string[] {
  const paragraphs = text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
  const chunks: string[] = [];
  let current: string[] = [];
  let words = 0;

  for (const p of paragraphs) {
    const n = p.split(/\s+/).length;
    if (words + n > targetWords && current.length > 0) {
      chunks.push(current.join("\n\n"));
      current = [current[current.length - 1]]; // overlap for continuity
      words = current[0].split(/\s+/).length;
    }
    current.push(p);
    words += n;
  }
  if (current.length) chunks.push(current.join("\n\n"));
  return chunks;
}

// ---- rate limiting -------------------------------------------------------
//
// A free Voyage account without a payment method is capped at 3 requests per
// minute. That is not an error condition for a one-off ingest — it is the
// normal state of a new account — so this waits it out rather than dying.
//
// The pacing is adaptive on purpose. Nothing is slowed down until the provider
// actually says to; the first 429 switches on a minimum gap between calls for
// the rest of the run, so an ingest on a limited account finishes slowly
// instead of failing fast.

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** 3 requests per minute is one every 20 seconds; a second of slack. */
const PACED_INTERVAL_MS = 21_000;
const MAX_ATTEMPTS = 6;

let minIntervalMs = Number(Deno.env.get("EMBED_MIN_INTERVAL_MS") ?? 0);
let lastCallAt = 0;

async function embedRequest(url: string, key: string, body: unknown): Promise<number[][]> {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const wait = lastCallAt + minIntervalMs - Date.now();
    if (wait > 0) await sleep(wait);
    lastCallAt = Date.now();

    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify(body),
    });

    if (res.ok) {
      const json = await res.json();
      return json.data.map((d: { embedding: number[] }) => d.embedding);
    }

    const detail = await res.text();
    const retryable = res.status === 429 || res.status >= 500;
    if (!retryable || attempt === MAX_ATTEMPTS) {
      throw new Error(`embeddings: ${res.status} ${detail}`);
    }

    if (res.status === 429) {
      // Every later call in this run gets spaced out too. Retrying one request
      // and then immediately firing the next at full speed just moves the
      // failure along by one.
      minIntervalMs = Math.max(minIntervalMs, PACED_INTERVAL_MS);
    }
    // Retry-After is authoritative when the provider sends it.
    const header = Number(res.headers.get("retry-after"));
    const backoff = Number.isFinite(header) && header > 0
      ? header * 1000
      : Math.max(PACED_INTERVAL_MS, 2 ** attempt * 1000);

    console.warn(
      `  rate limited (${res.status}); waiting ${Math.round(backoff / 1000)}s ` +
        `then retrying — attempt ${attempt} of ${MAX_ATTEMPTS}`,
    );
    await sleep(backoff);
  }
  throw new Error("unreachable");
}

/**
 * The model this run will use, named the same way retrieval.ts picks one.
 *
 * Voyage wins when both keys are present, which is worth knowing when
 * switching providers: adding OPENAI_API_KEY does not switch anything while
 * VOYAGE_API_KEY is still set. The old key has to be removed, in the gateway's
 * secrets as well as here, or the corpus and the queries end up on different
 * models and every answer is retrieved by noise.
 */
export function currentEmbeddingModel(): string {
  if (Deno.env.get("VOYAGE_API_KEY")) {
    return Deno.env.get("EMBEDDING_MODEL") ?? "voyage-3";
  }
  if (Deno.env.get("OPENAI_API_KEY")) {
    return Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-small";
  }
  throw new Error("set VOYAGE_API_KEY or OPENAI_API_KEY");
}

async function embedBatch(texts: string[]): Promise<number[][]> {
  const model = currentEmbeddingModel();
  const voyage = Deno.env.get("VOYAGE_API_KEY");
  if (voyage) {
    return await embedRequest("https://api.voyageai.com/v1/embeddings", voyage, {
      model,
      input: texts,
      input_type: "document", // documents, not queries — it matters for Voyage
    });
  }

  const openai = Deno.env.get("OPENAI_API_KEY")!;
  return await embedRequest("https://api.openai.com/v1/embeddings", openai, {
    model,
    input: texts,
    // kb_chunks.embedding is vector(1024). OpenAI returns 1536 by default, so
    // this is not a preference — the insert fails without it.
    dimensions: 1024,
  });
}

async function db(path: string, init: RequestInit): Promise<Response> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: SERVICE_KEY!,
      Authorization: `Bearer ${SERVICE_KEY}`,
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) throw new Error(`${path}: ${res.status} ${await res.text()}`);
  return res;
}

type Outcome = "ingested" | "skipped" | "repaired" | "re-embedded";

/**
 * Ingests one document, or reports why it did not need to be.
 *
 * Re-running this used to insert a second copy of everything, which made the
 * only sane response to a half-finished run — run it again — the wrong one.
 * Now the state is read first, and there are exactly three cases:
 *
 *   chunks, same model         nothing to do
 *   chunks, a different model  the provider changed. Skipping here would be
 *                              the worst outcome available: the corpus would
 *                              hold vectors from two models in one index, and
 *                              retrieval would rank by noise while every row
 *                              count still looked healthy. Re-embedded.
 *   there with no chunks       a previous run died between creating the row
 *                              and embedding its text. That row is not
 *                              harmless: it looks ingested and contributes
 *                              nothing to retrieval. Removed and redone.
 *   not there                  ingest it
 *
 * The identity is (source, title), which is what a document is called and
 * where it came from. Two documents differing only in body text are the same
 * document revised, and the revision should replace rather than accumulate.
 */
async function ingest(doc: SourceDoc, model: string): Promise<Outcome> {
  const q = `kb_documents?source=eq.${encodeURIComponent(doc.source)}` +
    `&title=eq.${encodeURIComponent(doc.title)}&select=id,embedding_model`;
  const existing = await (await db(q, { method: "GET" })).json() as {
    id: string;
    embedding_model: string | null;
  }[];

  let outcome: Outcome = "ingested";

  if (existing.length > 0) {
    const ids = existing.map((r) => r.id);
    const counted = await (await db(
      `kb_chunks?document_id=in.(${ids.join(",")})&select=id&limit=1`,
      { method: "GET" },
    )).json() as unknown[];

    if (counted.length > 0) {
      const stored = existing.find((r) => r.embedding_model)?.embedding_model ?? null;
      if (stored === model) {
        console.log(`  ${doc.title}: already ingested with ${model}, skipping`);
        return "skipped";
      }
      console.log(
        `  ${doc.title}: embedded with ${stored ?? "an unrecorded model"}, ` +
          `now using ${model} — re-embedding`,
      );
      await db(`kb_documents?id=in.(${ids.join(",")})`, { method: "DELETE" });
      outcome = "re-embedded";
    } else {
      console.log(`  ${doc.title}: found ${ids.length} row(s) with no chunks — repairing`);
      await db(`kb_documents?id=in.(${ids.join(",")})`, { method: "DELETE" });
      outcome = "repaired";
    }
  }

  const created = await db("kb_documents", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      source: doc.source,
      title: doc.title,
      url: doc.url ?? null,
      licence: doc.licence ?? null,
      domain: doc.domain,
      embedding_model: model,
    }),
  });
  const documentId = (await created.json())[0].id;

  const pieces = chunk(doc.text);
  console.log(`  ${doc.title}: ${pieces.length} chunks`);

  // Batched, because embedding APIs charge and rate-limit per request.
  for (let i = 0; i < pieces.length; i += 16) {
    const batch = pieces.slice(i, i + 16);
    const vectors = await embedBatch(batch);
    await db("kb_chunks", {
      method: "POST",
      body: JSON.stringify(
        batch.map((content, j) => ({
          document_id: documentId,
          chunk_index: i + j,
          content,
          embedding: vectors[j],
        })),
      ),
    });
  }
  return outcome;
}

if (import.meta.main) {
  if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error("set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY");
    Deno.exit(1);
  }
  const path = Deno.args[0];
  if (!path) {
    console.error("usage: deno run --allow-net --allow-env --allow-read ingest.ts sources.json");
    Deno.exit(1);
  }

  const docs: SourceDoc[] = JSON.parse(await Deno.readTextFile(path));
  const model = currentEmbeddingModel();
  console.log(`ingesting ${docs.length} documents with ${model}`);

  const tally: Record<Outcome, number> = {
    ingested: 0,
    skipped: 0,
    repaired: 0,
    "re-embedded": 0,
  };
  for (const doc of docs) {
    tally[await ingest(doc, model)]++;
  }

  console.log(
    `\ndone — ${tally.ingested} ingested, ${tally["re-embedded"]} re-embedded, ` +
      `${tally.repaired} repaired, ${tally.skipped} already present`,
  );
  if (tally["re-embedded"] > 0) {
    console.log(
      `the provider changed, so those documents were rebuilt on ${model}. The ` +
        "gateway must use the same model to query with, or retrieval compares " +
        "vectors from two different spaces — check its secrets.",
    );
  }
  if (minIntervalMs > 0) {
    console.log(
      "this account is rate limited, so the run was paced. Adding a payment " +
        "method at dashboard.voyageai.com lifts the limit and keeps the free tokens.",
    );
  }
  console.log("rebuild the ivfflat index after a large ingest:");
  console.log("  reindex index kb_chunks_embedding_idx;");
}
