import { db, sha256Hex } from "./db.ts";

export async function isAdmin(userId: string): Promise<boolean> {
  const res = await db(`founder_admins?user_id=eq.${userId}&select=role`);
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

export async function hashPromoCode(code: string): Promise<string> {
  return await sha256Hex(code.trim().toUpperCase());
}

export function parsePath(url: URL): { route: string; parts: string[] } {
  // Supabase serves functions at /functions/v1/<name>/...
  let path = url.pathname;
  path = path.replace(/^\/functions\/v1\/api/, "");
  path = path.replace(/^\/api/, "");
  if (!path.startsWith("/")) path = `/${path}`;
  if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1);
  const parts = path.split("/").filter(Boolean);
  return { route: path || "/", parts };
}

export async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    if (body && typeof body === "object" && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
    return {};
  } catch {
    return null;
  }
}
