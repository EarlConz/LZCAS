-- migration_v33_branch_stock_grants.sql
-- ---------------------------------------------------------------------------
-- Make branch stock readable by the app WITH RLS ENABLED.
--
-- Problem: as `authenticated`, count(*) on branch_stock returned 0 (no error) —
-- classic sign RLS is on with no policy, so every row is filtered out.
--
-- Model (reads only; ALL writes go through the SECURITY DEFINER RPCs, which run
-- as the table owner and bypass RLS — so no INSERT/UPDATE/DELETE policies are
-- needed, and direct client writes stay impossible):
--   * admin / main cashier (can_manage_branch_stock) -> see ALL branches
--   * a branch cashier                                -> see only their OWN rows
--
-- The view is security_invoker = true so the RLS below is enforced through it
-- (a branch cashier querying the view only ever gets their own rows).
--
-- Safe to re-run. Run AFTER migration_v30 (LAST of the branch-stock set).
-- ---------------------------------------------------------------------------

alter table public.branch_stock    enable row level security;
alter table public.stock_transfers enable row level security;

-- RLS filters on top of grants — the role still needs the base SELECT privilege.
grant select on public.branch_stock    to authenticated;
grant select on public.stock_transfers to authenticated;

-- ── branch_stock: owner sees own; admin/main-cashier see all ────────────────
drop policy if exists branch_stock_select on public.branch_stock;
create policy branch_stock_select on public.branch_stock
  for select to authenticated
  using (public.can_manage_branch_stock() or owner_id = auth.uid());

-- ── stock_transfers: recipient sees own; admin/main-cashier see all ─────────
drop policy if exists stock_transfers_select on public.stock_transfers;
create policy stock_transfers_select on public.stock_transfers
  for select to authenticated
  using (public.can_manage_branch_stock() or to_owner_id = auth.uid());

-- View reads base tables AS THE CALLER, so the RLS above applies through it.
create or replace view public.branch_stock_view
with (security_invoker = true) as
select
  bs.owner_id,
  i.id          as id,
  i.name        as name,
  i.category    as category,
  bs.quantity   as stock,
  bs.updated_at as last_updated,
  case
    when bs.quantity <= 0 then 'Out of Stock'
    when bs.quantity < coalesce(c.low_stock_threshold, 50) then 'Low Stock'
    else 'Good'
  end as status
from public.branch_stock bs
join public.items i on i.id = bs.item_id
left join public.categories c on c.name = i.category;

grant select on public.branch_stock_view to authenticated;
