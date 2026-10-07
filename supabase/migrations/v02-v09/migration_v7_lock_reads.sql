-- ═══════════════════════════════════════════════════════════════════
-- Migration v7 — Lock cross-member reads (CRITICAL-3, final step)
--
-- Tightens SELECT on members / sales / member_transactions from
-- "any logged-in user" to "staff OR the row's own member". Earnings are
-- now computed by get_member_earnings (migration_v6), a SECURITY DEFINER
-- RPC that reads the tree internally — so the member client no longer
-- needs to read anyone else's rows.
--
-- ⚠ RUN ONLY AFTER:
--   1. migration_v6_earnings_rpc.sql is applied, AND
--   2. the updated app build is deployed, AND
--   3. you've verified get_member_earnings returns the SAME numbers a
--      reseller saw before (open the earnings tab as a test reseller,
--      compare Total Earnings / Balance / each component).
--
-- Until all three are true, leave reads open — locking early would make
-- the earnings tab read as zero for members on the OLD app build.
--
-- Rollback: re-run the "_select ... using (true)" policies from
-- enable_rls_staff.sql for these three tables.
-- Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- ── members: staff, or the caller's own row ────────────────────────
drop policy if exists "members_select" on public.members;
create policy "members_select" on public.members
  for select to authenticated
  using (
    public.is_staff()
    or id = (select p.member_id from public.profiles p where p.id = auth.uid())
  );

-- ── sales: staff, or sales where the caller is the buyer ───────────
drop policy if exists "sales_select" on public.sales;
create policy "sales_select" on public.sales
  for select to authenticated
  using (
    public.is_staff()
    or buyer_id = (select p.member_id from public.profiles p where p.id = auth.uid())
  );

-- ── member_transactions: staff, or the caller's own ledger ─────────
drop policy if exists "member_transactions_select" on public.member_transactions;
create policy "member_transactions_select" on public.member_transactions
  for select to authenticated
  using (
    public.is_staff()
    or member_id = (select p.member_id from public.profiles p where p.id = auth.uid())
  );

-- ── Verify a reseller can no longer read the whole tree ────────────
-- As a logged-in NON-staff reseller, this must now return only their
-- own row(s), not every member:
--   select count(*) from public.members;   -- expect: 1 (self)
--   select count(*) from public.sales;      -- expect: only own purchases
