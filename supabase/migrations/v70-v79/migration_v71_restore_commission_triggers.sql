-- ═══════════════════════════════════════════════════════════════════
-- Migration v71 — Restore the commission triggers (Group Sales and
--                 referral bonuses)
--
-- Requires the packages columns from v16–v27 (they are there: the app
-- reads them). Safe to re-run, and safe on a database that already has
-- all of this: every function is CREATE OR REPLACE with the same body,
-- and every trigger is dropped and created again, identically.
--
-- Found 2026-10-05 (Part 4: G2, X3, X6): staging has NO triggers on
-- public.sales. Staging was built from schema/schema.sql, which never had
-- the earnings chain, and v45 recorded v19–v27 on it as "ASSUMED, not
-- detected". So on staging:
--   • no product sale, in store or delivered, ever paid Group Sales;
--   • no first package availment paid Direct/Indirect Referral or
--     Chairman's Bonus (e.g. sale 42: ₱300 Direct Referral never paid);
--   • package upgrades may have failed (process_package_upgrade).
--
-- This re-creates, from the migration that LAST defined each one, copied
-- verbatim:
--   v19  sync_group_sales_for_sale, remove_group_sales_for_sale
--   v25  first_availed_package, first_availment_ts, package_held_at
--   v26  process_package_upgrade
--   v27  referral_bonus_min_tier, crystallize_referral_on_availment
-- and the four triggers on sales. It does NOT re-run those migrations'
-- one-off backfills and recalculations, and does NOT touch
-- get_member_earnings (v56 owns it). It pays nothing for past sales:
-- see supabase/maintenance/backfill_missed_commissions_staging.sql.
--
-- Production: check first with section 1 of
-- supabase/diagnostics/diagnose_recent_commissions.sql. If it lists the
-- four triggers, production does not need this (running it anyway changes
-- nothing).
--
-- Rollback: supabase/rollbacks/rollback_restore_commission_triggers_v71.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── sync_group_sales_for_sale (as last defined in v19) ──
create or replace function public.sync_group_sales_for_sale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_direct_ref   bigint;
  v_indirect_ref bigint;
  v_rate         integer;
begin
  -- Clear any existing credits tied to this sale (re-sync on UPDATE).
  delete from public.member_transactions
    where sale_id = NEW.id and item_name like 'Group Sales%';

  -- Only product sales (not package availments) with a real buyer + qty.
  if NEW.package_id is not null
     or coalesce(NEW.quantity, 0) <= 0
     or NEW.buyer_id is null then
    return NEW;
  end if;

  -- Level 1 — the buyer's DIRECT referrer, paid at THEIR current rate.
  select referrer_id into v_direct_ref
    from public.members where id = NEW.buyer_id;

  if v_direct_ref is not null then
    select coalesce(p.group_sales_direct, 0) into v_rate
      from public.members m
      left join public.packages p on p.id = m.package_id
      where m.id = v_direct_ref;

    if coalesce(v_rate, 0) > 0 then
      insert into public.member_transactions
        (user_id, member_id, sale_id, item_name, quantity, price, timestamp)
      values
        (NEW.user_id, v_direct_ref, NEW.id, 'Group Sales (Direct)',
         NEW.quantity, v_rate * NEW.quantity, NEW."timestamp");
    end if;

    -- Level 2 — the direct referrer's referrer (indirect).
    select referrer_id into v_indirect_ref
      from public.members where id = v_direct_ref;

    if v_indirect_ref is not null then
      select coalesce(p.group_sales_indirect, 0) into v_rate
        from public.members m
        left join public.packages p on p.id = m.package_id
        where m.id = v_indirect_ref;

      if coalesce(v_rate, 0) > 0 then
        insert into public.member_transactions
          (user_id, member_id, sale_id, item_name, quantity, price, timestamp)
        values
          (NEW.user_id, v_indirect_ref, NEW.id, 'Group Sales (Indirect)',
           NEW.quantity, v_rate * NEW.quantity, NEW."timestamp");
      end if;
    end if;
  end if;

  return NEW;
end;
$$;

-- ── remove_group_sales_for_sale (as last defined in v19) ──
create or replace function public.remove_group_sales_for_sale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.member_transactions
    where sale_id = OLD.id and item_name like 'Group Sales%';
  return OLD;
end;
$$;

-- ── first_availed_package (as last defined in v25) ──
create or replace function public.first_availed_package(p_member bigint)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select s.package_id
  from public.sales s
  where s.buyer_id = p_member and s.package_id is not null
  order by s."timestamp" asc, s.id asc
  limit 1
$$;

-- ── first_availment_ts (as last defined in v25) ──
create or replace function public.first_availment_ts(p_member bigint)
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select s."timestamp"
  from public.sales s
  where s.buyer_id = p_member and s.package_id is not null
  order by s."timestamp" asc, s.id asc
  limit 1
