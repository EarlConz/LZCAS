-- ═══════════════════════════════════════════════════════════════════
-- Reseller Quota Compliance Subsystem — Database Layer
-- Safe to re-run. Designed to be sourced after schema.sql.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Schema: quota columns on members ──────────────────────────

alter table public.members
  add column if not exists quota_valid_until timestamptz;

alter table public.members
  add column if not exists last_remittance_at timestamptz;

-- Backfill: for existing verified resellers, set quota_valid_until
-- to 7 days from their most recent remittance, or 7 days from now.
update public.members m
set quota_valid_until = coalesce(
  (
    select max(b.settled_at)
    from public.borrows b
    where b.member_id = m.id
      and b.status = 'remitted'
  ),
  m.last_remittance_at,
  now()
) + interval '7 days'
where m.role = 'Verified Reseller'
  and m.quota_valid_until is null;

-- ── 2. System alerts table ──────────────────────────────────────

create table if not exists public.system_alerts (
  id bigint generated always as identity primary key,
  member_id bigint not null references public.members(id),
  alert_type text not null,            -- 'quota_overdue'
  severity text not null default 'warning', -- warning, critical
  title text not null,
  message text,
  is_active boolean not null default true,
  is_read boolean not null default false,
  snoozed_until timestamptz,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists idx_system_alerts_member
  on public.system_alerts (member_id, alert_type, is_active);

create index if not exists idx_system_alerts_active
  on public.system_alerts (alert_type, is_active)
  where is_active = true;

alter table public.system_alerts enable row level security;

drop policy if exists "system_alerts_read_authenticated" on public.system_alerts;
create policy "system_alerts_read_authenticated" on public.system_alerts
  for select to authenticated
  using (true);

drop policy if exists "system_alerts_insert_authenticated" on public.system_alerts;
create policy "system_alerts_insert_authenticated" on public.system_alerts
  for insert to authenticated
  with check (true);

drop policy if exists "system_alerts_update_authenticated" on public.system_alerts;
create policy "system_alerts_update_authenticated" on public.system_alerts
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "system_alerts_delete_admin" on public.system_alerts;
create policy "system_alerts_delete_admin" on public.system_alerts
  for delete to authenticated
  using (public.is_admin());

-- ── 3. Remittance trigger (category-gated stacking quota extension) ──
--
-- Fires whenever quantity_remitted increases on a borrows row.
-- Quota time is granted ONLY when the remitted item belongs to the
-- 'Box' category (case-insensitive). Remittances of any other
-- category process normally but leave quota_valid_until untouched.
--
-- Note: items stores the category NAME in the text column
-- items.category (there is no items.category_id FK), so the lookup
-- resolves the item first, then validates that name against the
-- categories table.

create or replace function public.handle_reseller_remittance_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_role text;
  v_category_name text;
  v_boxes_remitted integer;
  v_extension_weeks integer;
  v_base_date timestamptz;
  v_new_quota timestamptz;
begin
  -- Only act when the remitted count actually increased.
  v_boxes_remitted := new.quantity_remitted - coalesce(old.quantity_remitted, 0);
  if v_boxes_remitted <= 0 then
    return new;
  end if;

  -- Look up the member; only Verified Resellers are quota-tracked.
  select m.role, m.quota_valid_until
    into v_member_role, v_base_date
  from public.members m
  where m.id = new.member_id;

  if v_member_role is distinct from 'Verified Reseller' then
    return new;
  end if;

  -- CATEGORY GATE
  -- Step 1: use NEW.item_id to find the item's category name (text).
  -- Step 2: validate that name against the categories table, so only
  --         a registered category counts (freetext typos don't match).
  select c.name
    into v_category_name
  from public.items i
  join public.categories c
    on lower(trim(c.name)) = lower(trim(coalesce(i.category, '')))
  where i.id = new.item_id;

  if lower(trim(coalesce(v_category_name, ''))) = 'box' then
    -- Extension: 1 box = 1 week, 2 = 2 weeks, 3 = 3 weeks, 4+ = 4 weeks
    v_extension_weeks := least(v_boxes_remitted, 4);

    -- Base date: if quota already expired (or unset), start from now
    if v_base_date is null or v_base_date < now() then
      v_base_date := now();
    end if;

    v_new_quota := v_base_date + make_interval(weeks => v_extension_weeks);

    -- Hard cap: never more than 4 weeks out from now
    if v_new_quota > (now() + interval '4 weeks') then
      v_new_quota := now() + interval '4 weeks';
    end if;

    update public.members
    set quota_valid_until = v_new_quota,
        last_remittance_at = now()
    where id = new.member_id;

    -- Remitting boxes cures delinquency: retire active overdue alerts
    update public.system_alerts
    set is_active = false
    where member_id = new.member_id
      and alert_type = 'quota_overdue'
      and is_active = true;
  end if;

  -- Non-'Box' categories fall through: remittance saves, quota untouched.
  return new;
end;
$$;

-- Attach trigger to borrows table. The WHEN clause skips the function
-- entirely unless quantity_remitted increased.
drop trigger if exists trg_reseller_remittance_quota on public.borrows;
create trigger trg_reseller_remittance_quota
  after update on public.borrows
  for each row
  when (new.quantity_remitted > coalesce(old.quantity_remitted, 0))
  execute function public.handle_reseller_remittance_quota();

-- ── 4. Nightly quota check function ──────────────────────────────

create or replace function public.check_reseller_quotas()
returns integer as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select m.id, m.first_name, m.last_name, m.quota_valid_until
    from public.members m
    where m.role = 'Verified Reseller'
      and m.quota_valid_until < now()
      and not exists (
        -- Don't create duplicate active alerts
        select 1 from public.system_alerts sa
        where sa.member_id = m.id
          and sa.alert_type = 'quota_overdue'
          and sa.is_active = true
      )
  loop
    insert into public.system_alerts (
      member_id, alert_type, severity, title, message
    ) values (
      r.id,
      'quota_overdue',
      case
        when r.quota_valid_until < (now() - interval '2 weeks') then 'critical'
        else 'warning'
      end,
      'Quota Overdue — ' || coalesce(r.first_name || ' ', '') || coalesce(r.last_name, 'Reseller #' || r.id),
      'Weekly box remittance quota expired on '
        || to_char(r.quota_valid_until, 'Mon DD, YYYY')
        || '. This reseller is now '
        || extract(day from now() - r.quota_valid_until)::text
        || ' day(s) overdue.'
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$ language plpgsql security definer;

-- ── 5. pg_cron: schedule nightly check (midnight UTC) ──────────

-- Requires pg_cron extension (enable via Supabase Dashboard → Extensions)
create extension if not exists pg_cron with schema extensions;

select cron.schedule(
  'check_reseller_quotas_midnight',
  '0 0 * * *',          -- every night at midnight UTC
  $$ select public.check_reseller_quotas(); $$
);

-- ── 6. Helper: trigger check manually (for testing) ─────────────

-- Run this to test the function immediately:
--   select public.check_reseller_quotas();

-- View all active quota alerts:
--   select * from public.system_alerts where alert_type = 'quota_overdue' and is_active = true;
