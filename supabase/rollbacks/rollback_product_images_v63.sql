-- ═══════════════════════════════════════════════════════════════════
-- Rollback v63 — product pictures
--
-- Drops the column (every product loses its picture link), rebuilds
-- items_with_status without it, and removes the bucket's write policies.
--
-- The bucket itself is left in place: Supabase refuses to delete a bucket
-- that still has files. To remove it, empty it in Storage, then delete it
-- there. With the policies gone nobody can upload to it meanwhile.
--
-- Run the app version from before v63 after this, or pictures will fail
-- to save (the app falls back to letter tiles when reading).
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "product-images write"  on storage.objects;
drop policy if exists "product-images update" on storage.objects;
drop policy if exists "product-images delete" on storage.objects;

drop view if exists public.items_with_status;

alter table public.items
  drop column if exists image_path;

create view public.items_with_status
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

delete from public.schema_migrations where version = 63;

notify pgrst, 'reload schema';
