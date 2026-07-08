-- ═══════════════════════════════════════════════════════════════════
-- Category-Gated Quota Extension — Migration
-- Safe to re-run. Designed to be sourced after schema.sql and
-- schema_quota.sql.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Add adds_quota_time flag to categories ────────────────────

alter table public.categories
  add column if not exists adds_quota_time boolean not null default false;

-- ── 2. Replace the remittance trigger with category-aware logic ──
--     Instead of hardcoding 'Box', the trigger reads
--     categories.adds_quota_time and only extends the quota when
--     that flag is true.

create or replace function public.handle_reseller_remittance_quota()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_role       text;
  v_adds_quota_time   boolean;
  v_quantity_increase integer;
  v_extension_weeks   integer;
  v_base_date         timestamptz;
  v_new_quota         timestamptz;
begin
  -- Only act when the remitted count actually increased.
  v_quantity_increase := new.quantity_remitted
                         - coalesce(old.quantity_remitted, 0);
  if v_quantity_increase <= 0 then
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

  --
  -- DYNAMIC CATEGORY GATE
  -- Use NEW.item_id to join items → categories and read the
  -- adds_quota_time flag.  If the flag is false (or the category
  -- isn't found), skip extension entirely.
  --
  select c.adds_quota_time
    into v_adds_quota_time
  from public.items i
  join public.categories c
    on lower(trim(c.name)) = lower(trim(coalesce(i.category, '')))
  where i.id = new.item_id;

  -- Guard: exit cleanly when the category does not grant quota time
  if v_adds_quota_time is not true then
    return new;
  end if;

  -- Extension: 1 box = 1 week, 2 = 2 weeks, 3 = 3 weeks, 4+ = 4 weeks
  v_extension_weeks := least(v_quantity_increase, 4);

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
  set quota_valid_until  = v_new_quota,
      last_remittance_at = now()
  where id = new.member_id;

  -- Remitting quota-qualifying items cures delinquency
  update public.system_alerts
  set is_active = false
  where member_id  = new.member_id
    and alert_type = 'quota_overdue'
    and is_active  = true;

  return new;
end;
$$;

-- Re-attach the trigger (idempotent)
drop trigger if exists trg_reseller_remittance_quota on public.borrows;
create trigger trg_reseller_remittance_quota
  after update on public.borrows
  for each row
  when (new.quantity_remitted > coalesce(old.quantity_remitted, 0))
  execute function public.handle_reseller_remittance_quota();
