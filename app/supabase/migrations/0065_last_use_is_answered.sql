-- The day's last question, photo and plan rewrite are answered, not taken and
-- refused (seat 4, found while building O13).
--
-- qamar_ai_try_consume (0041) returns the bucket after the use it just took,
-- through qamar_ai_bucket_json, whose "allowed" is used < limit + extra. After
-- the third of three that is 3 < 3: false. The gateway reads "allowed" on the
-- answer to decide whether to go on (ai-gateway/index.ts, takeAiUse: "if
-- (!q.allowed) return quotaDenied"), so the third question was counted and
-- then refused with the wall, and never refunded. The free tier promises
-- "three photos and three questions a day" (the paywall, Me, 0041) and was
-- answering two of each; the third plan rewrite was refused the same way, and
-- a member's fiftieth question. It would also have taken a question bought
-- with Su (0066) and refused it.
--
-- Only the answer changes: a use that was taken says allowed. A refused use
-- (used >= limit + extra) is unchanged, and so are the counters and every
-- caller. Idempotent: create or replace, and the grants are re-stated.

create or replace function public.qamar_ai_try_consume(p_user_id uuid, p_bucket text default 'chat')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day date := public.qamar_cairo_today();
  v_limit int;
  v_used int;
  v_extra int := 0;
  v_cap int;
begin
  if auth.role() <> 'service_role' then
    raise exception 'not authorised to consume AI quota';
  end if;
  if p_bucket not in ('photo', 'chat', 'plan') then
    raise exception 'unknown quota bucket %', p_bucket;
  end if;

  v_limit := public.qamar_ai_bucket_limit(p_user_id, p_bucket);

  insert into public.ai_usage_days (user_id, day)
  values (p_user_id, v_day)
  on conflict (user_id, day) do nothing;

  select
    case p_bucket when 'photo' then photo_used when 'chat' then chat_used else plan_used end,
    case p_bucket when 'photo' then extra else 0 end
  into v_used, v_extra
  from public.ai_usage_days
  where user_id = p_user_id and day = v_day
  for update;

  v_cap := v_limit + v_extra;
  if v_used >= v_cap then
    return public.qamar_ai_bucket_json(p_bucket, v_used, v_limit, v_extra)
      || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id));
  end if;

  update public.ai_usage_days
     set photo_used = photo_used + case when p_bucket = 'photo' then 1 else 0 end,
         chat_used  = chat_used  + case when p_bucket = 'chat'  then 1 else 0 end,
         plan_used  = plan_used  + case when p_bucket = 'plan'  then 1 else 0 end,
         updated_at = now()
   where user_id = p_user_id and day = v_day;

  -- This use was allowed: it was taken, and it is to be answered. The
  -- counters are the state after it ("remaining" can now be 0); "allowed"
  -- is about this call, which is what the gateway reads (0065).
  return public.qamar_ai_bucket_json(p_bucket, v_used + 1, v_limit, v_extra)
    || jsonb_build_object('day', v_day, 'plus', public.qamar_is_plus(p_user_id), 'allowed', true);
end;
$$;

revoke all on function public.qamar_ai_try_consume(uuid, text) from public, anon, authenticated;
grant execute on function public.qamar_ai_try_consume(uuid, text) to service_role;
