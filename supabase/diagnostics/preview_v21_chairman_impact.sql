-- ═══════════════════════════════════════════════════════════════════
-- PREVIEW (read-only) — impact of migration_v21 on Chairman's Bonus
--
-- Run this on the LIVE database BEFORE applying v21. It writes nothing and
-- affects no users — it just shows, per reseller, the current Chairman's
-- Bonus vs. what it becomes after v21, and the increase.
--
--   chairman_now       = current behaviour (rate × Fridays)
--   chairman_after_v21 = with the immediate availment/upgrade payment
--   increase           = the one-time bump each member will see
-- ═══════════════════════════════════════════════════════════════════
with pkg_periods as (
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
periods as (
  select
    member_id,
    rate,
    greatest(0,
      ((coalesce(eff_to, (now() at time zone 'Asia/Manila')::date) - date '2000-01-07') / 7)
      - ((eff_from - date '2000-01-07') / 7)
    ) as fridays
  from pkg_periods
)
select
  p.member_id,
  m.first_name,
  m.last_name,
  sum(p.rate * p.fridays)             as chairman_now,
  sum(p.rate * (p.fridays + 1))       as chairman_after_v21,
  sum(p.rate * (p.fridays + 1))
    - sum(p.rate * p.fridays)         as increase
from periods p
left join public.members m on m.id = p.member_id
group by p.member_id, m.first_name, m.last_name
order by increase desc;
