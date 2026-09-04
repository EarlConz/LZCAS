-- ═══════════════════════════════════════════════════════════════════
-- Migration v38 — Member-facing cashier stock discovery
--
-- The member "Nearest Cashiers" screen needs to know, per located
-- cashier / branch cashier, whether that location currently has any
-- on-hand stock, and it shows the on-hand inventory list in the
-- inspection sheet.
--
-- Central stock (public.items) is already readable by any authenticated
-- user (enable_rls_staff.sql grants SELECT to everyone), but branch
-- allocations live in public.branch_stock whose RLS (migration v33)
-- restricts reads to admin/main-cashier and the branch cashier themself.
-- A member would therefore see every branch as empty.
--
-- This migration adds a SECURITY DEFINER function that returns each
-- branch cashier's on-hand lines to ANY authenticated caller, mirroring
-- the shape of branch_stock_view but readable by members. It exposes only
-- stock-on-hand (item name, category, quantity, status) — no transfer
-- audit data — which is exactly what the discovery screen needs to decide
-- "stocked vs out of stock" and render the inventory.
--
-- Regular (central-stock) cashiers are deliberately NOT covered here:
-- they all sell from the shared public.items catalog, which the app
-- already reads directly. hasStock for a regular cashier = any central
-- item with stock > 0.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_member_cashier_stock_v38.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.member_branch_stock()
returns table (
  owner_id  uuid,
  item_id   bigint,
  item_name text,
  category  text,
  quantity  integer,
  status    text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    bs.owner_id,
    i.id,
    i.name,
    i.category,
    bs.quantity,
    case
      when bs.quantity <= 0 then 'Out of Stock'
      when bs.quantity < coalesce(c.low_stock_threshold, 50) then 'Low Stock'
      else 'Good'
    end
  from public.branch_stock bs
  join public.items i on i.id = bs.item_id
  left join public.categories c on c.name = i.category
  order by i.name;
$$;

-- Only authenticated callers may execute it. Revoke the PUBLIC default so
-- the anon role (and any future role) cannot enumerate branch stock.
revoke all on function public.member_branch_stock() from public;
grant execute on function public.member_branch_stock() to authenticated;
