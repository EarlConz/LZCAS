-- ═══════════════════════════════════════════════════════════════════
-- Migration v70 — A member's earnings update on their phone by themselves
--
-- Requires nothing new. Safe to re-run.
--
-- Part 4 (2026-10-05, G2): a referrer watching their phone saw nothing
-- happen when a downline bought, because nothing told the phone. The
-- commission rows are written in the database by triggers on `sales`
-- (v19 Group Sales, v25–v27 referral bonuses), and a member's phone never
-- hears about another member's sale: row-level security only lets them
-- read their own purchases. Their own ledger, `member_transactions`, they
-- can read (v7), but it was never in the realtime publication.
--
-- This adds `member_transactions` to `supabase_realtime`. Each viewer
-- still receives only the rows v7's policy lets them read: a member their
-- own commissions and payments, staff everyone's.
--
-- Rollback: supabase/rollbacks/rollback_realtime_member_transactions_v70.sql
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  v_added boolean := false;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise notice 'No supabase_realtime publication here; nothing to do.';
    return;
  end if;
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public' and tablename = 'member_transactions'
  ) then
    alter publication supabase_realtime add table public.member_transactions;
    v_added := true;
  end if;

  -- The rollback reads this: it only removes what this migration added.
  insert into public.schema_migrations (version, name, note)
  values (70, 'realtime_member_transactions',
          case when v_added then 'added: member_transactions' else 'added: ' end)
  on conflict (version) do update
    set applied_at = now(), applied_by = current_user, verified = true,
        note = case when v_added then excluded.note else public.schema_migrations.note end;
end $$;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Published (expect 1 row):
--      select tablename from pg_publication_tables
--       where pubname = 'supabase_realtime' and tablename = 'member_transactions';
-- 2. In the app: a referrer's Earnings open on their phone; their downline
--    buys at the counter. Within a few seconds the Group Sales figure and
--    "Where your earnings came from" show the new credit, without reopening.