$$;

-- ── package_held_at (as last defined in v25) ──
create or replace function public.package_held_at(p_member bigint, p_ts timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select s.package_id
  from public.sales s
  where s.buyer_id = p_member and s.package_id is not null
    and s."timestamp" <= p_ts
  order by s."timestamp" desc, s.id desc
  limit 1
$$;

-- ── referral_bonus_min_tier (as last defined in v27) ──
create or replace function public.referral_bonus_min_tier(
  p_earner_pkg   bigint,
  p_referral_pkg bigint,
  p_kind         text
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r_earner   integer;
  r_referral integer;
  chosen_pkg bigint;
  amt        integer;
begin
  if p_earner_pkg is null or p_referral_pkg is null then
    return 0;
  end if;

  select hierarchy_rank into r_earner   from public.packages where id = p_earner_pkg;
  select hierarchy_rank into r_referral from public.packages where id = p_referral_pkg;

  chosen_pkg := case
    when coalesce(r_referral, 0) < coalesce(r_earner, 0) then p_referral_pkg
    else p_earner_pkg
  end;

  select case p_kind
           when 'indirect' then indirect_referral_bonus
           when 'upgrade'  then upgrade_referral_bonus
           when 'chairman' then chairmans_bonus
           else direct_referral_bonus
         end
    into amt
    from public.packages where id = chosen_pkg;

  return coalesce(amt, 0);
end;
$$;

-- ── crystallize_referral_on_availment (as last defined in v27) ──
create or replace function public.crystallize_referral_on_availment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.package_id is null then
    return NEW;
  end if;

  if exists (
    select 1 from public.sales s
    where s.buyer_id = NEW.buyer_id
      and s.package_id is not null
      and s.id <> NEW.id
      and (s."timestamp" < NEW."timestamp"
           or (s."timestamp" = NEW."timestamp" and s.id < NEW.id))
  ) then
    return NEW;
  end if;

  -- ═══ SIDE R — this member is the referral; pay their uplines ═══

  -- L1 Direct Referral (min-tier)
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a1.user_id, a1.id, NEW.buyer_id, 'Direct Referral', 1,
         public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'direct'),
         NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  where m.id = NEW.buyer_id
    and a1.is_deleted = false
    and a1.package_id is not null
    and public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'direct') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a1.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Direct Referral%');

  -- L1 Chairman's Bonus (MIN-TIER)
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a1.user_id, a1.id, NEW.buyer_id, 'Chairman Bonus', 1,
         public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'chairman'),
         NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  where m.id = NEW.buyer_id
    and a1.is_deleted = false
    and a1.package_id is not null
    and public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'chairman') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a1.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Chairman Bonus%');

  -- L2 Indirect Referral (min-tier)
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a2.user_id, a2.id, NEW.buyer_id, 'Indirect Referral', 1,
         public.referral_bonus_min_tier(a2.package_id, NEW.package_id, 'indirect'),
         NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  join public.members a2 on a2.id = a1.referrer_id
  where m.id = NEW.buyer_id
    and a2.is_deleted = false
    and a2.package_id is not null
    and public.referral_bonus_min_tier(a2.package_id, NEW.package_id, 'indirect') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a2.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Indirect Referral%');

  -- ═══ SIDE A — catch-up: this member now holds a package ═══

  -- Direct for already-availed direct downlines (min-tier)
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, d.id, 'Direct Referral', 1,
         public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'direct'),
         NEW."timestamp"
  from public.members m
  join public.members d on d.referrer_id = NEW.buyer_id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and public.first_availed_package(d.id) is not null
    and public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'direct') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = d.id
                      and t.item_name ilike 'Direct Referral%');

  -- Chairman for M (MIN-TIER), one per already-availed direct downline
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, d.id, 'Chairman Bonus', 1,
         public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'chairman'),
         NEW."timestamp"
  from public.members m
  join public.members d on d.referrer_id = NEW.buyer_id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and public.first_availed_package(d.id) is not null
    and public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'chairman') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = d.id
                      and t.item_name ilike 'Chairman Bonus%');

  -- Indirect for already-availed grand-downlines (min-tier)
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, e.id, 'Indirect Referral', 1,
         public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(e.id), 'indirect'),
         NEW."timestamp"
  from public.members m
  join public.members d on d.referrer_id = NEW.buyer_id
  join public.members e on e.referrer_id = d.id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and e.is_deleted = false
    and public.first_availed_package(e.id) is not null
    and public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(e.id), 'indirect') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = e.id
                      and t.item_name ilike 'Indirect Referral%');

  return NEW;
end;
$$;

