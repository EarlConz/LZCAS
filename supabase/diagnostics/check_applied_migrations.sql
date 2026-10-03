-- ═══════════════════════════════════════════════════════════════════
-- Which migrations are actually applied to THIS project? (v35 … v67)
--
-- Read-only. Safe on any environment, writes nothing.
--
-- Each row checks for the object the migration creates, so it reports what
-- the database really has rather than what anyone remembers running. Run it
-- on staging before rebuilding, and on prod before a release.
--
-- 'APPLIED' / 'MISSING' in the status column; apply the MISSING ones in
-- ascending version order.
-- ═══════════════════════════════════════════════════════════════════

-- Once v45 is applied, prefer the ledger — it knows about migrations that
-- leave no detectable trace, which this script cannot see:
--   select version, name, verified from public.schema_migrations order by version;
-- This remains useful as an independent check of what is really there.

select 'v35  admin fund adjustments' as migration,
       case when exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'admin_adjust_member_funds'
       ) then 'APPLIED' else 'MISSING' end as status,
       'admin_adjust_member_funds() RPC' as looks_for

union all
select 'v36  announcements + birthdays',
       case when to_regclass('public.announcements') is not null
            then 'APPLIED' else 'MISSING' end,
       'announcements table'

union all
select 'v37  cashier location',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'profiles'
           and column_name = 'location_updated_at'
       ) then 'APPLIED' else 'MISSING' end,
       'profiles.location_updated_at'

union all
select 'v38  member cashier stock',
       case when exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'member_branch_stock'
       ) then 'APPLIED' else 'MISSING' end,
       'member_branch_stock() RPC'

union all
-- to_regclass, not 'public.announcements'::regclass: the cast RAISES on a
-- database where the table does not exist yet, which is exactly the database
-- this script is most needed on. to_regclass returns null instead.
select 'v39  announcement audiences',
       case when exists (
         select 1 from pg_constraint
         where conrelid = to_regclass('public.announcements')
           and pg_get_constraintdef(oid) ilike '%branches%'
       ) then 'APPLIED' else 'MISSING' end,
       'audience CHECK allows ''branches'''

union all
select 'v40  announcement reads',
       case when to_regclass('public.announcement_reads') is not null
            then 'APPLIED' else 'MISSING' end,
       'announcement_reads table'

union all
select 'v41  saved items by profile',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'member_saved_items'
           and column_name = 'profile_id'
       ) then 'APPLIED' else 'MISSING' end,
       'member_saved_items.profile_id'

union all
select 'v42  server_now',
       case when exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'server_now'
       ) then 'APPLIED' else 'MISSING' end,
       'server_now() RPC'

-- Narrowed, not added: this one checks the policy no longer opens with
-- is_staff(), which is what let branch cashiers read Members-only notices.
union all
select 'v43  announcement staff bypass',
       case when exists (
         select 1 from pg_policies
         where schemaname = 'public' and tablename = 'announcements'
           and policyname = 'announcements_select'
           and qual ilike '%is_admin%' and qual not ilike '%is_staff%'
       ) then 'APPLIED' else 'MISSING' end,
       'announcements_select uses is_admin(), not is_staff()'

union all
select 'v44  posters (column)',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'announcements'
           and column_name = 'image_path'
       ) then 'APPLIED' else 'MISSING' end,
       'announcements.image_path'

union all
select 'v44  posters (bucket)',
       case when exists (
         select 1 from storage.buckets
         where id = 'announcement-media' and public = false
       ) then 'APPLIED' else 'MISSING' end,
       'private announcement-media bucket'

union all
select 'v44  posters (body nullable)',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'announcements'
           and column_name = 'body' and is_nullable = 'YES'
       ) then 'APPLIED' else 'MISSING' end,
       'announcements.body accepts null'

union all
select 'v45  migration ledger',
       case when to_regclass('public.schema_migrations') is not null
            then 'APPLIED' else 'MISSING' end,
       'schema_migrations table'

union all
select 'v46  app_config RLS',
       case when exists (
         select 1 from pg_policies
         where schemaname = 'public' and tablename = 'app_config'
           and policyname = 'app_config_update'
       ) then 'APPLIED' else 'MISSING' end,
       'app_config_update policy'

union all
select 'v47  member location',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'members'
           and column_name = 'location_updated_at'
       ) then 'APPLIED' else 'MISSING' end,
       'members.location_updated_at'

union all
select 'v48  delivery orders',
       case when to_regclass('public.orders') is not null
             and exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'create_delivery_order')
            then 'APPLIED' else 'MISSING' end,
       'orders table + create_delivery_order()'

union all
select 'v49  orders authorization',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'order_rider_is_me')
            then 'APPLIED' else 'MISSING' end,
       'order_rider_is_me() function'

