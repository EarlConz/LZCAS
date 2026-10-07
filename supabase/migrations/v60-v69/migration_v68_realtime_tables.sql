-- ═══════════════════════════════════════════════════════════════════
-- Migration v68 — Live updates for every table the app listens to
--
-- Requires nothing new. Safe to re-run.
--
-- Part 3 testing (2026-10-03) found changes not reaching other devices:
-- a product added on the admin's phone did not appear on the admin's PC,
-- the member's Marketplace did not update, and a member edited on the PC
-- did not change on the phone until the app was reopened (W4).
--
-- The app subscribes to Postgres changes on these tables
-- (SupabaseRepository._initRealtime):
--   items, members, sales, pending_requests, withdrawal_requests, orders
-- Supabase only sends changes for tables in the `supabase_realtime`
-- publication, and new tables are not added to it automatically. Only
-- `orders` was ever added by a migration (v48); the rest depended on
-- someone switching them on in the dashboard (Database → Publications),
-- which the projects may never have had. Without it the app's
-- subscriptions connect and simply never hear anything.
--
-- This adds each one that is missing. Every viewer still receives only
-- rows their own row-level security lets them read.
--
-- Rollback: supabase/rollbacks/rollback_realtime_tables_v68.sql (removes
-- only the tables this migration added, as recorded in the ledger note).
-- ═══════════════════════════════════════════════════════════════════

-- Before: which of them are already published (run on its own if curious).
--   select tablename from pg_publication_tables
--    where pubname = 'supabase_realtime' and schemaname = 'public'
--    order by 1;

do $$
declare
  t       text;
  v_added text[] := '{}';
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'No supabase_realtime publication here; nothing to do.';
    return;
  end if;

  foreach t in array array['items', 'members', 'sales', 'pending_requests',
                           'withdrawal_requests', 'orders']
  loop
    continue when to_regclass('public.' || t) is null;
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      v_added := v_added || t;
    end if;
  end loop;

  raise notice 'Added to realtime: %', coalesce(nullif(array_to_string(v_added, ', '), ''), 'none, all were on');

  -- The rollback reads this to undo only what was added here.
  insert into public.schema_migrations (version, name, note)
  values (68, 'realtime_tables', 'added: ' || array_to_string(v_added, ','))
  on conflict (version) do update
    set applied_at = now(), applied_by = current_user, verified = true,
        note = case when array_length(v_added, 1) > 0
                    then excluded.note else public.schema_migrations.note end;
end $$;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. All six are published (expect 6 rows):
--      select tablename from pg_publication_tables
--       where pubname = 'supabase_realtime' and schemaname = 'public'
--         and tablename in ('items', 'members', 'sales', 'pending_requests',
--                           'withdrawal_requests', 'orders')
--       order by 1;
-- 2. What this run added: select note from public.schema_migrations where version = 68;
-- 3. In the app, two devices signed in: add a product on one; the other's
--    Inventory shows it within a few seconds, without reopening.
