-- ═══════════════════════════════════════════════════════════════════
-- Migration v19 — Group Sales frozen at purchase time
--
-- Problem: Group Sales was recomputed live as
--   (all downline product purchases) × the reseller's CURRENT package rate.
-- So upgrading re-priced every PAST purchase at the new rate — a purchase a
-- downline made while the reseller held Starter would suddenly pay the
-- Ambassador rate the moment they upgraded.
--
-- Fix: record each purchase's group-sales credit AT PURCHASE TIME, using the
-- reseller's package rate at that moment, as a member_transactions ledger row
-- (same pattern as the Upgrade Bonus). Earnings then just SUM those frozen
-- rows, so an upgrade only affects FUTURE purchases.
--
-- Triggers on public.sales keep the ledger in sync:
--   • INSERT / UPDATE → (re)record the frozen credits for that sale
--   • DELETE          → remove that sale's credits
-- (Edits go through delete+re-insert, so all edit paths are covered.)
--
-- NOTE: only applies to sales created AFTER this migration. Historical sales
-- have no frozen credit and contribute 0 until re-earned — intended on a
-- fresh reset DB.
--
-- Redefines get_member_earnings (supersedes v6/v15/v16/v18). Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Record/refresh a sale's frozen group-sales credits ────────────
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

-- ── 2. Remove a deleted sale's group-sales credits ───────────────────
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

-- ── 3. Wire up the triggers (idempotent) ─────────────────────────────
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

-- ── 4. Earnings: sum the FROZEN group-sales credits ──────────────────
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_has_pkg        boolean := false;
  v_pkg_direct     integer := 0;
  v_pkg_indirect   integer := 0;
  v_pkg_chairman   integer := 0;
  v_direct_count   integer := 0;
  v_indirect_count integer := 0;
  v_balance        integer := 0;
  v_indirect       integer := 0;
  v_passive        integer := 0;
  v_chairman       integer := 0;
  v_fridays        integer := 0;
  v_avail_ts       timestamptz;
  v_upgrade        integer := 0;
  v_total          integer := 0;
  v_earn_deduct    integer := 0;
  v_bal_deduct     integer := 0;
  v_now_manila     timestamp := (now() at time zone 'Asia/Manila');
begin
  -- ── Authorization: staff, or the member themselves ──────────────
  if not (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = p_member_id
    )
  ) then
    raise exception 'Not authorized to view these earnings';
  end if;

  -- ── This member's package bonuses (if any) ──────────────────────
  select p.direct_referral_bonus, p.indirect_referral_bonus,
         p.chairmans_bonus, true
    into v_pkg_direct, v_pkg_indirect, v_pkg_chairman, v_has_pkg
    from public.members m
    join public.packages p on p.id = m.package_id
    where m.id = p_member_id;
  if not found then
    v_has_pkg := false;
    v_pkg_direct := 0; v_pkg_indirect := 0; v_pkg_chairman := 0;
  end if;

  -- ── Direct + indirect referral counts ───────────────────────────
  select count(*) into v_direct_count
    from public.members where referrer_id = p_member_id;

  select count(*) into v_indirect_count
    from public.members
    where referrer_id in (
      select id from public.members where referrer_id = p_member_id
    );

  if v_has_pkg then
    v_balance  := v_direct_count * v_pkg_direct;      -- balance pool
    v_indirect := v_indirect_count * v_pkg_indirect;  -- indirect bonus
  end if;

  -- ── Group Sales (passive income): FROZEN at purchase time ───────
  -- Recorded by the sales triggers at each downline purchase using the
  -- reseller's package rate at that moment, so upgrading never re-prices
  -- past purchases. Just sum the ledger.
  select coalesce(sum(price), 0)
    into v_passive
    from public.member_transactions
    where member_id = p_member_id
      and item_name ilike 'Group Sales%';

  -- ── Chairman's Bonus: WEEKLY (every Friday) ─────────────────────
  if v_has_pkg and v_pkg_chairman > 0 then
    select min(s."timestamp") into v_avail_ts
      from public.sales s
      where s.buyer_id = p_member_id
        and s.package_id is not null
        and coalesce(s.item_name, '') not like 'Package Upgrade%';
    if v_avail_ts is null then
      select min(s."timestamp") into v_avail_ts
        from public.sales s where s.buyer_id = p_member_id;
    end if;

    if v_avail_ts is not null then
      v_fridays :=
          ((v_now_manila::date - date '2000-01-07') / 7)
        - (((v_avail_ts at time zone 'Asia/Manila')::date - date '2000-01-07') / 7);
      if v_fridays < 0 then v_fridays := 0; end if;
      v_chairman := v_fridays * v_pkg_chairman;
    end if;
  end if;

  -- ── Upgrade referral bonus: recorded by the upgrade RPC ─────────
  select coalesce(sum(price), 0)
    into v_upgrade
    from public.member_transactions
    where member_id = p_member_id
      and item_name ilike 'Upgrade Bonus%';

  -- Repeat Purchase was removed from the compensation plan (v18).
  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

  -- ── Subtract approved withdrawals per bucket ────────────────────
  select
    coalesce(sum(case when source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct
    from public.withdrawal_requests
    where member_id = p_member_id and status = 'approved';

  return jsonb_build_object(
    'totalEarnings',  greatest(0, v_total   - v_earn_deduct),
    'balance',        greatest(0, v_balance - v_bal_deduct),
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$$;
