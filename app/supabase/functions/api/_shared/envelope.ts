import { CORS, requestId } from "./cors.ts";

export type ApiError = {
  code: string;
  message_key: string;
  retryable: boolean;
  field_errors?: Record<string, string>;
};

export function ok(req: Request, data: unknown, status = 200, extra: HeadersInit = {}): Response {
  const rid = requestId(req);
  return new Response(JSON.stringify({ data, request_id: rid }), {
    status,
    headers: {
      ...CORS,
      "Content-Type": "application/json",
      "x-request-id": rid,
      ...Object.fromEntries(new Headers(extra).entries()),
    },
  });
}

export function err(
  req: Request,
  status: number,
  code: string,
  messageKey: string,
  opts: { retryable?: boolean; field_errors?: Record<string, string> } = {},
): Response {
  const rid = requestId(req);
  const body: { error: ApiError; request_id: string } = {
    request_id: rid,
    error: {
      code,
      message_key: messageKey,
      retryable: opts.retryable ?? (status >= 500 || status === 429),
      field_errors: opts.field_errors,
    },
  };
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "x-request-id": rid },
  });
}
