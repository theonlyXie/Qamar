// Compiles the markdown corpus into the JSON that ingest.ts eats.
//
//   deno run --allow-read --allow-write build_sources.ts [outfile]
//
// Keeping the corpus as one file per document rather than one big JSON is
// deliberate: these are documents people have to read and argue with, and a
// diff on a 40 KB JSON string tells you nothing about what changed in the
// advice.

interface SourceDoc {
  source: string;
  title: string;
  url?: string;
  licence?: string;
  domain: "nutrition" | "training";
  text: string;
}

const DOMAINS = new Set(["nutrition", "training"]);

/** Splits `---` front matter from the body, and fails loudly on a bad header. */
function parse(file: string, raw: string): SourceDoc {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) throw new Error(`${file}: missing --- front matter block`);

  const [, header, body] = match;
  const fields: Record<string, string> = {};
  for (const line of header.split("\n")) {
    const at = line.indexOf(":");
    if (at === -1) continue;
    fields[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }

  for (const required of ["source", "title", "domain"]) {
    if (!fields[required]) throw new Error(`${file}: missing '${required}'`);
  }
  if (!DOMAINS.has(fields.domain)) {
    throw new Error(`${file}: domain must be nutrition or training, got '${fields.domain}'`);
  }
  // A document with no source URL is an opinion wearing a citation's clothes.
  // Internal documents are allowed to point at the evidence they rest on
  // rather than at themselves, but they must point somewhere.
  if (!fields.url) throw new Error(`${file}: no url — every document must be traceable`);

  const text = body.trim();
  if (text.length < 200) throw new Error(`${file}: body too short to be worth embedding`);

  return {
    source: fields.source,
    title: fields.title,
    url: fields.url,
    licence: fields.licence,
    domain: fields.domain as "nutrition" | "training",
    text,
  };
}

if (import.meta.main) {
  const out = Deno.args[0] ?? "sources.json";
  const docs: SourceDoc[] = [];

  const names: string[] = [];
  for await (const entry of Deno.readDir(".")) {
    if (entry.isFile && entry.name.endsWith(".md") && entry.name !== "README.md") {
      names.push(entry.name);
    }
  }
  names.sort();

  for (const name of names) {
    const doc = parse(name, await Deno.readTextFile(name));
    docs.push(doc);
    const words = doc.text.split(/\s+/).length;
    console.log(`  ${name.padEnd(34)} ${doc.domain.padEnd(10)} ${words} words`);
  }

  await Deno.writeTextFile(out, JSON.stringify(docs, null, 2));
  const total = docs.reduce((n, d) => n + d.text.split(/\s+/).length, 0);
  console.log(`\n${docs.length} documents, ${total} words -> ${out}`);
}
