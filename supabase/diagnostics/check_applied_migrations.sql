-- ═══════════════════════════════════════════════════════════════════
-- Which migrations are actually applied to THIS project? (v35 onward)
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

order by 1;
