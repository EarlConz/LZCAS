-- migration_v10_category_thresholds.sql
-- Per-category Low Stock Threshold.
--
-- Each category carries its own low-stock threshold. Items whose category
-- does not match a category row (e.g. uncategorized) fall back to the
-- global app_config 'low_stock_threshold', then to 50.
--
-- A read-only view (items_with_status) computes each item's effective
-- threshold and status server-side, so the inventory list's status
-- filters and the low-stock counts stay correct across pagination.

-- 1. Per-category threshold column ------------------------------------------
alter table public.categories
  add column if not exists low_stock_threshold int;

-- Backfill existing categories from the current global default so no
-- category is left without a threshold (the app now requires one).
update public.categories
set low_stock_threshold = coalesce(
  (select value::int from public.app_config where key = 'low_stock_threshold'),
  50
)
where low_stock_threshold is null;

-- 2. Items-with-status view -------------------------------------------------
-- security_invoker = true → the view honours the caller's RLS on the
-- underlying tables (Supabase / PostgreSQL 15+).
create or replace view public.items_with_status
with (security_invoker = true) as
select
  i.*,
  coalesce(
    c.low_stock_threshold,
    (select value::int from public.app_config where key = 'low_stock_threshold'),
    50
  ) as effective_threshold,
  case
    when i.stock <= 0 then 'Out of Stock'
    when i.stock < coalesce(
      c.low_stock_threshold,
      (select value::int from public.app_config where key = 'low_stock_threshold'),
      50
    ) then 'Low Stock'
    else 'Good'
  end as stock_status
from public.items i
left join public.categories c on c.name = i.category;

-- Let the API roles read the view (RLS on the underlying items table is
-- still enforced because the view uses security_invoker).
grant select on public.items_with_status to authenticated, anon;
