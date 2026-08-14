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

async function embedBatch(texts: string[]): Promise<number[][]> {
  const voyage = Deno.env.get("VOYAGE_API_KEY");
  if (voyage) {
    const res = await fetch("https://api.voyageai.com/v1/embeddings", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${voyage}` },
      body: JSON.stringify({
        model: Deno.env.get("EMBEDDING_MODEL") ?? "voyage-3",
        input: texts,
        input_type: "document", // documents, not queries — it matters for Voyage
      }),
    });
    if (!res.ok) throw new Error(`voyage: ${res.status} ${await res.text()}`);
    const json = await res.json();
    return json.data.map((d: { embedding: number[] }) => d.embedding);
  }

  const openai = Deno.env.get("OPENAI_API_KEY");
  if (openai) {
    const res = await fetch("https://api.openai.com/v1/embeddings", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${openai}` },
      body: JSON.stringify({ model: "text-embedding-3-small", input: texts, dimensions: 1024 }),
    });
    if (!res.ok) throw new Error(`openai: ${res.status} ${await res.text()}`);
    const json = await res.json();
    return json.data.map((d: { embedding: number[] }) => d.embedding);
  }

  throw new Error("set VOYAGE_API_KEY or OPENAI_API_KEY");
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

async function ingest(doc: SourceDoc): Promise<void> {
  const created = await db("kb_documents", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({
      source: doc.source,
      title: doc.title,
      url: doc.url ?? null,
      licence: doc.licence ?? null,
      domain: doc.domain,
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
  console.log(`ingesting ${docs.length} documents`);
  for (const doc of docs) {
    await ingest(doc);
  }
  console.log("done — rebuild the ivfflat index after a large ingest:");
  console.log("  reindex index kb_chunks_embedding_idx;");
}
