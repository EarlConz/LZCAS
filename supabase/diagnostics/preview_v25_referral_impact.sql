-- ═══════════════════════════════════════════════════════════════════
-- PREVIEW (read-only) — impact of migration_v25 on referral earnings
--
-- Run on the LIVE database BEFORE applying v25. Writes nothing. Shows, per
-- member, their current Direct/Indirect/Chairman totals vs what v25 will make
-- them, and the net change. Sorted by change (biggest drops first).
--
--   *_now  = today's stored ledger (old registration-based rule)
--   *_new  = v25 (availment-based, min-tier direct/indirect, own-rate chairman)
--   change = (new direct+indirect+chairman) − (now direct+indirect+chairman)
--
-- Depends on the same helper functions v25 installs. If you haven't applied
-- v25 yet, run just the two helper functions from the migration first (Part A),
-- or run this right after a `begin;`-wrapped dry-run of the migration.
-- ═══════════════════════════════════════════════════════════════════
with now_agg as (
  select member_id,
    coalesce(sum(price) filter (where item_name ilike 'Direct Referral%'), 0)   as now_direct,
    coalesce(sum(price) filter (where item_name ilike 'Indirect Referral%'), 0) as now_indirect,
    coalesce(sum(price) filter (where item_name ilike 'Chairman Bonus%'), 0)    as now_chairman
  from public.member_transactions
  group by member_id
),
-- level 1: direct (min-tier) + chairman (own rate), priced at each pair's
--          crystallization moment (later of the two first availments)
new_l1 as (
  select a1.id as member_id,
    coalesce(sum(public.referral_bonus_min_tier(
      public.package_held_at(a1.id, greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id))),
      public.first_availed_package(x.id), 'direct')), 0) as new_direct,
    coalesce(sum(
      coalesce((select pk.chairmans_bonus from public.packages pk
                where pk.id = public.package_held_at(a1.id, greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id)))), 0)
    ), 0) as new_chairman
  from public.members a1
  join public.members x on x.referrer_id = a1.id
  where a1.is_deleted = false and x.is_deleted = false
    and public.first_availment_ts(a1.id) is not null
    and public.first_availed_package(x.id) is not null
  group by a1.id
),
-- level 2: indirect (min-tier), priced at crystallization
new_l2 as (
  select a2.id as member_id,
    coalesce(sum(public.referral_bonus_min_tier(
      public.package_held_at(a2.id, greatest(public.first_availment_ts(a2.id), public.first_availment_ts(x.id))),
      public.first_availed_package(x.id), 'indirect')), 0) as new_indirect
  from public.members a2
  join public.members a1 on a1.referrer_id = a2.id
  join public.members x  on x.referrer_id = a1.id
  where a2.is_deleted = false and x.is_deleted = false
    and public.first_availment_ts(a2.id) is not null
    and public.first_availed_package(x.id) is not null
  group by a2.id
)
select
  m.id as member_id,
  (coalesce(m.first_name,'')||' '||coalesce(m.last_name,'')) as name,
  coalesce(na.now_direct, 0)                             as now_direct,
  coalesce(nl1.new_direct, 0)                            as new_direct,
  coalesce(na.now_indirect, 0)                           as now_indirect,
  coalesce(nl2.new_indirect, 0)                          as new_indirect,
  coalesce(na.now_chairman, 0)                           as now_chairman,
  coalesce(nl1.new_chairman, 0)                          as new_chairman,
  (coalesce(na.now_direct,0)+coalesce(na.now_indirect,0)+coalesce(na.now_chairman,0)) as now_total,
  (coalesce(nl1.new_direct,0)+coalesce(nl2.new_indirect,0)+coalesce(nl1.new_chairman,0)) as new_total,
  (coalesce(nl1.new_direct,0)+coalesce(nl2.new_indirect,0)+coalesce(nl1.new_chairman,0))
  - (coalesce(na.now_direct,0)+coalesce(na.now_indirect,0)+coalesce(na.now_chairman,0)) as change
from public.members m
left join now_agg na  on na.member_id  = m.id
left join new_l1  nl1 on nl1.member_id = m.id
left join new_l2  nl2 on nl2.member_id = m.id
where m.is_deleted = false
  and (na.member_id is not null or nl1.member_id is not null or nl2.member_id is not null)
order by change, m.id;