-- ── process_package_upgrade (as last defined in v26) ──
create or replace function public.process_package_upgrade(
  p_member_id bigint,
  p_target_package_id bigint
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_rank     integer;
  v_target_rank      integer;
  v_target_name      text;
  v_target_price     integer;
  v_upgrade_bonus    integer := 0;
  v_referrer_id      bigint;
  v_referrer_pkg     bigint;
  v_last             record;
begin
  -- 0. Authorization
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to process an upgrade';
  end if;

  -- 1. Lock the member row
  perform 1 from public.members where id = p_member_id for update;
  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 1b. Must have a login account
  if not exists (select 1 from public.profiles where member_id = p_member_id) then
    raise exception
      'Member % has no login account; create one before availing a package',
      p_member_id;
  end if;

  -- 2. Current rank (0 if no package)
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  -- 3. Target package
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price
    into v_target_rank, v_target_name, v_target_price
    from public.packages pkgs
    where pkgs.id = p_target_package_id;
  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 4. Upgrade-only: target must be a strictly higher tier
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 5. Change the member's package
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 5b. Role follows the package
  update public.members
    set role = 'Verified Reseller'
    where id = p_member_id
      and (role in ('Member', 'Verified Reseller') or role is null);

  update public.profiles p
    set role = 'reseller'
    where p.member_id = p_member_id
      and p.role in ('member', 'reseller');

  -- 6. Direct referrer + their package
  select m.referrer_id into v_referrer_id
    from public.members m where m.id = p_member_id;

  if v_referrer_id is not null then
    select rm.package_id into v_referrer_pkg
      from public.members rm where rm.id = v_referrer_id;

    -- 6b. MIN-TIER: upgrade bonus = upgrade_referral_bonus of the lower-tier
    --     package between the referrer's own package and the target package
    --     the downline upgraded to. (Consistent with Direct/Indirect v25.)
    v_upgrade_bonus := public.referral_bonus_min_tier(
                         v_referrer_pkg, p_target_package_id, 'upgrade');
  end if;

  -- 7. Pay ONLY for a genuine upgrade (member already held a package)
  if v_referrer_id is not null
     and v_current_rank > 0
     and coalesce(v_upgrade_bonus, 0) > 0 then

    insert into public.member_transactions (
      user_id, member_id, item_name, quantity, price, timestamp
    ) values (
      auth.uid(), v_referrer_id,
      'Upgrade Bonus — ' || v_target_name, 1, v_upgrade_bonus, now()
    );

    select total_earnings, balance,
           indirect_bonus, group_sales, passive_income,
           repeat_purchase, chairman_bonus, upgrade_bonus
      into v_last
      from public.earnings_history
      where member_id = v_referrer_id
      order by recorded_at desc
      limit 1;

    insert into public.earnings_history (
      member_id, total_earnings, balance,
      earnings_delta, balance_delta,
      indirect_bonus, group_sales, passive_income,
      repeat_purchase, chairman_bonus, upgrade_bonus
    ) values (
      v_referrer_id,
      coalesce(v_last.total_earnings, 0) + v_upgrade_bonus,
      coalesce(v_last.balance, 0),
      v_upgrade_bonus, 0,
      coalesce(v_last.indirect_bonus, 0),
      coalesce(v_last.group_sales, 0),
      coalesce(v_last.passive_income, 0),
      coalesce(v_last.repeat_purchase, 0),
      coalesce(v_last.chairman_bonus, 0),
      coalesce(v_last.upgrade_bonus, 0) + v_upgrade_bonus
    );
  end if;
end;
$$;

-- ── Triggers on sales (v19, v27) ───────────────────────────────────
drop trigger if exists trg_sync_group_sales_ins on public.sales;
create trigger trg_sync_group_sales_ins
  after insert on public.sales
  for each row execute function public.sync_group_sales_for_sale();

drop trigger if exists trg_sync_group_sales_upd on public.sales;
create trigger trg_sync_group_sales_upd
  after update on public.sales
  for each row execute function public.sync_group_sales_for_sale();

drop trigger if exists trg_remove_group_sales_del on public.sales;
create trigger trg_remove_group_sales_del
  after delete on public.sales
  for each row execute function public.remove_group_sales_for_sale();

drop trigger if exists trg_crystallize_referral_on_availment on public.sales;
create trigger trg_crystallize_referral_on_availment
  after insert on public.sales
  for each row execute function public.crystallize_referral_on_availment();

-- v25: registration no longer pays referral bonuses; availment does.
drop trigger if exists trg_record_referral_bonus on public.members;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (71, 'restore_commission_triggers')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Four triggers on sales, all enabled (tgenabled = 'O'):
--      select tgname, tgenabled from pg_trigger
--       where tgrelid = 'public.sales'::regclass and not tgisinternal
--       order by tgname;
-- 2. Sell 1 product at the POS to a member whose referrer holds a
--    package: a 'Group Sales (Direct)' row appears for the referrer
--    (section 4 of diagnose_recent_commissions.sql).
