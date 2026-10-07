-- ═══════════════════════════════════════════════════════════════════
-- Migration v28 — Add the Branch Cashier staff role
--
-- Introduces a new login role, 'branch_cashier', treated as STAFF at the
-- database level. Its restriction to POS Terminal + Stocks on Hand is enforced
-- in the APP UI (routing + role visibility), not in RLS.
--
-- DB change is a single line: add 'branch_cashier' to is_staff(). Because
-- is_staff() gates every operational-table write (sales/items/stock_movements/
-- member_transactions/members/pending_requests) and the RPC auth checks, this
-- gives a branch cashier full staff DB access — enough to run POS and read
-- stock. The narrower surface is applied client-side.
--
-- ADDITIVE & SAFE: existing roles (admin/cashier/inventory pass; member/
-- reseller don't) behave identically. No account uses the new value until an
-- admin creates a branch_cashier login, so this has zero observable effect on
-- the live system when applied — it can go to prod ahead of the app release.
--
-- NOTE (future): to tighten to least privilege later, revert is_staff() to the
-- three back-office roles and add a separate is_pos_operator() applied only to
-- the POS tables' write policies. Not needed now.
--
-- Rollback: rollbacks/rollback_is_staff_v27.sql
-- ═══════════════════════════════════════════════════════════════════
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'cashier', 'inventory', 'branch_cashier')
  );
$$;
