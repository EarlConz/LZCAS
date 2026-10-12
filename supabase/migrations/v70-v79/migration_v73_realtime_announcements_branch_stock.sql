-- ═══════════════════════════════════════════════════════════════════
-- Migration v73 — Live updates for announcements and branch stock
--
-- Requires v36 (announcements) and v30 (branch_stock). Safe to re-run.
--
-- Part 5 testing (2026-10-06) asked whether the admin's screens update
-- by themselves on every tab. Two did not when the change came from
-- another device:
--   Announcements — a cashier's new post did not appear on the admin's
--                   board until the tab was reopened;
--   Branch Stock  — stock given to or returned by a branch did not show
--                   on the other staff devices.
-- The app now subscribes to both tables (SupabaseRepository._initRealtime).
-- Supabase only sends changes for tables in the `supabase_realtime`
-- publication; this adds the two that are missing. Every viewer still
-- receives only rows their own row-level security lets them read (a
-- member: the announcements sent to them; a branch cashier: their own
-- branch stock).
--
-- Rollback: supabase/rollbacks/rollback_realtime_announcements_branch_stock_v73.sql
-- (removes only the tables this migration added, as recorded in the
-- ledger note).
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  t       text;
  v_added text[] := '{}';
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'No supabase_realtime publication here; nothing to do.';
    return;
  end if;

  foreach t in array array['announcements', 'branch_stock']
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

  raise notice 'Added to realtime: %', coalesce(nullif(array_to_string(v_added, ', '), ''), 'none, both were on');

  -- The rollback reads this to undo only what was added here.
  insert into public.schema_migrations (version, name, note)
  values (73, 'realtime_announcements_branch_stock', 'added: ' || array_to_string(v_added, ','))
  on conflict (version) do update
    set applied_at = now(), applied_by = current_user, verified = true,
        note = case when array_length(v_added, 1) > 0
                    then excluded.note else public.schema_migrations.note end;
end $$;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Both are published (expect 2 rows):
--      select tablename from pg_publication_tables
--       where pubname = 'supabase_realtime' and schemaname = 'public'
--         and tablename in ('announcements', 'branch_stock')
--       order by 1;
-- 2. What this run added: select note from public.schema_migrations where version = 73;
-- 3. In the app: a cashier posts an announcement; the admin's
--    Announcements tab shows it within a few seconds, without reopening.
