-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v41_saved_items_by_profile.sql
--
-- Restores `member_saved_items.member_id` and the v36 policies.
--
-- ── This LOSES branch cashier saves ────────────────────────────────
-- Rows belonging to a staff account have no member to map back to —
-- that is the entire reason v41 exists. They are DELETED here, because
-- the restored `member_id not null` cannot hold them and the restored
-- policies could never read them anyway. The count is reported first.
--
-- Member saves map back cleanly and are preserved.
-- ═══════════════════════════════════════════════════════════════════

alter table public.member_saved_items
  add column if not exists member_id bigint;

update public.member_saved_items s
   set member_id = p.member_id
  from public.profiles p
 where p.id = s.profile_id
   and p.member_id is not null;

do $$
declare
  staff_rows integer;
begin
  select count(*) into staff_rows
    from public.member_saved_items
   where member_id is null;

  if staff_rows > 0 then
    raise notice 'v41 rollback: deleting % saved item(s) belonging to accounts with no member row (branch cashiers).', staff_rows;
  end if;
end $$;

delete from public.member_saved_items where member_id is null;

alter table public.member_saved_items alter column member_id set not null;

drop index if exists public.uq_saved_announcement;
drop index if exists public.uq_saved_birthday;
drop index if exists public.idx_saved_profile;

create unique index if not exists uq_saved_announcement
  on public.member_saved_items (member_id, announcement_id)
  where item_kind = 'announcement';

create unique index if not exists uq_saved_birthday
  on public.member_saved_items (member_id, birthday_year)
  where item_kind = 'birthday';

create index if not exists idx_saved_member
  on public.member_saved_items (member_id, saved_at desc);

alter table public.member_saved_items drop column if exists profile_id;

-- Restore the v36 join-based policies.
drop policy if exists "saved_items_select" on public.member_saved_items;
create policy "saved_items_select" on public.member_saved_items
  for select to authenticated
  using (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );

drop policy if exists "saved_items_insert" on public.member_saved_items;
create policy "saved_items_insert" on public.member_saved_items
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );

drop policy if exists "saved_items_delete" on public.member_saved_items;
create policy "saved_items_delete" on public.member_saved_items
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );
