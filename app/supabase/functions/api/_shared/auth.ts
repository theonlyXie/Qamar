export type AuthUser = {
  id: string;
  email?: string | null;
  is_anonymous?: boolean;
  app_metadata?: Record<string, unknown>;
  user_metadata?: Record<string, unknown>;
};

export function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

export function serviceKey(): string {
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

export function anonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? serviceKey();
}

/** Verifies the caller's JWT with Supabase Auth and returns the user. */
export async function authenticate(req: Request): Promise<AuthUser | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const res = await fetch(`${supabaseUrl()}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: anonKey() },
  });
  if (!res.ok) return null;
  const user = await res.json();
  if (!user?.id) return null;
  return user as AuthUser;
}

/** Optional auth: returns null for guests without failing. */
export async function authenticateOptional(req: Request): Promise<AuthUser | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  return await authenticate(req);
}

export function bearerToken(req: Request): string | null {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  return auth.slice("Bearer ".length);
}
