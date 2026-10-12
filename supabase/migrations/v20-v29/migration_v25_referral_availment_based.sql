-- ═══════════════════════════════════════════════════════════════════
-- Migration v25 — Direct/Indirect Referral (and Chairman) become
--                 AVAILMENT-based, min-tier capped, with catch-up
--
-- Old rule (v24): the referrer earned a Direct/Indirect/Chairman bonus the
-- moment a downline REGISTERED, at the referrer's own package rate, whether or
-- not the downline ever availed a package.
--
-- New rule (v25):
--   1. A referral pays ONLY when the referred member avails their FIRST
--      package (registration alone pays nothing). Later upgrades never create
--      a new direct/indirect bonus.
--   2. Direct/Indirect amount = the referral bonus of the LOWER-TIER package
--      (by hierarchy_rank) between the EARNER's package and the referral's
--      first-availed package. Referral on a lower tier caps the earner down;
--      referral on a higher tier is capped at the earner's own package.
--   3. Chairman = the EARNER's OWN package chairman rate, one per qualifying
--      direct referral (referral must have availed a package). NOT min-tier.
--   4. Package-less members may still gather a downline; their uplines just
--      earn nothing for them until they avail. When a member finally avails,
--      "catch-up" pays them for downlines who already availed while the member
--      had no package (crystallizes at the LATER of the two availments).
--   5. Everything stays FROZEN once crystallized — a later upgrade by either
--      party never re-prices it (consistent with the frozen-ledger model).
--
-- Requires packages.hierarchy_rank to be set for tiers to matter (Starter <
-- Ambassador < Elite …). If all ranks are equal/0, min-tier degrades to the
-- earner's own rate (no cap).
--
-- The RPC (get_member_earnings) is UNCHANGED — it already sums the
-- 'Direct Referral' / 'Indirect Referral' / 'Chairman Bonus' ledgers. DB-only,
-- no app rebuild.
--
-- Parts: (A) helpers, (B) availment trigger, (C) drop the old registration
-- trigger, (D) backfill existing members to the new rule.
--
-- ⚠️ Part D is destructive-then-rebuild (drops existing referral/chairman
-- ledger rows and regenerates them). Back up first:
--     create table member_transactions_backup_v25 as
--       select * from public.member_transactions;
-- Rollback: rollbacks/rollback_referral_bonus_v24.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── A. Helpers ───────────────────────────────────────────────────────

-- A member's FIRST-availed package id (null if they never availed).
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

-- The referral bonus (direct or indirect) priced at the LOWER-TIER package
-- between the earner's package and the referral's availed package. Returns 0
-- if either package is null (no package → no bonus). Ties (equal rank) use the
-- earner's package.
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

  select case when p_kind = 'indirect' then indirect_referral_bonus
              else direct_referral_bonus end
    into amt
    from public.packages where id = chosen_pkg;

  return coalesce(amt, 0);
end;
$$;

-- Timestamp of a member's FIRST package availment (null if never availed).
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

-- The package a member HELD at a given moment = their latest package sale at
-- or before that timestamp (null if they held none yet).
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

-- ── B. Availment trigger: crystallize referral bonuses ───────────────
create or replace function public.crystallize_referral_on_availment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only package availments (product sales have package_id null).
  if NEW.package_id is null then
    return NEW;
  end if;

  -- Only the buyer's FIRST package availment. If any earlier package sale
  -- exists, this is an upgrade → no direct/indirect/chairman here.
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

  -- L1 Direct Referral to the direct referrer (min-tier), if they hold a pkg.
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

  -- L1 Chairman's Bonus to the direct referrer (their OWN rate).
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a1.user_id, a1.id, NEW.buyer_id, 'Chairman Bonus', 1,
         pk.chairmans_bonus, NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  join public.packages pk on pk.id = a1.package_id
  where m.id = NEW.buyer_id
    and a1.is_deleted = false
    and pk.chairmans_bonus > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a1.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Chairman Bonus%');

  -- L2 Indirect Referral to the referrer's referrer (min-tier).
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

  -- ═══ SIDE A — this member now holds a package; catch-up pay them for
  --            downlines who already availed while they had none ═══

  -- Direct for M's direct downlines that already availed (min-tier).
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

  -- Chairman for M (own rate), one per already-availed direct downline.
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, d.id, 'Chairman Bonus', 1,
         pk.chairmans_bonus, NEW."timestamp"
  from public.members m
  join public.packages pk on pk.id = NEW.package_id
  join public.members d on d.referrer_id = NEW.buyer_id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and pk.chairmans_bonus > 0
    and public.first_availed_package(d.id) is not null
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = d.id
                      and t.item_name ilike 'Chairman Bonus%');

  -- Indirect for M's downlines' downlines that already availed (min-tier).
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

drop trigger if exists trg_crystallize_referral_on_availment on public.sales;
create trigger trg_crystallize_referral_on_availment
  after insert on public.sales
  for each row execute function public.crystallize_referral_on_availment();

-- ── C. Registration no longer pays referral bonuses ─────────────────
--    (the function is left defined but its trigger is removed).
drop trigger if exists trg_record_referral_bonus on public.members;

-- ── D. Backfill existing members to the new rule ────────────────────
--    HISTORICALLY ACCURATE: each pair is priced at the earner's package AT
--    the crystallization moment = the LATER of the earner's and the referral's
--    first availment. This is a true freeze — an earner who upgraded keeps
--    their earlier (pre-upgrade) rate for referrals earned back then. The
--    row's timestamp is set to that crystallization moment too.

delete from public.member_transactions
where item_name ilike 'Direct Referral%'
   or item_name ilike 'Indirect Referral%'
   or item_name ilike 'Chairman Bonus%';

-- L1 Direct — earner = direct referrer, priced at their package when crystallized
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
select earner_user, earner_id, ref_id, 'Direct Referral', 1,
       public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'direct'), cts
from priced
where public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'direct') > 0;

-- L1 Chairman — earner's OWN chairman rate at the crystallization moment
with pairs as (
  select a1.id as earner_id, a1.user_id as earner_user, x.id as ref_id,
         greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id)) as cts
  from public.members x
  join public.members a1 on a1.id = x.referrer_id
  where x.is_deleted = false and a1.is_deleted = false
    and public.first_availed_package(x.id) is not null
    and public.first_availment_ts(a1.id) is not null
),
priced as (
  select p.*,
         coalesce((select pk.chairmans_bonus from public.packages pk
                   where pk.id = public.package_held_at(p.earner_id, p.cts)), 0) as chair
  from pairs p
)
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select earner_user, earner_id, ref_id, 'Chairman Bonus', 1, chair, cts
from priced
where chair > 0;

-- L2 Indirect — earner = referrer's referrer, priced at crystallization
with pairs as (
  select a2.id as earner_id, a2.user_id as earner_user, x.id as ref_id,
         greatest(public.first_availment_ts(a2.id), public.first_availment_ts(x.id)) as cts,
         public.first_availed_package(x.id) as ref_pkg
  from public.members x
  join public.members a1 on a1.id = x.referrer_id
  join public.members a2 on a2.id = a1.referrer_id
  where x.is_deleted = false and a2.is_deleted = false
    and public.first_availed_package(x.id) is not null
    and public.first_availment_ts(a2.id) is not null
),
priced as (
  select p.*, public.package_held_at(p.earner_id, p.cts) as earner_pkg from pairs p
)
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select earner_user, earner_id, ref_id, 'Indirect Referral', 1,
       public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'indirect'), cts
from priced
where public.referral_bonus_min_tier(earner_pkg, ref_pkg, 'indirect') > 0;
