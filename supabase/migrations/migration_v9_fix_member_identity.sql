-- ═══════════════════════════════════════════════════════════════════
-- Migration v9 — Fix member identity mapping for withdrawals
--
-- get_current_member_id() resolved auth.uid() against members.user_id,
-- but members.user_id holds the STAFF CREATOR's id, never the member's
-- own auth id. So for a logged-in member the function returned NULL,
-- which made the withdrawal_requests RLS policies (submit + view own)
-- fail — members could not request or see their own withdrawals.
--
-- Fix: map via profiles.member_id, the same auth.uid() -> member link
-- the rest of the app already uses (fetchMemberByAuthUserId, the
-- members/earnings_history self policies, get_member_earnings).
--
-- Only the withdrawal_requests policies call this helper, so redefining
-- it has no other side effects. Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.get_current_member_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select member_id
  from public.profiles
  where id = auth.uid()
  limit 1;
$$;

-- ── Ledger ─────────────────────────────────────────────────────────
-- Added 2026-09-23. v45 could only ASSUME this file had run (its backfill
-- row is verified = false), and staging was later found serving the old
-- definition because schema.sql still carried it — a combination that
-- reads as "applied" while withdrawals are broken. Re-running this file
-- now records itself as verified, so the ledger stops being optimistic.
-- Guarded for a database that predates the ledger.
do $$
begin
  if to_regclass('public.schema_migrations') is not null then
    insert into public.schema_migrations (version, name)
    values (9, 'fix_member_identity')
    on conflict (version) do update
      set applied_at = now(), applied_by = current_user, verified = true;
  end if;
end $$;

-- ── Verify ─────────────────────────────────────────────────────────
-- The body must read profiles.member_id, never members.user_id:
--   select pg_get_functiondef(p.oid)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'get_current_member_id';
--
-- Then in the app: as a member with a balance, submit a withdrawal. It
-- succeeds, and the request appears in the admin's pending list.
