-- ═══════════════════════════════════════════════════════════════════
-- Migration v27 — Chairman's Bonus becomes MIN-TIER capped
--
-- Brings Chairman in line with Direct/Indirect/Upgrade: the amount per
-- qualifying direct referral is the chairmans_bonus of the LOWER-TIER package
-- (by hierarchy_rank) between the EARNER's package and the referral's
-- first-availed package — instead of always the earner's own rate.
--
--   e.g. earner on Gold, referral availed Starter:
--        min-tier(Gold, Starter) = Starter → earner gets Starter's chairman
--        rate, not Gold's.
--
-- Unchanged: Chairman is still ONE payment per direct referral who availed a
-- package (level 1 only), still frozen, still Total Earnings. Only the amount
-- rule changes. Direct/Indirect/Upgrade ledgers are NOT touched.
--
-- ⚠️ THIS CHANGES EXISTING EARNINGS. Members who recruited downlines on a
-- lower tier than their own will see Chairman drop (min-tier never raises it).
-- Part 3 recomputes existing Chairman rows historically (priced at each pair's
-- crystallization moment). Back up first:
--     create table member_transactions_backup_v27 as
--       select * from public.member_transactions;
--
-- Three parts: (1) extend the helper with 'chairman', (2) redefine the
-- availment trigger's chairman inserts to min-tier, (3) recompute the Chairman
-- ledger. RPC unchanged. DB-only, no app rebuild.
--
-- Rollback: rollbacks/rollback_chairman_v25.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Teach referral_bonus_min_tier the 'chairman' kind ─────────────
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

-- ── 2. Availment trigger — chairman inserts now use min-tier ─────────
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

-- (trigger binding is unchanged from v25; re-assert to be safe)
drop trigger if exists trg_crystallize_referral_on_availment on public.sales;
create trigger trg_crystallize_referral_on_availment
  after insert on public.sales
  for each row execute function public.crystallize_referral_on_availment();

-- ── 3. Recompute ONLY the Chairman ledger at min-tier (historical) ───
--    Direct/Indirect rows are left exactly as v25 wrote them.

delete from public.member_transactions where item_name ilike 'Chairman Bonus%';

with pairs as (
  select a1.id as earner_id, a1.user_id as earner_user, x.id as ref_id,
         greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id)) as cts,
         public.first_availed_package(x.id) as ref_pkg
  from public.members x
  join public.members a1 on a1.id = x.referrer_id
  where x.is_deleted = false and a1.is_deleted = false
    and public.first_availed_package(x.id) is not null
    and public.first_availment_ts(a1.id) is not null
),
priced as (
  select p.*, public.package_held_at(p.earner_id, p.cts) as earner_pkg from pairs p
)
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select earner_user, earner_id, ref_id, 'Chairman Bonus', 1,
       public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'chairman'), cts
from priced
where public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'chairman') > 0;
