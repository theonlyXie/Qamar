import type { AuthUser } from "../_shared/auth.ts";
import { db } from "../_shared/db.ts";
import { err, ok } from "../_shared/envelope.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";

/**
 * Chat contract endpoints. Full model generation remains on ai-gateway;
 * these routes own conversation lifecycle, stop, action confirm, and report.
 */
export async function handleChat(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  // POST /chat/responses — create/continue conversation (non-streaming JSON;
  // clients that need tokens stream from ai-gateway /chat/reply).
  if (method === "POST" && parts[1] === "responses") {
    const limit = await checkRateLimit(user.id, "chat", 40);
    if (!limit.allowed) {
      return err(req, 429, "quota_exceeded", "error.chat.quota_exceeded", { retryable: true });
    }

    const message = String(body.message ?? "").trim();
    const lang = body.lang === "en" ? "en" : "ar";
    if (!message) return err(req, 400, "missing_message", "error.chat.missing_message");

    let conversationId = body.conversation_id ? String(body.conversation_id) : null;
    if (!conversationId) {
      const c = await db("chat_conversations", {
        method: "POST",
        body: JSON.stringify({ user_id: user.id, lang, status: "open" }),
      });
      if (!c.ok) return err(req, 500, "chat_create_failed", "error.chat.create_failed");
      conversationId = (await c.json())[0].id;
    }

    await db("chat_messages", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({
        conversation_id: conversationId,
        user_id: user.id,
        role: "user",
        content: message,
      }),
    });

    // Proxy to ai-gateway for the grounded reply
    const gatewayUrl = Deno.env.get("AI_GATEWAY_INTERNAL_URL") ??
      `${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-gateway/chat/reply`;
    const aiRes = await fetch(gatewayUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: req.headers.get("Authorization") ?? "",
        apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      },
      body: JSON.stringify({ message, lang }),
    });

    let reply = "";
    let sources: unknown[] = [];
    let refused = false;
    if (aiRes.ok) {
      const payload = await aiRes.json();
      reply = payload.reply ?? "";
      sources = payload.sources ?? [];
      refused = !!payload.refused;
    } else {
      reply = lang === "ar"
        ? "المساعد مش متصل دلوقتي. جرّب تاني بعد شوية."
        : "The assistant is not connected right now. Try again shortly.";
      refused = true;
    }

    const mRes = await db("chat_messages", {
      method: "POST",
      body: JSON.stringify({
        conversation_id: conversationId,
        user_id: user.id,
        role: "assistant",
        content: reply,
        sources,
      }),
    });
    const assistantMsg = mRes.ok ? (await mRes.json())[0] : null;

    // Optional pending write-action token
    let pending_action = null;
    if (body.request_action) {
      const token = crypto.randomUUID();
      const a = await db("pending_actions", {
        method: "POST",
        body: JSON.stringify({
          user_id: user.id,
          kind: String((body.request_action as Record<string, unknown>).kind ?? "generic"),
          payload: body.request_action,
          confirmation_token: token,
        }),
      });
      if (a.ok) pending_action = (await a.json())[0];
    }

    return ok(req, {
      conversation_id: conversationId,
      message: assistantMsg,
      reply,
      sources,
      refused,
      pending_action,
      stream: false,
    });
  }

  // POST /chat/{id}/stop
  if (method === "POST" && parts[2] === "stop") {
    const id = parts[1];
    await db(`chat_conversations?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ status: "stopped", updated_at: new Date().toISOString() }),
    });
    return ok(req, { conversation_id: id, status: "stopped" });
  }

  // POST /messages/{id}/report — also /chat/messages/{id}/report
  if (method === "POST" && (parts[0] === "messages" || parts[1] === "messages") &&
    (parts[2] === "report" || parts[3] === "report")) {
    const messageId = parts[0] === "messages" ? parts[1] : parts[2];
    const res = await db(`chat_messages?id=eq.${messageId}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify({ reported_at: new Date().toISOString() }),
    });
    if (!res.ok) return err(req, 404, "message_not_found", "error.chat.message_not_found");
    return ok(req, { reported: true, message_id: messageId });
  }

  return err(req, 404, "not_found", "error.not_found");
}

export async function handleActions(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  if (req.method.toUpperCase() !== "POST" || parts[2] !== "confirm") {
    return err(req, 404, "not_found", "error.not_found");
  }
  const id = parts[1];
  const token = String(body.confirmation_token ?? body.token ?? "");
  const res = await db(
    `pending_actions?id=eq.${id}&user_id=eq.${user.id}&status=eq.pending&select=*`,
  );
  const rows = res.ok ? await res.json() : [];
  if (!rows[0]) return err(req, 404, "action_not_found", "error.actions.not_found");
  if (rows[0].confirmation_token !== token) {
    return err(req, 403, "invalid_token", "error.actions.invalid_token");
  }
  if (new Date(rows[0].expires_at).getTime() < Date.now()) {
    await db(`pending_actions?id=eq.${id}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ status: "expired" }),
    });
    return err(req, 410, "action_expired", "error.actions.expired");
  }
  await db(`pending_actions?id=eq.${id}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ status: "confirmed", resolved_at: new Date().toISOString() }),
  });
  return ok(req, { action: { ...rows[0], status: "confirmed" } });
}

export async function handleMemory(
  req: Request,
  parts: string[],
  user: AuthUser,
  body: Record<string, unknown>,
): Promise<Response> {
  const method = req.method.toUpperCase();

  if (method === "GET" && parts.length === 1) {
    const res = await db(`memories?user_id=eq.${user.id}&order=updated_at.desc&select=*`);
    return ok(req, { memories: res.ok ? await res.json() : [] });
  }

  if (method === "POST" && parts[1] === "proposals" && parts[3] === "confirm") {
    const proposalId = parts[2];
    const pRes = await db(
      `memory_proposals?id=eq.${proposalId}&user_id=eq.${user.id}&status=eq.pending&select=*`,
    );
    const proposals = pRes.ok ? await pRes.json() : [];
    if (!proposals[0]) return err(req, 404, "proposal_not_found", "error.memory.proposal_not_found");
    const mem = await db("memories", {
      method: "POST",
      body: JSON.stringify({
        user_id: user.id,
        kind: proposals[0].kind,
        content: proposals[0].content,
        provenance: proposals[0].provenance,
      }),
    });
    await db(`memory_proposals?id=eq.${proposalId}`, {
      method: "PATCH",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ status: "confirmed", resolved_at: new Date().toISOString() }),
    });
    if (!mem.ok) return err(req, 500, "memory_write_failed", "error.memory.write_failed");
    return ok(req, { memory: (await mem.json())[0] }, 201);
  }

  if ((method === "PATCH" || method === "DELETE") && parts[1]) {
    const id = parts[1];
    if (method === "DELETE") {
      await db(`memories?id=eq.${id}&user_id=eq.${user.id}`, {
        method: "DELETE",
        headers: { Prefer: "return=minimal" },
      });
      return ok(req, { deleted: true });
    }
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (body.content != null) patch.content = body.content;
    if (body.kind != null) patch.kind = body.kind;
    const res = await db(`memories?id=eq.${id}&user_id=eq.${user.id}`, {
      method: "PATCH",
      body: JSON.stringify(patch),
    });
    if (!res.ok) return err(req, 404, "memory_not_found", "error.memory.not_found");
    return ok(req, { memory: (await res.json())[0] });
  }

  return err(req, 404, "not_found", "error.not_found");
}