union all
select 'v50  delivery role',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'orders'
           and column_name = 'delivery_id'
       ) then 'APPLIED' else 'MISSING' end,
       'orders.delivery_id'

union all
select 'v51  cashier announcements',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'can_post_announcements')
            then 'APPLIED' else 'MISSING' end,
       'can_post_announcements() function'

union all
select 'v52  order payment + sales',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'orders'
           and column_name = 'cod_remitted_at'
       ) then 'APPLIED' else 'MISSING' end,
       'orders.cod_remitted_at'

union all
select 'v53  order route',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'orders'
           and column_name = 'route_points'
       ) then 'APPLIED' else 'MISSING' end,
       'orders.route_points'

union all
select 'v54  delivery payment hardening',
       case when to_regclass('public.order_fee_offers') is not null
            then 'APPLIED' else 'MISSING' end,
       'order_fee_offers table'

union all
select 'v55  delivery cashiers only',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'can_handle_orders')
            then 'APPLIED' else 'MISSING' end,
       'can_handle_orders() function'

union all
select 'v56  withdrawal reservations',
       case when exists (select 1 from pg_trigger
                          where tgname = 'withdrawal_requests_guard' and not tgisinternal)
            then 'APPLIED' else 'MISSING' end,
       'withdrawal_requests_guard trigger'

union all
select 'v57  order refunds + receiver',
       case when exists (
         select 1 from pg_constraint
         where conrelid = to_regclass('public.orders')
           and conname = 'orders_payment_status_check'
           and pg_get_constraintdef(oid) ilike '%refunded%'
       ) then 'APPLIED' else 'MISSING' end,
       'payment_status CHECK allows ''refunded'''

union all
select 'v58  push notifications',
       case when to_regclass('public.push_tokens') is not null
            then 'APPLIED' else 'MISSING' end,
       'push_tokens table'

-- Changed bodies only, so this looks inside the function for v59's message.
union all
select 'v59  dispatch needs payment',
       case when exists (
         select 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = 'cashier_assign_rider'
           and prosrc ilike '%Waiting for the member to pay%'
       ) then 'APPLIED' else 'MISSING' end,
       'cashier_assign_rider() waits for payment'

union all
select 'v60  reduce item stock',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'reduce_item_stock')
            then 'APPLIED' else 'MISSING' end,
       'reduce_item_stock() function'

union all
select 'v61  courier delivery',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'orders'
           and column_name = 'tracking_number'
       ) then 'APPLIED' else 'MISSING' end,
       'orders.tracking_number'

union all
select 'v62  short COD code + busy riders',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'delivery_busy_rider_ids')
            then 'APPLIED' else 'MISSING' end,
       'delivery_busy_rider_ids() function'

union all
select 'v63  product pictures',
       case when exists (
         select 1 from information_schema.columns
         where table_schema = 'public' and table_name = 'items'
           and column_name = 'image_path'
       ) and exists (select 1 from storage.buckets where id = 'product-images')
            then 'APPLIED' else 'MISSING' end,
       'items.image_path + product-images bucket'

union all
select 'v64  POS sale guard + Edit Sale',
       case when exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                           and proname = 'pos_record_sale')
            then 'APPLIED' else 'MISSING' end,
       'pos_record_sale() function'

-- Widened, not added: the cashier arm no longer limits to auth.uid().
union all
select 'v65  every cashier sees every order',
       case when exists (
         select 1 from pg_policies
         where schemaname = 'public' and tablename = 'orders'
           and policyname = 'orders_select'
           and qual ilike '%can_handle_orders()%' and qual not ilike '%auth.uid()%'
       ) then 'APPLIED' else 'MISSING' end,
       'orders_select has no "own orders only" limit'

union all
select 'v66  Edit Sale fix (_item_status bigint)',
       case when exists (
         select 1 from pg_proc
         where pronamespace = 'public'::regnamespace and proname = '_item_status'
           and pg_get_function_identity_arguments(oid) like 'p_stock bigint%'
       ) then 'APPLIED' else 'MISSING' end,
       '_item_status(bigint, text) function'

union all
select 'v67  no referral loops',
       case when exists (select 1 from pg_trigger
                          where tgname = 'members_guard_referrer' and not tgisinternal)
            then 'APPLIED' else 'MISSING' end,
       'members_guard_referrer trigger'

order by 1;

-- ── The ledger (v45 onward) ────────────────────────────────────────
-- Run separately; it errors if v45 itself is missing. Lists what was
-- recorded as run. v48 never wrote its own row, so it shows only if
-- someone added it by hand; trust the check above for v48.
--
--   select version, name, applied_at::date as applied, verified
--     from public.schema_migrations
--    where version >= 45
--    order by version;
