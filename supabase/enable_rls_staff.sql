-- ═══════════════════════════════════════════════════════════════════
-- Re-enable RLS on the app tables, with policies that let STAFF
-- (admin AND cashier) do everything admins could — fixing the
-- "admin action only" rejection cashiers hit when adding members.
--
-- Supersedes fix_rls_cashier.sql (that one DISABLED rls — do not use it).
--
-- Model (mirrors the existing packages/categories pattern):
--   • Everyone logged in can READ the operational tables. This is
--     required — reseller earnings walk the whole members/sales tree
--     client-side, and the member dashboard reads its own rows.
--   • Only STAFF can INSERT / UPDATE / DELETE.
--   • Exception: a member may UPDATE their OWN members row (profile edit).
--
--   profiles is intentionally LEFT RLS-OFF (see note at the bottom).
--
-- Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- ── Helper: is the current auth user staff? ────────────────────────
-- Staff = the back-office roles: admin, cashier, inventory. All three
-- write to the operational tables (cashier POS, inventory product/stock
-- management), so all three must pass. Member/reseller roles do NOT.
-- SECURITY DEFINER so it reads profiles regardless of RLS.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'cashier', 'inventory')
  );
$$;

-- ═══════════════════════════════════════════════════════════════════
-- MEMBERS — open read; staff write; a member may edit their own row.
-- ═══════════════════════════════════════════════════════════════════
alter table public.members enable row level security;

drop policy if exists "members_select"        on public.members;
drop policy if exists "members_insert_staff"  on public.members;
drop policy if exists "members_update_staff"  on public.members;
drop policy if exists "members_delete_staff"  on public.members;

create policy "members_select" on public.members
  for select to authenticated
  using (true);

create policy "members_insert_staff" on public.members
  for insert to authenticated
  with check (public.is_staff());

-- Staff can update any member; a member can update only their own row.
-- (Soft-delete is an UPDATE of is_deleted, so it lives here — staff.)
create policy "members_update_staff" on public.members
  for update to authenticated
  using (
    public.is_staff()
    or id = (select p.member_id from public.profiles p where p.id = auth.uid())
  )
  with check (
    public.is_staff()
    or id = (select p.member_id from public.profiles p where p.id = auth.uid())
  );

create policy "members_delete_staff" on public.members
  for delete to authenticated
  using (public.is_staff());

-- ═══════════════════════════════════════════════════════════════════
-- SALES, ITEMS, STOCK_MOVEMENTS, MEMBER_TRANSACTIONS, PENDING_REQUESTS
-- Same shape: open read (needed for earnings/POS/dashboards),
-- staff-only writes. Applied in a loop so all five stay identical.
-- ═══════════════════════════════════════════════════════════════════
do $$
declare
  t text;
begin
  foreach t in array array[
    'sales', 'items', 'stock_movements',
    'member_transactions', 'pending_requests'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);

    execute format('drop policy if exists %I on public.%I', t || '_select',       t);
    execute format('drop policy if exists %I on public.%I', t || '_insert_staff', t);
    execute format('drop policy if exists %I on public.%I', t || '_update_staff', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete_staff', t);

    execute format(
      'create policy %I on public.%I for select to authenticated using (true)',
      t || '_select', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check (public.is_staff())',
      t || '_insert_staff', t);
    execute format(
      'create policy %I on public.%I for update to authenticated using (public.is_staff()) with check (public.is_staff())',
      t || '_update_staff', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated using (public.is_staff())',
      t || '_delete_staff', t);
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- PROFILES — deliberately kept RLS-OFF. The login-by-username flow
-- reads profiles BEFORE authenticating (anon role), and role detection
-- reads it on every login; an RLS policy there silently breaks login
-- and misroutes admins to the cashier view. Leave it disabled.
-- ═══════════════════════════════════════════════════════════════════
alter table public.profiles disable row level security;

-- ── Verify ─────────────────────────────────────────────────────────
select relname as table_name, relrowsecurity as rls_enabled
  from pg_class
  where relnamespace = 'public'::regnamespace and relkind = 'r'
    and relname in (
      'members','sales','items','stock_movements',
      'member_transactions','pending_requests','profiles'
    )
  order by relname;
-- Expect: profiles = false; all others = true.

select tablename, policyname, cmd
  from pg_policies
  where schemaname = 'public'
    and tablename in (
      'members','sales','items','stock_movements',
      'member_transactions','pending_requests'
    )
  order by tablename, cmd;
-- Expect: each table has a select + insert + update + delete policy.
