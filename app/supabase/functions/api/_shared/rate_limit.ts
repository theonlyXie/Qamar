import { db } from "./db.ts";

/** Increment a daily counter; returns false when the limit is exceeded. */
export async function checkRateLimit(
  userId: string,
  bucket: string,
  limit: number,
): Promise<{ allowed: boolean; count: number }> {
  const day = new Date().toISOString().slice(0, 10);
  const existing = await db(
    `rate_limits?user_id=eq.${userId}&bucket=eq.${encodeURIComponent(bucket)}&day=eq.${day}&select=count`,
  );
  let count = 0;
  if (existing.ok) {
    const rows = await existing.json();
    count = rows[0]?.count ?? 0;
  }
  if (count >= limit) return { allowed: false, count };

  if (count === 0) {
    await db("rate_limits", {
      method: "POST",
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
      body: JSON.stringify({ user_id: userId, bucket, day, count: 1 }),
    });
    return { allowed: true, count: 1 };
  }

  await db(`rate_limits?user_id=eq.${userId}&bucket=eq.${encodeURIComponent(bucket)}&day=eq.${day}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ count: count + 1 }),
  });
  return { allowed: true, count: count + 1 };
}
