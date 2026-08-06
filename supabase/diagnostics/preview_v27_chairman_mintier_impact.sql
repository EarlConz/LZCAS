-- ═══════════════════════════════════════════════════════════════════
-- PREVIEW (read-only) — impact of migration_v27 on Chairman's Bonus
--
-- Shows, per member: current Chairman total (stored) vs the new min-tier
-- Chairman total (priced at each pair's crystallization moment), and the
-- change. All changes are ≤ 0 (min-tier never raises Chairman). Writes nothing.
--
-- REQUIRES the extended referral_bonus_min_tier helper (with the 'chairman'
-- branch) to be installed first — run that helper block (from migration_v27
-- Part 1, or the snippet the assistant provides) before this preview.
-- ═══════════════════════════════════════════════════════════════════
with now_c as (
  select member_id, coalesce(sum(price), 0) as now_chairman
  from public.member_transactions
  where item_name ilike 'Chairman Bonus%'
  group by member_id
),
new_c as (
  select a1.id as member_id,
    coalesce(sum(public.referral_bonus_min_tier(
      public.package_held_at(a1.id, greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id))),
      public.first_availed_package(x.id), 'chairman')), 0) as new_chairman
  from public.members a1
  join public.members x on x.referrer_id = a1.id
  where a1.is_deleted = false and x.is_deleted = false
    and public.first_availment_ts(a1.id) is not null
    and public.first_availed_package(x.id) is not null
  group by a1.id
)
select
  coalesce(nc.member_id, wc.member_id) as member_id,
  m.first_name, m.last_name,
  coalesce(wc.now_chairman, 0) as now_chairman,
  coalesce(nc.new_chairman, 0) as new_chairman,
  coalesce(nc.new_chairman, 0) - coalesce(wc.now_chairman, 0) as change
from now_c wc
full outer join new_c nc on nc.member_id = wc.member_id
left join public.members m on m.id = coalesce(nc.member_id, wc.member_id)
order by change, member_id;
