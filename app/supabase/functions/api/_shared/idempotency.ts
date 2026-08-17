import { db, sha256Hex } from "./db.ts";

type Stored = { response_status: number; response_body: unknown };

/**
 * Returns a prior response when the same idempotency key was already used.
 * On first use, call `store` after computing the response.
 */
export async function loadIdempotent(
  userId: string,
  scope: string,
  key: string | null,
): Promise<Stored | null> {
  if (!key) return null;
  const rows = await db(
    `idempotency_keys?user_id=eq.${userId}&scope=eq.${encodeURIComponent(scope)}&key=eq.${encodeURIComponent(key)}&select=response_status,response_body`,
  );
  if (!rows.ok) return null;
  const data = await rows.json();
  return data[0] ?? null;
}

export async function storeIdempotent(
  userId: string,
  scope: string,
  key: string,
  body: unknown,
  status: number,
  requestBody?: unknown,
): Promise<void> {
  const request_hash = requestBody != null ? await sha256Hex(JSON.stringify(requestBody)) : null;
  await db("idempotency_keys", {
    method: "POST",
    headers: { Prefer: "resolution=ignore-duplicates,return=minimal" },
    body: JSON.stringify({
      user_id: userId,
      scope,
      key,
      request_hash,
      response_status: status,
      response_body: body,
    }),
  });
}

export function idempotencyKey(req: Request): string | null {
  const k = req.headers.get("idempotency-key")?.trim();
  return k && k.length > 0 ? k : null;
}
