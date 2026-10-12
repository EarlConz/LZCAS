-- ═══════════════════════════════════════════════════════════════════
-- Rollback v70 — takes member_transactions back out of realtime, but only
-- if v70 is what added it (its ledger note says so).
-- ═══════════════════════════════════════════════════════════════════

do $$
begin
  if exists (select 1 from public.schema_migrations
              where version = 70 and note = 'added: member_transactions') then
    begin
      alter publication supabase_realtime drop table public.member_transactions;
    exception when undefined_object then
      null;
    end;
  end if;
end $$;

delete from public.schema_migrations where version = 70;
