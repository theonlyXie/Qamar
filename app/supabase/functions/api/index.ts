// Qamar mobile API — spec_mvp.txt §29.6 internal contract.
//
// Deployed as Supabase Edge Function `api`. The Flutter app calls
// `${SUPABASE_URL}/functions/v1/api/...` with the user JWT.
//
// Envelope: { data, request_id } | { error: { code, message_key, retryable }, request_id }
// Idempotency-Key required on confirm / redeem / billing / export / deletion writes.

import { authenticate, authenticateOptional } from "./_shared/auth.ts";
import { CORS } from "./_shared/cors.ts";
import { err } from "./_shared/envelope.ts";
import { parsePath, readJson } from "./_shared/util.ts";

import { handleAuth, handleBootstrap, handleConfig } from "./routes/bootstrap_auth.ts";
import { handleConsents, handleGuidance, handleProfile, handleTargets } from "./routes/profile.ts";
import { handleMealDrafts, handleMeals, handleMedia } from "./routes/meals.ts";
import { handleBarcodes, handleFoods } from "./routes/foods.ts";
import { handleInsights, handlePlans, handleProgress } from "./routes/plans_progress.ts";
import { handleActions, handleChat, handleMemory } from "./routes/chat_memory.ts";
import {
  handleAchievements,
  handleCosmetics,
  handleJourney,
  handleQuests,
  handleWallet,
} from "./routes/wallet.ts";
import { handleBilling, handleWebhooks } from "./routes/billing.ts";
import {
  handleAdmin,
  handleAnalytics,
  handleDevices,
  handlePrivacy,
  handleReminders,
} from "./routes/ops.ts";

const PUBLIC_GET = new Set(["/bootstrap", "/config"]);
const PUBLIC_POST_PREFIX = ["/auth/", "/webhooks/", "/promo/"];

function isPublic(method: string, route: string): boolean {
  if (method === "GET" && PUBLIC_GET.has(route)) return true;
  if (method === "GET" && route === "/billing/offering") return true;
  if (method === "POST") {
    for (const p of PUBLIC_POST_PREFIX) {
      if (route === p.slice(0, -1) || route.startsWith(p)) return true;
    }
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const { route, parts } = parsePath(url);
  const method = req.method.toUpperCase();

  let body: Record<string, unknown> = {};
  if (method !== "GET" && method !== "DELETE") {
    const parsed = await readJson(req);
    if (parsed === null && method !== "OPTIONS") {
      // DELETE may have empty body
    }
    if (parsed === null && (method === "POST" || method === "PATCH" || method === "PUT")) {
      // Allow empty body for some POSTs
      try {
        // already consumed — readJson returns null on invalid
      } catch {
        /* ignore */
      }
    }
    body = parsed ?? {};
  } else if (method === "DELETE") {
    body = (await readJson(req)) ?? {};
  }

  try {
    // Webhooks never use user JWT
    if (parts[0] === "webhooks") {
      return await handleWebhooks(req, parts, body);
    }

    const needsAuth = !isPublic(method, route);
    const user = needsAuth ? await authenticate(req) : await authenticateOptional(req);
    if (needsAuth && !user) {
      return err(req, 401, "unauthorized", "error.unauthorized");
    }

    // Bootstrap / config
    if (parts[0] === "bootstrap" && method === "GET") {
      return await handleBootstrap(req, user);
    }
    if (parts[0] === "config" && method === "GET") {
      return await handleConfig(req);
    }

    // Auth
    if (parts[0] === "auth") {
      return await handleAuth(req, parts, user, body);
    }

    // Everything below requires a user (needsAuth already enforced)
    if (!user) return err(req, 401, "unauthorized", "error.unauthorized");

    if (parts[0] === "consents") return await handleConsents(req, parts, user, body);
    if (parts[0] === "profile") return await handleProfile(req, parts, user, body);
    if (parts[0] === "targets") return await handleTargets(req, parts, user, body);
    if (parts[0] === "guidance") return await handleGuidance(req, parts, user);

    if (parts[0] === "media") return await handleMedia(req, parts, user, body);
    if (parts[0] === "meal-drafts") return await handleMealDrafts(req, parts, user, body);
    if (parts[0] === "meals") return await handleMeals(req, parts, user, body);

    if (parts[0] === "foods" || parts[0] === "product-label-drafts" || parts[0] === "food-corrections") {
      return await handleFoods(req, parts, user, body);
    }
    if (parts[0] === "barcodes") return await handleBarcodes(req, parts, user);

    if (parts[0] === "plans") return await handlePlans(req, parts, user, body);
    if (parts[0] === "progress" || parts[0] === "weight") {
      return await handleProgress(req, parts, user, body);
    }
    if (parts[0] === "insights") return await handleInsights(req, parts, user, body);

    if (parts[0] === "chat" || parts[0] === "messages") {
      return await handleChat(req, parts, user, body);
    }
    if (parts[0] === "actions") return await handleActions(req, parts, user, body);
    if (parts[0] === "memory") return await handleMemory(req, parts, user, body);

    if (parts[0] === "journey") return await handleJourney(req, parts, user);
    if (parts[0] === "quests") return await handleQuests(req, parts, user, body);
    if (parts[0] === "achievements" && method === "GET") {
      return await handleAchievements(req, user);
    }
    if (parts[0] === "cosmetics") return await handleCosmetics(req, parts, user);
    if (parts[0] === "wallet") return await handleWallet(req, parts, user, body);

    if (parts[0] === "billing" || parts[0] === "promo") {
      return await handleBilling(req, parts, user, body);
    }

    if (parts[0] === "devices") return await handleDevices(req, parts, user, body);
    if (parts[0] === "reminders") return await handleReminders(req, parts, user, body);

    if (
      parts[0] === "exports" ||
      parts[0] === "conversations" ||
      parts[0] === "account-deletion"
    ) {
      return await handlePrivacy(req, parts, user, body);
    }

    if (parts[0] === "events" || parts[0] === "feedback" || parts[0] === "support-code") {
      return await handleAnalytics(req, parts, user, body);
    }

    if (parts[0] === "admin") return await handleAdmin(req, parts, user, body);

    return err(req, 404, "not_found", "error.not_found");
  } catch (e) {
    console.error("api", route, e);
    return err(req, 500, "internal_error", "error.internal", { retryable: true });
  }
});
