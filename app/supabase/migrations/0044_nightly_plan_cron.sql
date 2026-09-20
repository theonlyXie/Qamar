-- The night job: at 22:00 Cairo, write tomorrow's plan for every Qamar+
-- member who does not have one yet.
--
-- pg_cron fires in UTC and Egypt moves its clocks (UTC+2 winter, UTC+3
-- summer), so the schedule fires at both 19:00 and 20:00 UTC and the
-- gateway itself checks the Cairo hour: one of the two firings is 22:00
-- Cairo, the other is 21:00 (skipped) or 23:00 (a second pass for members a
-- long first pass did not reach). Members who already have tomorrow's plan
-- are never written a second one, so extra firings are harmless.
--
-- Secrets live in Vault, never in this file. Before the job can run, once:
--
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/ai-gateway', 'qamar_gateway_url');
--   select vault.create_secret('<anon key>',        'qamar_anon_key');    -- passes the platform JWT check
--   select vault.create_secret('<long random>',     'qamar_cron_secret'); -- must equal QAMAR_CRON_SECRET on the function
--
-- and on the function: supabase secrets set QAMAR_CRON_SECRET=<the same long random>.
-- Until all three exist the job logs a notice and does nothing.

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

create or replace function public.qamar_run_nightly_plans()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_anon text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'qamar_gateway_url';
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'qamar_anon_key';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'qamar_cron_secret';
  if v_url is null or v_anon is null or v_secret is null then
    raise notice 'qamar nightly plans: vault secrets qamar_gateway_url / qamar_anon_key / qamar_cron_secret not all set; skipping';
    return;
  end if;

  perform net.http_post(
    url := rtrim(v_url, '/') || '/plan/nightly',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon,
      'Authorization', 'Bearer ' || v_anon,
      'X-Qamar-Cron', v_secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 5000
  );
end;
$$;

-- Only the scheduler runs this.
revoke all on function public.qamar_run_nightly_plans() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('qamar-nightly-plans');
exception when others then
  -- Not scheduled yet.
  null;
end;
$$;

select cron.schedule(
  'qamar-nightly-plans',
  '0 19,20 * * *',
  $$ select public.qamar_run_nightly_plans(); $$
);
