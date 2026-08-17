/** CORS headers shared by every mobile-API response. */
export const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key, if-match, x-request-id",
  "Access-Control-Allow-Methods": "GET, POST, PATCH, PUT, DELETE, OPTIONS",
  "Access-Control-Expose-Headers": "etag, x-request-id",
};

export function requestId(req: Request): string {
  return req.headers.get("x-request-id") ?? crypto.randomUUID();
}
