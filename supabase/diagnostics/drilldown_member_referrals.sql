-- ═══════════════════════════════════════════════════════════════════
-- DRILL-DOWN (read-only) — one earner's referral bonuses, line by line
--
-- For the earner set below, lists every DIRECT (level 1) and INDIRECT
-- (level 2) referral with: whether they availed a package, the referral's
-- first-availed package, the earner's package AT the crystallization moment,
-- and the resulting v25 amount vs the current (old-rule) amount.
--
-- Needs the v25 helper functions installed (first_availed_package,
-- referral_bonus_min_tier, first_availment_ts, package_held_at).
--
-- Set the earner id below (default 1 = GUTVITA LZCAS).
-- ═══════════════════════════════════════════════════════════════════
with params as ( select 1::bigint as earner ),   -- ◀── earner member id

direct_rows as (
  select
    'Direct'::text as level,
    x.id as ref_id,
    (coalesce(x.first_name,'')||' '||coalesce(x.last_name,'')) as referral,
    greatest(public.first_availment_ts(p.earner), public.first_availment_ts(x.id)) as cts
  from params p
  join public.members x on x.referrer_id = p.earner
  where x.is_deleted = false
),
indirect_rows as (
  select
    'Indirect'::text as level,
    x.id as ref_id,
    (coalesce(x.first_name,'')||' '||coalesce(x.last_name,'')) as referral,
    greatest(public.first_availment_ts(p.earner), public.first_availment_ts(x.id)) as cts
  from params p
  join public.members a1 on a1.referrer_id = p.earner and a1.is_deleted = false
  join public.members x  on x.referrer_id  = a1.id     and x.is_deleted  = false
),
all_rows as (
  select * from direct_rows
  union all
  select * from indirect_rows
)
select
  r.level,
  r.referral,
  (public.first_availed_package(r.ref_id) is not null) as availed,
  coalesce(rpk.name || ' (r' || rpk.hierarchy_rank || ')', 'NONE') as referral_package,
  coalesce(epk.name || ' (r' || epk.hierarchy_rank || ')', 'NONE') as my_package_when_earned,
  -- v25 amount (min-tier for direct/indirect)
  public.referral_bonus_min_tier(
    public.package_held_at((select earner from params), r.cts),
    public.first_availed_package(r.ref_id),
    lower(r.level)
  ) as new_bonus,
  -- current stored amount for this pair (old rule)
  coalesce((select sum(mt.price) from public.member_transactions mt
            where mt.member_id = (select earner from params) and mt.item_id = r.ref_id
              and mt.item_name ilike (r.level || ' Referral%')), 0) as now_bonus,
  -- chairman (direct only): earner's OWN rate at crystallization vs current stored
  case when r.level = 'Direct'
       then coalesce(epk.chairmans_bonus, 0) else null end as new_chairman,
  case when r.level = 'Direct'
       then coalesce((select sum(mt.price) from public.member_transactions mt
                      where mt.member_id = (select earner from params) and mt.item_id = r.ref_id
                        and mt.item_name ilike 'Chairman Bonus%'), 0)
       else null end as now_chairman
from all_rows r
left join public.packages rpk on rpk.id = public.first_availed_package(r.ref_id)
left join public.packages epk on epk.id = public.package_held_at((select earner from params), r.cts)
order by r.level, r.ref_id;
