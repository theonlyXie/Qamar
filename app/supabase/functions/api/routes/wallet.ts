import type { AuthUser } from "../_shared/auth.ts";
import { db, rpc } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { idempotencyKey, loadIdempotent, storeIdempotent } from "../_shared/idempotency.ts";

export async function handleJourney(
  req: Request,
  _parts: string[],
  user: AuthUser,
): Promise<Response> {
  if (req.method.toUpperCase() !== "GET") {
    return err(req, 405, "method_not_allowed", "error.method_not_allowed");
  }
  const [quests, achievements, cosmetics, wallet] = await Promise.all([
    db(`quests?user_id=eq.${user.id}&order=issued_at.desc&limit=7&select=*`),
    db(`user_achievements?user_id=eq.${user.id}&select=*`),
    db(`user_cosmetics?user_id=eq.${user.id}&select=*`),
    db(`wallet_accounts?user_id=eq.${user.id}&select=*`),
  ]);
  return ok(req, {
    quests: quests.ok ? await quests.json() : [],
    achievements: achievements.ok ? await achievements.json() : [],
    cosmetics: cosmetics.ok ? await cosmetics.json() : [],
    wallet: wallet.ok ? (await wallet.json())[0] ?? { available_points: 0 } : { available_points: 0 },
  });
}

export async function handleQuests(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const res = await db(`quests?user_id=eq.${user.id}&order=issued_at.desc&limit=14&select=*`);
    return ok(req, { quests: res.ok ? await res.json() : [] });
  }

  if (method === "POST" && parts[2] === "replace") {
    const id = parts[1];
    const key = idempotencyKey(req) ?? `quest-replace:${id}`;
    const prior = await loadIdempotent(user.id, "quest_replace", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    await db(`quests?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ replaced_at: new Date().toISOString() }),
    });
    const title = String(body.title ?? "New daily quest");
    const reason = String(body.reason ?? "Replaced quest");
    const res = await db("quests", {
      method: "POST",
      body: JSON.stringify({
        user_id: user.id,
        title,
        reason,
        su_points: Number(body.su_points ?? 5),
        quest_type: "primary_daily",
      }),
    });
    if (!res.ok) return err(req, 500, "quest_replace_failed", "error.quests.replace_failed");
    const payload = { quest: (await res.json())[0] };
    await storeIdempotent(user.id, "quest_replace", key, payload, 201, body);
    return ok(req, payload, 201);
  }

  if (method === "POST" && parts[2] === "skip") {
    const id = parts[1];
    await db(`quests?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ replaced_at: new Date().toISOString() }),
    });
    return ok(req, { skipped: true, id });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleAchievements(req: Request, user: AuthUser): Promise<Response> {
  const [catalog, earned] = await Promise.all([
    db("achievements?active=eq.true&select=*"),
    db(`user_achievements?user_id=eq.${user.id}&select=*`),
  ]);
  return ok(req, {
    catalog: catalog.ok ? await catalog.json() : [],
    earned: earned.ok ? await earned.json() : [],
  });
}

export async function handleCosmetics(
  req: Request,
  parts: string[],
  user: AuthUser,
): Promise<Response> {
  if (req.method.toUpperCase() !== "POST" || parts[2] !== "equip") {
    return err(req, 404, "not_found", "error.not_found");
  }
  const id = parts[1];
  // Unequip all, equip one
  await db(`user_cosmetics?user_id=eq.${user.id}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ equipped: false }),
  });
  const existing = await db(
    `user_cosmetics?user_id=eq.${user.id}&cosmetic_id=eq.${encodeURIComponent(id)}&select=*`,
  );
  const rows = existing.ok ? await existing.json() : [];
  if (rows.length === 0) {
    const ins = await db("user_cosmetics", {
      method: "POST",
      body: JSON.stringify({ user_id: user.id, cosmetic_id: id, equipped: true }),
    });
    if (!ins.ok) return err(req, 404, "cosmetic_not_found", "error.cosmetics.not_found");
    return ok(req, { cosmetic: (await ins.json())[0] });
  }
  const upd = await db(
    `user_cosmetics?user_id=eq.${user.id}&cosmetic_id=eq.${encodeURIComponent(id)}`,
    { method: "PATCH", body: JSON.stringify({ equipped: true }) },
  );
  return ok(req, { cosmetic: (await upd.json())[0] });
}

export async function handleWallet(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const [acct, ledger] = await Promise.all([
      db(`wallet_accounts?user_id=eq.${user.id}&select=*`),
      db(`su_point_ledger?user_id=eq.${user.id}&order=created_at.desc&limit=50&select=*`),
    ]);
    return ok(req, {
      account: acct.ok ? (await acct.json())[0] ?? { available_points: 0, lifetime_earned: 0 } : null,
      ledger: ledger.ok ? await ledger.json() : [],
    });
  }

  if (method === "GET" && parts[1] === "catalog") {
    const res = await db("wallet_catalog_items?active=eq.true&select=*");
    return ok(req, { items: res.ok ? await res.json() : [] });
  }

  if (method === "POST" && parts[1] === "redeem") {
    const key = idempotencyKey(req);
    if (!key) return err(req, 400, "idempotency_required", "error.wallet.idempotency_required");
    const prior = await loadIdempotent(user.id, "wallet_redeem", key);
    if (prior) return ok(req, prior.response_body, prior.response_status);

    const itemId = String(body.catalog_item_id ?? body.item_id ?? "");
    if (!itemId) return err(req, 400, "missing_item", "error.wallet.missing_item");

    const result = await rpc("qamar_wallet_redeem", {
      p_user_id: user.id,
      p_catalog_item_id: itemId,
      p_idempotency_key: key,
    });
    if (!result.ok) {
      return err(req, 400, "redeem_failed", "error.wallet.redeem_failed");
    }
    const payload = { result: result.data };
    await storeIdempotent(user.id, "wallet_redeem", key, payload, 200, body);
    return ok(req, payload);
  }

  return err(req, 404, "not_found", "error.not_found");
}
