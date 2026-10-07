-- ═══════════════════════════════════════════════════════════════════
-- Migration v4 — Purge stale quota triggers left over from the quota
-- system removal.
--
-- Symptom: PostgrestException 42703 — record "new" has no field
-- "quota_valid_until" — thrown on member updates (blocking member
-- edits and Verified Reseller promotion). Cause: the quota columns
-- were dropped, but one or more trigger functions that referenced
-- them survived on the live database.
--
-- This script finds EVERY trigger/function in public whose source
-- still references the removed quota columns, drops them, and prints
-- what it removed. Safe to re-run (a clean database drops nothing).
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  r record;
begin
  -- 1. Drop triggers whose function references the removed columns
  for r in
    select tg.tgname, cl.relname
    from pg_trigger tg
    join pg_class cl on cl.oid = tg.tgrelid
    join pg_namespace n on n.oid = cl.relnamespace
    join pg_proc p on p.oid = tg.tgfoid
    where not tg.tgisinternal
      and n.nspname = 'public'
      and (p.prosrc ilike '%quota_valid_until%'
        or p.prosrc ilike '%last_remittance_at%'
        or p.prosrc ilike '%adds_quota_time%')
  loop
    execute format('drop trigger %I on public.%I', r.tgname, r.relname);
    raise notice 'dropped trigger % on table %', r.tgname, r.relname;
  end loop;

  -- 2. Drop the now-orphaned trigger functions themselves
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.prosrc ilike '%quota_valid_until%'
        or p.prosrc ilike '%last_remittance_at%'
        or p.prosrc ilike '%adds_quota_time%')
  loop
    execute format('drop function if exists %s cascade', r.sig);
    raise notice 'dropped function %', r.sig;
  end loop;
end $$;

-- ── Verification (run after the block above) ───────────────────────
-- Both queries must return zero rows:
--
-- select p.proname
--   from pg_proc p
--   join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and p.prosrc ilike '%quota%';
--
-- select tg.tgname, cl.relname
--   from pg_trigger tg
--   join pg_class cl on cl.oid = tg.tgrelid
--   where not tg.tgisinternal and cl.relname = 'members';
