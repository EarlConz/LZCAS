-- ═══════════════════════════════════════════════════════════════════
-- Which of v38–v44 are actually applied to THIS project?
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

select 'v38  member cashier stock'   as migration,
       case when exists (
         select 1 from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'member_branch_stock'
       ) then 'APPLIED' else 'MISSING' end as status,
       'member_branch_stock() RPC' as looks_for

union all
select 'v39  announcement audiences',
       case when exists (
         select 1 from pg_constraint
         where conrelid = 'public.announcements'::regclass
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

order by 1;
