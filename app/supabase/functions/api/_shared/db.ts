import { serviceKey, supabaseUrl } from "./auth.ts";

export async function db(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${supabaseUrl()}/rest/v1/${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      apikey: serviceKey(),
      Authorization: `Bearer ${serviceKey()}`,
      Prefer: "return=representation",
      ...(init.headers ?? {}),
    },
  });
}

export async function rpc<T = unknown>(
  name: string,
  args: Record<string, unknown>,
): Promise<{ ok: boolean; data: T | null; status: number; text: string }> {
  const res = await fetch(`${supabaseUrl()}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: serviceKey(),
      Authorization: `Bearer ${serviceKey()}`,
    },
    body: JSON.stringify(args),
  });
  const text = await res.text();
  let data: T | null = null;
  try {
    data = text ? (JSON.parse(text) as T) : null;
  } catch {
    data = null;
  }
  return { ok: res.ok, data, status: res.status, text };
}

export async function dbJson<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await db(path, init);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`db ${path} → ${res.status}: ${text}`);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/** SHA-256 hex of a string (for promo code hashing / request hashes). */
export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
