-- ═══════════════════════════════════════════════════════════════════
-- Migration v24 — Chairman's Bonus becomes a FROZEN LEDGER
--
-- Until now Chairman's Bonus was the only bonus computed LIVE by the earnings
-- RPC (it read packages.chairmans_bonus every time). That meant editing a
-- package's chairman rate would retroactively change every past referral's
-- chairman. This migration makes Chairman behave exactly like the other four
-- bonuses: a member_transactions ledger row is written the moment it's earned,
-- at the rate in effect then, and the RPC just SUMS those rows. Editing a
-- package rate afterwards no longer changes history.
--
-- One "Chairman Bonus" row is written per DIRECT REFERRAL (the referrer earns
-- one chairman payment each time they recruit someone), priced at the
-- referrer's package chairmans_bonus at that moment — identical to the v23
-- live logic, just frozen into a row.
--
-- Three parts, run together as one script:
--   1. TRIGGER — future referrals write a frozen "Chairman Bonus" row.
--   2. BACKFILL — create those rows for all existing referrals (same rate v23
--      computes now), so no member's total changes at cutover. Idempotent.
--   3. RPC — sum the "Chairman Bonus" ledger instead of computing live.
--
-- Safe on live: values are unchanged at cutover; only the source (stored vs
-- recomputed) changes. DB-only — no app rebuild (same return keys).
--
-- Rollback: supabase/rollback_get_member_earnings_v24.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. TRIGGER: write Direct + Chairman + Indirect ledger rows ────────
create or replace function public.record_referral_bonus_on_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_l2       bigint;
  v_direct   integer;
  v_chairman integer;
  v_indirect integer;
begin
  if NEW.referrer_id is null then
    return NEW;
  end if;

  -- Direct referrer's package rates, frozen at this moment.
  select coalesce(p.direct_referral_bonus, 0), coalesce(p.chairmans_bonus, 0)
    into v_direct, v_chairman
    from public.members m
    left join public.packages p on p.id = m.package_id
    where m.id = NEW.referrer_id;

  -- Level 1 — Direct Referral Bonus (Balance wallet).
  if coalesce(v_direct, 0) > 0 then
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    values
      (NEW.user_id, NEW.referrer_id, NEW.id, 'Direct Referral', 1, v_direct, now());
  end if;

  -- Level 1 — Chairman's Bonus: one per direct referral, frozen at the
  -- referrer's current package rate (Total Earnings wallet).
  if coalesce(v_chairman, 0) > 0 then
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    values
      (NEW.user_id, NEW.referrer_id, NEW.id, 'Chairman Bonus', 1, v_chairman, now());
  end if;

  -- Level 2 — Indirect Referral Bonus.
  select referrer_id into v_l2 from public.members where id = NEW.referrer_id;
  if v_l2 is not null then
    select coalesce(p.indirect_referral_bonus, 0) into v_indirect
      from public.members m
      left join public.packages p on p.id = m.package_id
      where m.id = v_l2;

    if coalesce(v_indirect, 0) > 0 then
      insert into public.member_transactions
        (user_id, member_id, item_id, item_name, quantity, price, timestamp)
      values
        (NEW.user_id, v_l2, NEW.id, 'Indirect Referral', 1, v_indirect, now());
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_record_referral_bonus on public.members;
create trigger trg_record_referral_bonus
  after insert on public.members
  for each row execute function public.record_referral_bonus_on_member();

-- ── 2. BACKFILL: one Chairman Bonus row per EXISTING direct referral,
--       priced at the package the referrer held at that referral's time
--       (same rate v23 computes). Skipped if a row already exists, so this
--       is safe to re-run and won't collide with the trigger. ────────────
with dr as (
  select mt.user_id, mt.member_id, mt.item_id, mt."timestamp" as ts
  from public.member_transactions mt
  where mt.item_name ilike 'Direct Referral%'
),
priced as (
  select
    dr.user_id, dr.member_id, dr.item_id, dr.ts,
    coalesce((
      select coalesce(pk.chairmans_bonus, 0)
      from public.sales s
      join public.packages pk on pk.id = s.package_id
      where s.buyer_id = dr.member_id
        and s.package_id is not null
        and s."timestamp" <= dr.ts
      order by s."timestamp" desc
      limit 1
    ), 0) as rate
  from dr
)
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select p.user_id, p.member_id, p.item_id, 'Chairman Bonus', 1, p.rate, p.ts
from priced p
where p.rate > 0
  and not exists (
    select 1 from public.member_transactions cb
    where cb.member_id = p.member_id
      and cb.item_id   = p.item_id
      and cb.item_name ilike 'Chairman Bonus%'
  );

-- ── 3. RPC: sum the frozen Chairman ledger (no more live recompute) ────
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_balance     integer := 0;
  v_indirect    integer := 0;
  v_passive     integer := 0;
  v_chairman    integer := 0;
  v_fridays     integer := 0;
  v_upgrade     integer := 0;
  v_total       integer := 0;
  v_earn_deduct integer := 0;
  v_bal_deduct  integer := 0;
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

  -- ── Direct Referral Bonus (Balance wallet) — frozen at registration
  select coalesce(sum(price), 0) into v_balance
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Direct Referral%';

  -- ── Indirect Referral Bonus — frozen at registration ────────────
  select coalesce(sum(price), 0) into v_indirect
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Indirect Referral%';

  -- ── Group Sales (passive income) — frozen at purchase time (v19) ─
  select coalesce(sum(price), 0) into v_passive
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Group Sales%';

  -- ── Upgrade Referral Bonus — frozen at upgrade time ─────────────
  select coalesce(sum(price), 0) into v_upgrade
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Upgrade Bonus%';

  -- ── Chairman's Bonus — frozen ledger (v24): one row per direct
  --    referral, locked at the referrer's package rate when earned.
  select coalesce(sum(price), 0) into v_chairman
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Chairman Bonus%';

  -- No Friday concept — keep the key for old clients, always 0.
  v_fridays := 0;

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
$function$;
