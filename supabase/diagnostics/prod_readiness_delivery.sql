-- ═══════════════════════════════════════════════════════════════════
-- Production readiness for the delivery release (v48 → v74)
--
-- READ-ONLY. Writes nothing; safe on production. One result: a row per
-- check, with what to expect beside it. Run the whole file at once.
--
-- Pairs with docs/prod_rollout_delivery.md, phase 1. Run it before the
-- first migration, and again whenever you want to see where things stand.
-- Vault entries are listed by NAME only; their values are never read.
-- ═══════════════════════════════════════════════════════════════════

with
earned as (
  -- As audit_withdrawal_overdrafts.sql and get_member_earnings sum them.
  select
    m.id as member_id,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Direct Referral%'
         or t.item_name ilike 'Order Payment (Balance)%'), 0) as balance_earned,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Indirect Referral%'
         or t.item_name ilike 'Group Sales%'
         or t.item_name ilike 'Upgrade Bonus%'
         or t.item_name ilike 'Chairman Bonus%'
         or t.item_name ilike 'Order Payment (Earnings)%'), 0) as earnings_earned
  from public.members m
  left join public.member_transactions t on t.member_id = m.id
  where m.is_deleted = false
  group by m.id
),
req as (
  select
    member_id,
    coalesce(sum(requested_amount) filter (where status in ('approved', 'pending') and source_bucket = 'balance'), 0)        as bal_out,
    coalesce(sum(requested_amount) filter (where status in ('approved', 'pending') and source_bucket = 'total_earnings'), 0) as earn_out,
    count(*) filter (where status = 'pending') as pending
  from public.withdrawal_requests
  group by member_id
),
checks(n, item, expect, actual) as (
  select 1, 'Ledger: versions recorded from v45',
         'v45 v46 v47 v51 (v48 maybe); nothing from v52 up',
         coalesce((select string_agg('v' || version, ' ' order by version)
                     from public.schema_migrations where version >= 45), '(none)')
  union all
  select 2, 'v48: orders table exists', 'either; v48 is safe to re-run',
         case when to_regclass('public.orders') is null then 'no' else 'yes' end
  union all
  select 3, 'v56: pending withdrawals', 'any number',
         (select count(*)::text from public.withdrawal_requests where status = 'pending')
  union all
  select 4, 'v56: members whose pending withdrawals would overdraw', '0 (else settle them before v56)',
         (select count(*)::text
            from earned e join req r on r.member_id = e.member_id
           where r.pending > 0
             and (r.bal_out > e.balance_earned or r.earn_out > e.earnings_earned))
  union all
  select 5, 'v67: members in their own referral chain (self or two-way)', '0 (rows do not block v67)',
         (select count(*)::text from public.members m
           where m.referrer_id = m.id
              or exists (select 1 from public.members r
                          where r.id = m.referrer_id and r.referrer_id = m.id))
  union all
  select 6, 'v71: commission triggers on sales (name:enabled)',
         '4 rows, each :O; if all 4 are there, v71 is not needed',
         coalesce((select string_agg(tgname::text || ':' || tgenabled::text, ' ' order by tgname)
                     from pg_trigger
                    where tgrelid = 'public.sales'::regclass and not tgisinternal), '(none)')
  union all
  select 7, 'v72: orders updated_at trigger', 'none before v48; after v48, present',
         coalesce((select string_agg(tgname::text, ' ')
                     from pg_trigger
                    where tgrelid = to_regclass('public.orders') and not tgisinternal), '(none)')
  union all
  select 8, 'v68/v70/v73: tables in realtime now', 'any; the migrations add what is missing',
         coalesce((select string_agg(tablename, ' ' order by tablename)
                     from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public'), '(none)')
  union all
  select 9, 'v58: pg_net extension', 'either; v58 enables it',
         case when exists (select 1 from pg_extension where extname = 'pg_net') then 'installed'
              when exists (select 1 from pg_available_extensions where name = 'pg_net') then 'available'
              else 'NOT AVAILABLE' end
  union all
  select 10, 'v74: pg_cron extension', 'installed or available (else scheduled posts get no push)',
         case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'installed'
              when exists (select 1 from pg_available_extensions where name = 'pg_cron') then 'available'
              else 'NOT AVAILABLE' end
  union all
  select 11, 'Vault: push entries (names only)', 'none yet; set in phase 3',
         coalesce((select string_agg(name, ' ' order by name)
                     from vault.secrets where name like 'order_push%'), '(none)')
  union all
  select 12, 'v63: product-images bucket', 'no before v63',
         case when exists (select 1 from storage.buckets where id = 'product-images') then 'yes' else 'no' end
  union all
  select 13, 'Members (not deleted) / without a package', 'members: any; without a package: 0',
         (select (count(*) filter (where not is_deleted))::text || ' / ' ||
                 (count(*) filter (where not is_deleted and package_id is null))::text
            from public.members)
  union all
  select 14, 'Accounts by role', 'for reference',
         coalesce((select string_agg(role || ' ' || c, ', ' order by role)
                     from (select coalesce(role, '(none)') as role, count(*) as c
                             from public.profiles group by 1) x), '(none)')
)
select n as "#", item as "check", expect, actual
  from checks
 order by n;
