-- ═══════════════════════════════════════════════════════════════════
-- PREVIEW (read-only) — impact of migration_v22 on Chairman's Bonus
--
-- Run this on the LIVE database BEFORE applying v22. It writes nothing and
-- affects no users — it just shows, per reseller:
--
--   chairman_v21        = current behaviour (rate × (1 + Fridays elapsed))
--   chairman_after_v22  = new behaviour (per payout Friday: referrals that
--                         week × chairman rate of the package held THAT Friday,
--                         counting only Fridays that have already passed)
--   paid_fridays_v22    = number of Fridays they actually get paid on (weeks
--                         with ≥1 credited referral)
--   change              = chairman_after_v22 − chairman_v21 (can be + or −)
--
-- Members with a package but no direct referrals drop to 0 under v22 (they no
-- longer accrue a bonus every Friday just for holding a package).
-- ═══════════════════════════════════════════════════════════════════
with now_manila as (
  select (now() at time zone 'Asia/Manila')::date as d
),
-- each reseller's availment/upgrade timeline (Manila dates)
pkg_periods as (
  select
    s.buyer_id as member_id,
    ((s."timestamp") at time zone 'Asia/Manila')::date as eff_from,
    ((lead(s."timestamp") over (partition by s.buyer_id order by s."timestamp"))
       at time zone 'Asia/Manila')::date as eff_to,
    coalesce(pk.chairmans_bonus, 0) as rate
  from public.sales s
  join public.packages pk on pk.id = s.package_id
  where s.package_id is not null
),
-- ── v21 (current) Chairman's Bonus: rate × (1 + Fridays elapsed) ──────
v21_periods as (
  select
    pp.member_id,
    pp.rate,
    greatest(0,
      ((coalesce(pp.eff_to, (select d from now_manila)) - date '2000-01-07') / 7)
      - ((pp.eff_from - date '2000-01-07') / 7)
    ) as fridays
  from pkg_periods pp
),
v21 as (
  select member_id, coalesce(sum(rate * (fridays + 1)), 0) as chairman_v21
  from v21_periods
  group by member_id
),
-- ── v22 (new) Chairman's Bonus: per payout Friday, referrals that week ×
--    the chairman rate of the package held ON that Friday ────────────────
referrals as (
  select
    mt.member_id,
    (date '2000-01-07'
      + (ceil((((mt."timestamp") at time zone 'Asia/Manila')::date
               - date '2000-01-07')::numeric / 7)::int) * 7) as payout_friday
  from public.member_transactions mt
  where mt.item_name ilike 'Direct Referral%'
),
weekly as (
  select member_id, payout_friday, count(*) as referral_count
  from referrals
  where payout_friday <= (select d from now_manila)
  group by member_id, payout_friday
),
priced as (
  select
    w.member_id,
    w.referral_count,
    coalesce((
      select pp.rate
      from pkg_periods pp
      where pp.member_id = w.member_id
        and w.payout_friday >= pp.eff_from
        and (pp.eff_to is null or w.payout_friday < pp.eff_to)
      order by pp.eff_from desc
      limit 1
    ), 0) as rate
  from weekly w
),
v22 as (
  select
    member_id,
    coalesce(sum(referral_count * rate), 0) as chairman_after_v22,
    count(*) as paid_fridays_v22
  from priced
  group by member_id
)
select
  coalesce(v21.member_id, v22.member_id) as member_id,
  m.first_name,
  m.last_name,
  coalesce(v21.chairman_v21, 0)        as chairman_v21,
  coalesce(v22.chairman_after_v22, 0)  as chairman_after_v22,
  coalesce(v22.paid_fridays_v22, 0)    as paid_fridays_v22,
  coalesce(v22.chairman_after_v22, 0)
    - coalesce(v21.chairman_v21, 0)    as change
from v21
full outer join v22 on v22.member_id = v21.member_id
left join public.members m on m.id = coalesce(v21.member_id, v22.member_id)
order by change;
