-- ═══════════════════════════════════════════════════════════════════
-- Migration v12 — Package-based reseller status (drop ID verification)
--
-- Reseller status is now derived purely from package availment:
--   package_id IS NOT NULL  → 'Verified Reseller'
--   package_id IS NULL      → 'Member'
--
-- This migration:
--   1. Re-derives member roles + linked login roles from package_id.
--   2. Adds an RPC to sync a member's login role when their package
--      changes at edit time.
--   3. Drops the now-unused ID columns and the member-ids storage bucket
--      (files + policies).
--
-- Requires is_staff() (enable_rls_staff.sql). Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Re-derive member roles from package (preserve any exotic roles). ──
update public.members
set role = case
             when package_id is not null then 'Verified Reseller'
             else 'Member'
           end
where role in ('Member', 'Verified Reseller') or role is null;

-- 2. Sync existing login accounts to match (never touch staff roles). ──
update public.profiles p
set role = case
             when m.package_id is not null then 'reseller'
             else 'member'
           end
from public.members m
where p.member_id = m.id
  and p.role in ('member', 'reseller');

-- 3. RPC: sync a member's login role when their package changes. ───────
create or replace function public.set_member_account_role(
  p_member_id bigint,
  p_is_reseller boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required';
  end if;

  update public.profiles
  set role = case when p_is_reseller then 'reseller' else 'member' end
  where member_id = p_member_id
    and role in ('member', 'reseller');  -- never demote/alter staff
end;
$$;

grant execute on function public.set_member_account_role(bigint, boolean)
  to authenticated;

-- 4. Drop the ID verification columns. ────────────────────────────────
alter table public.members
  drop column if exists id_type,
  drop column if exists id_number,
  drop column if exists id_image_path;

-- 5. Drop the member-ids storage policies (RLS on storage.objects). ────
-- NOTE: The bucket ITSELF and its files cannot be removed from SQL —
-- Supabase blocks direct deletes on storage tables (protect_delete()).
-- After running this migration, delete the bucket manually in the
-- Supabase Dashboard:  Storage → member-ids → ⋯ → Delete bucket.
drop policy if exists "member-ids read"   on storage.objects;
drop policy if exists "member-ids write"  on storage.objects;
drop policy if exists "member-ids update" on storage.objects;

-- ── Verify ─────────────────────────────────────────────────────────
-- select role, count(*) from public.members group by role;
