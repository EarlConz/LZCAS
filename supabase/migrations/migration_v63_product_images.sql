-- ═══════════════════════════════════════════════════════════════════
-- Migration v63 — A picture for each product
--
-- Client feedback (2026-10-02): admins add, replace and remove product
-- pictures, and the Marketplace shows them.
--
-- ── 1. items.image_path ────────────────────────────────────────────
-- The storage object path, not a URL (same as announcements, v44). Null
-- means no picture: the app shows the product's letter tile instead.
--
-- ── 2. items_with_status, rebuilt ──────────────────────────────────
-- The view selects i.*, but Postgres fixes a view's columns when it is
-- created, so the new column would not appear in it. The inventory list
-- reads the view. A plain "create or replace" cannot add a column in the
-- middle, so it is dropped and created again with the same definition
-- and the same grant (v11).
--
-- ── 3. A PUBLIC 'product-images' bucket ────────────────────────────
-- Unlike announcement posters, a product picture is not for one audience:
-- every member who can open the Marketplace sees every product. A public
-- bucket needs no signed URL, so pictures load straight from the CDN and
-- the app caches them by URL. File names are random, so a replaced picture
-- gets a new URL and nothing stale is ever served.
-- Writes are admins only, like the rest of the product settings screens.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_product_images_v63.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. The column ──────────────────────────────────────────────────
alter table public.items
  add column if not exists image_path text;

-- ── 2. The view ────────────────────────────────────────────────────
drop view if exists public.items_with_status;

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

-- ── 3. The bucket ──────────────────────────────────────────────────
-- 5 MB and images only. The app sends about 100 KB (800 px JPEG), so the
-- limit only stops something that did not come from the app.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880,
        array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "product-images write"  on storage.objects;
drop policy if exists "product-images update" on storage.objects;
drop policy if exists "product-images delete" on storage.objects;

-- No read policy: a public bucket serves its files by URL to anyone.
create policy "product-images write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());

create policy "product-images update" on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.is_admin())
  with check (bucket_id = 'product-images' and public.is_admin());

-- A replaced or removed picture's file is deleted, so it does not pay for
-- storage forever.
create policy "product-images delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (63, 'product_images')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- select
--   (select count(*) from information_schema.columns
--     where table_schema='public' and table_name='items'
--       and column_name='image_path')                      as items_column,
--   (select count(*) from information_schema.columns
--     where table_schema='public' and table_name='items_with_status'
--       and column_name='image_path')                      as view_column,
--   (select public from storage.buckets
--     where id='product-images')                           as bucket_public,
--   (select count(*) from pg_policies
--     where schemaname='storage' and policyname like 'product-images%') as policies;
-- Expect 1, 1, true, 3.
