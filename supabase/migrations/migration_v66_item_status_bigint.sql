-- ═══════════════════════════════════════════════════════════════════
-- Migration v66 — Edit Sale saves again (_item_status for bigint)
--
-- Requires v64.
--
-- Staging test X1/X2 (2026-10-03): Save changes in Edit Sale failed with
--   function public._item_status(bigint, text) does not exist
-- admin_edit_sale_group (v64) works out each product's change in stock
-- with sum(), and sum() of integers is a bigint, so `stock - delta` is a
-- bigint too. v64 only defined _item_status for an integer. POS checkout
-- (pos_record_sale) was never affected: its quantities are plain integers.
--
-- The fix adds the bigint version, which hands over to the integer one.
-- Postgres picks the exact type match, so every existing integer call
-- keeps using the original. admin_edit_sale_group itself is unchanged.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_item_status_bigint_v66.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public._item_status(p_stock bigint, p_category text)
returns text
language sql
stable
set search_path = public
as $$
  -- A stock past the integer range is not a real stock; clamp, don't fail.
  select public._item_status(least(greatest(p_stock, -2147483648), 2147483647)::integer, p_category);
$$;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (66, 'item_status_bigint')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Both versions exist (expect 2 rows: bigint, integer):
--      select pg_get_function_identity_arguments(oid)
--        from pg_proc where proname = '_item_status' order by 1;
-- 2. select public._item_status(3::bigint, null);   -- 'Low Stock'
-- 3. In the app (X1–X3): Transactions → a POS sale → Edit Sale → change a
--    quantity → Save changes. It saves, and the product's stock moves by
--    the difference.
