-- ═══════════════════════════════════════════════════════════════════
-- DIAGNOSE ONE MEMBER'S EARNINGS (read-only — writes nothing)
--
-- Itemizes every peso a reseller earned so you can see exactly where each
-- amount comes from and spot inconsistencies. Shows the frozen ledgers
-- (Direct/Indirect Referral, Group Sales, Upgrade Bonus, and — since v24 —
-- Chairman's Bonus), the package timeline, the withdrawals, and the
-- reconciled wallet totals. All bonuses are now stored rows the RPC sums.
--
-- HOW TO USE:
--   1. First, find the member id:
--        select id, first_name, last_name, role
--          from public.members where is_deleted = false order by id;
--   2. Put that id in the params CTE below (replace the 0).
--   3. Run. Read top-to-bottom; the TOTALS section reconciles everything.
-- ═══════════════════════════════════════════════════════════════════
with params as (
  select 0::bigint as member_id          -- ◀── SET THE MEMBER ID HERE
),

-- reseller's availment/upgrade timeline (Manila dates) — for display only
pkg_periods as (
  select
    ((s."timestamp") at time zone 'Asia/Manila')::date as eff_from,
    ((lead(s."timestamp") over (order by s."timestamp"))
       at time zone 'Asia/Manila')::date as eff_to,
    coalesce(pk.chairmans_bonus, 0) as rate
  from public.sales s
  join public.packages pk on pk.id = s.package_id, params p
  where s.buyer_id = p.member_id and s.package_id is not null
),

-- frozen-ledger totals
tot as (
  select
    coalesce((select sum(price) from public.member_transactions mt, params p
              where mt.member_id = p.member_id and mt.item_name ilike 'Direct Referral%'), 0)   as direct,
    coalesce((select sum(price) from public.member_transactions mt, params p
              where mt.member_id = p.member_id and mt.item_name ilike 'Indirect Referral%'), 0) as indirect,
    coalesce((select sum(price) from public.member_transactions mt, params p
              where mt.member_id = p.member_id and mt.item_name ilike 'Group Sales%'), 0)       as passive,
    coalesce((select sum(price) from public.member_transactions mt, params p
              where mt.member_id = p.member_id and mt.item_name ilike 'Upgrade Bonus%'), 0)     as upgrade,
    coalesce((select sum(price) from public.member_transactions mt, params p
              where mt.member_id = p.member_id and mt.item_name ilike 'Chairman Bonus%'), 0)    as chairman,
    coalesce((select sum(requested_amount) from public.withdrawal_requests w, params p
              where w.member_id = p.member_id and w.status='approved' and w.source_bucket='balance'), 0)        as bal_wd,
    coalesce((select sum(requested_amount) from public.withdrawal_requests w, params p
              where w.member_id = p.member_id and w.status='approved' and w.source_bucket='total_earnings'), 0) as earn_wd
)

-- ═══════════════ itemized output ═══════════════
select 1 as ord, 0 as ord2, 'MEMBER' as section, null::date as line_date,
  (coalesce(m.first_name,'')||' '||coalesce(m.last_name,'')) as description,
  null::integer as amount,
  ('id='||m.id||'  role='||coalesce(m.role,'-')||'  package='||coalesce(pk.name,'none')) as note
from public.members m left join public.packages pk on pk.id = m.package_id, params p
where m.id = p.member_id

union all
select 2, row_number() over (order by eff_from), 'PACKAGE TIMELINE', eff_from,
  'Availed / upgraded package', rate,
  'chairman rate ₱'||rate||' effective until '||coalesce(eff_to::text,'(current)')
from pkg_periods

union all
select 3, row_number() over (order by mt."timestamp"), 'DIRECT REFERRAL (Balance)',
  ((mt."timestamp") at time zone 'Asia/Manila')::date,
  'Recruited: '||coalesce(r.first_name,'')||' '||coalesce(r.last_name,'(member #'||mt.item_id||')'),
  mt.price, 'frozen at referrer rate'
from public.member_transactions mt
left join public.members r on r.id = mt.item_id, params p
where mt.member_id = p.member_id and mt.item_name ilike 'Direct Referral%'

union all
select 4, row_number() over (order by mt."timestamp"), 'INDIRECT REFERRAL',
  ((mt."timestamp") at time zone 'Asia/Manila')::date,
  'Downline recruited: '||coalesce(r.first_name,'')||' '||coalesce(r.last_name,'(member #'||mt.item_id||')'),
  mt.price, 'frozen at rate'
from public.member_transactions mt
left join public.members r on r.id = mt.item_id, params p
where mt.member_id = p.member_id and mt.item_name ilike 'Indirect Referral%'

union all
select 5, row_number() over (order by mt."timestamp"), 'GROUP SALES (Passive)',
  ((mt."timestamp") at time zone 'Asia/Manila')::date,
  mt.item_name, mt.price, 'frozen at purchase time'
from public.member_transactions mt, params p
where mt.member_id = p.member_id and mt.item_name ilike 'Group Sales%'

union all
select 6, row_number() over (order by mt."timestamp"), 'UPGRADE BONUS',
  ((mt."timestamp") at time zone 'Asia/Manila')::date,
  mt.item_name, mt.price, 'frozen at upgrade time'
from public.member_transactions mt, params p
where mt.member_id = p.member_id and mt.item_name ilike 'Upgrade Bonus%'

union all
select 7, row_number() over (order by mt."timestamp"), 'CHAIRMAN BONUS (frozen ledger)',
  ((mt."timestamp") at time zone 'Asia/Manila')::date,
  'For recruiting: '||coalesce(r.first_name,'')||' '||coalesce(r.last_name,'(member #'||mt.item_id||')'),
  mt.price, 'frozen at referrer chairman rate'
from public.member_transactions mt
left join public.members r on r.id = mt.item_id, params p
where mt.member_id = p.member_id and mt.item_name ilike 'Chairman Bonus%'

union all
select 8, row_number() over (order by w.created_at), 'WITHDRAWAL ('||w.source_bucket||')',
  ((w.created_at) at time zone 'Asia/Manila')::date,
  'status: '||w.status,
  case when w.status='approved' then -w.requested_amount else w.requested_amount end,
  case when w.status='approved' then 'deducted' else 'not deducted' end
from public.withdrawal_requests w, params p
where w.member_id = p.member_id

union all
select 9, 1, 'TOTALS', null, 'Balance — Direct Referral (gross)',        direct,   null from tot
union all
select 9, 2, 'TOTALS', null, 'Total Earnings · Indirect (gross)',        indirect, null from tot
union all
select 9, 3, 'TOTALS', null, 'Total Earnings · Group Sales (gross)',     passive,  null from tot
union all
select 9, 4, 'TOTALS', null, 'Total Earnings · Chairman (gross)',        chairman, 'frozen ledger (v24)' from tot
union all
select 9, 5, 'TOTALS', null, 'Total Earnings · Upgrade (gross)',         upgrade,  null from tot
union all
select 9, 7, 'TOTALS', null, 'Withdrawn from Balance (approved)',        -bal_wd,  null from tot
union all
select 9, 8, 'TOTALS', null, 'Withdrawn from Total Earnings (approved)', -earn_wd, null from tot
union all
select 9, 9, 'TOTALS', null, 'FINAL Balance = max(0, direct − wd)',
  greatest(0, direct - bal_wd), null from tot
union all
select 9,10, 'TOTALS', null, 'FINAL Total Earnings = max(0, indirect+passive+chairman+upgrade − wd)',
  greatest(0, indirect + passive + chairman + upgrade - earn_wd), 'live (v24)' from tot

order by ord, ord2, line_date nulls first, description;
