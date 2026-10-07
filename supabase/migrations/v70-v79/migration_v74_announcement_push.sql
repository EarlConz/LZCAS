-- ═══════════════════════════════════════════════════════════════════
-- Migration v74 — Push notifications for announcements
--
-- Requires v58 (push_tokens, pg_net, the order_push_* Vault secrets) and
-- v51 (announcement audiences as they are now). Pairs with the Edge
-- Function supabase/functions/announcement-push. Safe to re-run.
--
-- Part 7 testing (2026-10-08, AT2): a new announcement reached nobody
-- whose app was closed. The app now counts new announcements on the tab
-- while it is open (lib/services/announcement_alerts.dart); this is the
-- closed-app half.
--
-- ── When a push goes out ───────────────────────────────────────────
-- Once per announcement, when it goes live: at posting for most, but at
-- its publish time for a scheduled one, which must not be announced
-- early. `pushed_at` records that it went out, so an edit, or the
-- trigger and the five-minute job meeting the same row, never sends it
-- twice.
--   * Posting (or rescheduling to now) fires a trigger that queues the
--     pushes for every announcement now due.
--   * A scheduled announcement is picked up by a pg_cron job every five
--     minutes. Where pg_cron cannot be enabled, scheduled announcements
--     simply go without a push (the count on the tab still shows them).
-- Announcements already up before this migration are marked pushed, so
-- applying it sends nothing about the past.
--
-- ── Configuration ──────────────────────────────────────────────────
-- None new. The function's address is order-push's (Vault secret
-- 'order_push_url') with the name swapped, and the shared secret is the
-- same 'order_push_secret'. Supabase function secrets are per project,
-- so announcement-push already has FIREBASE_SERVICE_ACCOUNT,
-- PUSH_WEBHOOK_SECRET and SERVICE_ROLE_KEY. Deploy it once:
--   supabase functions deploy announcement-push --no-verify-jwt
-- Until it is deployed the calls fail quietly (net._http_response shows
-- a 404) and nothing else is affected.
--
-- Rollback: supabase/rollbacks/rollback_announcement_push_v74.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Which announcements have been pushed ────────────────────────
alter table public.announcements
  add column if not exists pushed_at timestamptz;

-- The past is not news.
update public.announcements
   set pushed_at = now()
 where pushed_at is null
   and published_at <= now();

-- ── 2. Queue the pushes that are due ───────────────────────────────
-- Live, not yet pushed, and gone live within the last day (one that
-- slipped through a longer outage is old news by then).
create or replace function public.queue_announcement_pushes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
  v_row    record;
  v_count  integer := 0;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'order_push_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'order_push_secret';
  if v_url is null or v_secret is null then
    return 0;   -- push is not configured in this environment
  end if;
  v_url := replace(v_url, '/order-push', '/announcement-push');

  for v_row in
    update public.announcements
       set pushed_at = now()
     where pushed_at is null
       and archived_at is null
       and published_at <= now()
       and published_at > now() - interval '1 day'
       and (ends_at is null or ends_at > now())
    returning id
  loop
    perform net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
                   'Content-Type',  'application/json',
                   'Authorization', 'Bearer ' || v_secret),
      body    := jsonb_build_object('announcement_id', v_row.id)
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ── 3. On posting ──────────────────────────────────────────────────
create or replace function public.announcements_queue_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.queue_announcement_pushes();
  return null;
exception when others then
  -- A notification is never worth failing a post for.
  raise warning 'announcement push not queued: %', sqlerrm;
  return null;
end;
$$;

drop trigger if exists announcements_push on public.announcements;
create trigger announcements_push
  after insert or update of published_at, archived_at, ends_at
  on public.announcements
  for each statement
  execute function public.announcements_queue_push();

-- ── 4. Scheduled ones, every five minutes ──────────────────────────
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron is not available here (%): scheduled announcements will not be pushed.', sqlerrm;
    return;
  end;
  perform cron.schedule(
    'announcement-push',
    '*/5 * * * *',
    'select public.queue_announcement_pushes()'
  );
end;
$$;

-- ── 5. Grants ──────────────────────────────────────────────────────
-- Only the trigger and the job call these, as their owner.
revoke all on function public.queue_announcement_pushes() from public, anon, authenticated;
revoke all on function public.announcements_queue_push() from public, anon, authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (74, 'announcement_push')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. The column, the trigger and the job (expect: 1, 1, 1; where
--    pg_cron is unavailable, drop the `job` line, as cron.job is missing):
--      select
--        (select count(*) from information_schema.columns
--          where table_schema = 'public' and table_name = 'announcements'
--            and column_name = 'pushed_at') as pushed_at_column,
--        (select count(*) from pg_trigger
--          where tgname = 'announcements_push') as trigger,
--        (select count(*) from cron.job
--          where jobname = 'announcement-push') as job;
-- 2. Nothing from the past is waiting (expect 0):
--      select count(*) from public.announcements
--       where pushed_at is null and published_at <= now();
-- 3. After posting one, the call was made (status_code 200 expected;
--    404 means announcement-push is not deployed yet):
--      select id, status_code, content::text, created
--        from net._http_response order by created desc limit 5;
