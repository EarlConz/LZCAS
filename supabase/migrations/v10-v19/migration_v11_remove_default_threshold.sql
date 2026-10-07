-- migration_v11_remove_default_threshold.sql
-- Retire the global/default low-stock threshold. Every category now carries
-- its own required threshold; only uncategorized items (legacy / CSV-imported
-- rows whose category matches no category row) fall back to a fixed 50.
--
-- Run AFTER migration_v10_category_thresholds.sql.

create or replace view public.items_with_status
with (security_invoker = true) as
select
  i.*,
  coalesce(c.low_stock_threshold, 50) as effective_threshold,
  case
    when i.stock <= 0 then 'Out of Stock'
    when i.stock < coalesce(c.low_stock_threshold, 50) then 'Low Stock'
    else 'Good'
  end as stock_status
from public.items i
left join public.categories c on c.name = i.category;

grant select on public.items_with_status to authenticated, anon;

-- Drop the now-unused global default (safe if the key doesn't exist).
delete from public.app_config where key = 'low_stock_threshold';
