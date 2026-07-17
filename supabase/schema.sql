-- Minimal schema. Safe to re-run — preserves existing profiles & auth users.
-- Business data tables are dropped and recreated. Profiles are NOT dropped.
drop table if exists public.member_transactions cascade;
drop table if exists public.sales cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.items cascade;
drop table if exists public.members cascade;
drop table if exists public.pending_requests cascade;
drop table if exists public.withdrawal_requests cascade;

-- Profiles: create only if missing — never drop (preserves admin users)
create table if not exists public.profiles (
  id uuid primary key,
  username text not null,
  email text,
  role text not null default 'cashier',
  member_id bigint references public.members(id),
  created_at timestamptz not null default now()
);

-- Add email column to existing profiles (safe to re-run)
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists member_id bigint;

-- Auto-populate email on new auth.users (so username→email resolution works)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    new.email,
    'cashier'
  )
  on conflict (id) do update
    set email = excluded.email;
  return new;
end;
$$ language plpgsql security definer;

-- Recreate trigger (idempotent)
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS off: the app reads profiles to determine user roles on every login.
-- An RLS policy that blocks reads will silently redirect admins to cashier.
alter table public.profiles disable row level security;

create table public.items (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  name text not null, category text,
  stock integer not null default 0, last_updated timestamptz, status text
);

create table public.members (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  last_name text, first_name text, middle_name text, role text,
  contact_no text, birthday text, address text, referrer text,
  referrer_id bigint, qr text, id_type text, id_number text,
  id_image_path text, email text,
  is_deleted boolean not null default false
);

-- Buyer / member name stored at transaction time so names survive deletion
alter table public.sales add column if not exists buyer_name text;

create table public.sales (
  id bigint generated always as identity primary key,
  user_id uuid not null, item_id bigint not null, buyer_id bigint,
  item_name text not null, quantity integer not null,
  price integer not null default 0, timestamp timestamptz not null default now(),
  -- Set when the sale is a package availment (no FK: history must survive
  -- package deletion). Package sales are excluded from product metrics.
  package_id bigint
);

create table public.member_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null, member_id bigint not null, sale_id bigint,
  item_id bigint, item_name text, quantity integer default 0,
  price integer default 0, timestamp timestamptz default now()
);

create table public.stock_movements (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  item_id bigint not null,
  item_name text not null,
  quantity integer not null,
  movement_type text not null,
  reason text,
  created_at timestamptz not null default now()
);

create table public.pending_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  item_id bigint,                      -- nullable: NULL for member requests
  item_name text,                      -- nullable: NULL for member requests
  member_id bigint,                    -- for delete_member requests
  member_name text,                    -- stored name (survives deletion)
  request_type text not null,          -- 'delete', 'reduce_stock', 'delete_member'
  quantity integer,                    -- for reduce_stock
  price integer,
  notes text,
  reason text,                         -- reason for the request
  rejection_reason text,               -- admin's reason when rejecting
  status text not null default 'pending', -- pending, approved, rejected
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ── Admin-viewable passwords (client requirement) ────────────────
-- Plaintext password columns so admins can view/reset user credentials.
alter table public.profiles add column if not exists password text;
alter table public.members add column if not exists password text;

-- ── RLS disabled for all app tables (app uses anon key) ────────
alter table public.profiles disable row level security;
alter table public.items disable row level security;
alter table public.members disable row level security;
alter table public.sales disable row level security;
alter table public.stock_movements disable row level security;
alter table public.member_transactions disable row level security;
alter table public.pending_requests disable row level security;

-- ═══════════════════════════════════════════════════════════════════
-- ── Performance Indexes (safe to re-run) ─────────────────────────
-- ═══════════════════════════════════════════════════════════════════

-- 1. Tenant isolation (user_id on every table)
create index if not exists idx_items_user_id on public.items (user_id);
create index if not exists idx_members_user_id on public.members (user_id);
create index if not exists idx_sales_user_id on public.sales (user_id);
create index if not exists idx_stock_movements_user_id on public.stock_movements (user_id);
create index if not exists idx_member_transactions_user_id on public.member_transactions (user_id);
create index if not exists idx_pending_requests_user_id on public.pending_requests (user_id);

-- 2. Date-range queries (timestamp on sales, stock_movements)
create index if not exists idx_sales_timestamp on public.sales (timestamp desc);
create index if not exists idx_stock_movements_created_at on public.stock_movements (created_at desc);
create index if not exists idx_pending_requests_created_at on public.pending_requests (created_at desc);

-- 3. Foreign-key / join lookups
create index if not exists idx_sales_item_id on public.sales (item_id);
create index if not exists idx_sales_buyer_id on public.sales (buyer_id);
create index if not exists idx_stock_movements_item_id on public.stock_movements (item_id);
create index if not exists idx_member_transactions_item_id on public.member_transactions (item_id);
create index if not exists idx_member_transactions_member_id on public.member_transactions (member_id);
create index if not exists idx_member_transactions_sale_id on public.member_transactions (sale_id);
create index if not exists idx_members_referrer_id on public.members (referrer_id);
create index if not exists idx_pending_requests_item_id on public.pending_requests (item_id);
create index if not exists idx_pending_requests_member_id on public.pending_requests (member_id);

-- 4. Status / type partial indexes (low-cardinality columns — smaller & faster)
create index if not exists idx_pending_requests_pending
  on public.pending_requests (status) where status = 'pending';

-- 5. Composite indexes for frequent multi-column filters
create index if not exists idx_pending_requests_status_created
  on public.pending_requests (status, created_at desc);

-- 6. Trigram indexes for ILIKE '%search%' — requires pg_trgm extension
create extension if not exists pg_trgm with schema extensions;
create index if not exists idx_items_name_trgm
  on public.items using gin (name extensions.gin_trgm_ops);
create index if not exists idx_members_last_name_trgm
  on public.members using gin (last_name extensions.gin_trgm_ops);
create index if not exists idx_members_first_name_trgm
  on public.members using gin (first_name extensions.gin_trgm_ops);
create index if not exists idx_sales_item_name_trgm
  on public.sales using gin (item_name extensions.gin_trgm_ops);
create index if not exists idx_sales_buyer_name_trgm
  on public.sales using gin (buyer_name extensions.gin_trgm_ops);

-- ── First admin setup (run once manually) ────────────────────────
-- After creating your admin user via Supabase Dashboard → Authentication,
-- copy the user's UUID and run:
--
--   INSERT INTO public.profiles (id, username, role)
--   VALUES ('<paste-uuid>', '<your-email>', 'admin')
--   ON CONFLICT (id) DO UPDATE SET role = 'admin';

-- ═══════════════════════════════════════════════════════════════════
-- ── Package Management ────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.packages (
  id bigint generated always as identity primary key,
  name text not null,
  price integer not null default 0,
  direct_referral_bonus integer not null default 0,
  indirect_referral_bonus integer not null default 0,
  chairmans_bonus integer not null default 0,
  repeat_purchase_json text not null default '{}',
  group_sales_direct integer not null default 0,
  group_sales_indirect integer not null default 0,
  created_at timestamptz not null default now()
);

-- ── Packages RLS: everyone logged in can read, only admins can write ──
-- Helper: check whether the current auth user is an admin.
-- SECURITY DEFINER so it works even if profiles gets RLS later.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

alter table public.packages enable row level security;

drop policy if exists "packages_read_authenticated" on public.packages;
create policy "packages_read_authenticated" on public.packages
  for select to authenticated
  using (true);

drop policy if exists "packages_insert_admin" on public.packages;
create policy "packages_insert_admin" on public.packages
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "packages_update_admin" on public.packages;
create policy "packages_update_admin" on public.packages
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "packages_delete_admin" on public.packages;
create policy "packages_delete_admin" on public.packages
  for delete to authenticated
  using (public.is_admin());

-- Link members to packages
alter table public.members add column if not exists package_id bigint
  references public.packages(id);

-- Mark package availments in sales (safe to re-run).
-- A sale is a package sale iff package_id is not null; item_id 0 alone is
-- NOT reliable (CSV-imported sales also use item_id 0).
alter table public.sales add column if not exists package_id bigint;
-- Backfill: historical package sales used item_id 0 + the package's name
update public.sales s set package_id = p.id
  from public.packages p
  where s.package_id is null and s.item_id = 0
    and lower(s.item_name) = lower(p.name);

-- Keep package availment names in sync with the catalog (safe to re-run).
-- The app propagates renames on updatePackage(); this repairs rows renamed
-- before that behavior existed.
update public.sales s set item_name = p.name
  from public.packages p
  where s.package_id = p.id and s.item_name <> p.name;

-- Seed default packages (safe to re-run with ON CONFLICT)
insert into public.packages (id, name, price, direct_referral_bonus, indirect_referral_bonus, chairmans_bonus, repeat_purchase_json, group_sales_direct, group_sales_indirect)
OVERRIDING SYSTEM VALUE
values
  (1, 'STARTER PACK',   3999, 300, 150, 50,  '{"pack":5,"box":5,"bottle":20}', 3, 2),
  (2, 'AMBASSADOR PACK', 7999, 600, 300, 100, '{"pack":5,"box":5,"bottle":20}', 3, 2)
on conflict (id) do update set
  name                 = excluded.name,
  price                = excluded.price,
  direct_referral_bonus  = excluded.direct_referral_bonus,
  indirect_referral_bonus = excluded.indirect_referral_bonus,
  chairmans_bonus       = excluded.chairmans_bonus,
  repeat_purchase_json  = excluded.repeat_purchase_json,
  group_sales_direct    = excluded.group_sales_direct,
  group_sales_indirect  = excluded.group_sales_indirect;

-- ═══════════════════════════════════════════════════════════════════
-- ── Category Management ───────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.categories (
  id bigint generated always as identity primary key,
  name text not null unique,
  commission_rate integer not null default 0
);

-- ── Categories RLS: everyone logged in can read, only admins can write ──
-- (uses the is_admin() helper defined in the Packages section above)
alter table public.categories enable row level security;

drop policy if exists "categories_read_authenticated" on public.categories;
create policy "categories_read_authenticated" on public.categories
  for select to authenticated
  using (true);

drop policy if exists "categories_insert_admin" on public.categories;
create policy "categories_insert_admin" on public.categories
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "categories_update_admin" on public.categories;
create policy "categories_update_admin" on public.categories
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "categories_delete_admin" on public.categories;
create policy "categories_delete_admin" on public.categories
  for delete to authenticated
  using (public.is_admin());

-- Seed default categories
insert into public.categories (name, commission_rate) values
  ('Pack', 5), ('Box', 5), ('Bottle', 20)
on conflict (name) do update set commission_rate = excluded.commission_rate;

-- ═══════════════════════════════════════════════════════════════════
-- ── Earnings history (snapshot ledger) ─────────────────────────────
-- ═══════════════════════════════════════════════════════════════════
-- Earnings/balance are computed live from the referral tree and sales,
-- so they have no natural event log (and can decrease). The app records
-- a snapshot whenever the computed values change; deltas are stored so
-- the history reads as a ledger.

create table if not exists public.earnings_history (
  id bigint generated always as identity primary key,
  member_id bigint not null,
  total_earnings integer not null default 0,
  balance integer not null default 0,
  earnings_delta integer not null default 0,
  balance_delta integer not null default 0,
  -- Component snapshot: where total_earnings comes from. Diffing two
  -- consecutive rows attributes a change to its source(s).
  -- (balance's only source is the direct referral bonus)
  indirect_bonus integer not null default 0,
  group_sales integer not null default 0,
  repeat_purchase integer not null default 0,
  chairman_bonus integer not null default 0,
  recorded_at timestamptz not null default now()
);

-- Component columns for pre-existing installs (safe to re-run)
alter table public.earnings_history add column if not exists indirect_bonus integer not null default 0;
alter table public.earnings_history add column if not exists group_sales integer not null default 0;
alter table public.earnings_history add column if not exists repeat_purchase integer not null default 0;
alter table public.earnings_history add column if not exists chairman_bonus integer not null default 0;

create index if not exists idx_earnings_history_member
  on public.earnings_history (member_id, recorded_at desc);

alter table public.earnings_history enable row level security;

-- Members see and write their own history; admins see everything.
drop policy if exists "earnings_history_select_own" on public.earnings_history;
create policy "earnings_history_select_own" on public.earnings_history
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = earnings_history.member_id
    )
  );

drop policy if exists "earnings_history_insert_own" on public.earnings_history;
create policy "earnings_history_insert_own" on public.earnings_history
  for insert to authenticated
  with check (
    public.is_admin()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = earnings_history.member_id
    )
  );

-- ═══════════════════════════════════════════════════════════════════
-- ── Withdrawal Requests ────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════
-- Members can request to withdraw funds from their Total Earnings or
-- Balance pools. Admins review, approve, or reject each request.

create table if not exists public.withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  member_id bigint not null,
  source_bucket text not null check (source_bucket in ('total_earnings', 'balance')),
  requested_amount integer not null check (requested_amount > 0),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Indexes
create index if not exists idx_withdrawal_requests_member
  on public.withdrawal_requests (member_id, created_at desc);
create index if not exists idx_withdrawal_requests_status
  on public.withdrawal_requests (status, created_at desc);

alter table public.withdrawal_requests enable row level security;

-- Members can only see and insert their own withdrawal requests.
-- Ownership uses a SECURITY DEFINER helper to safely map auth.uid() → bigint
-- member ID without tripping over cross-table RLS on the members table.
-- Admins have full read/write access via is_admin() bypass.

-- Helper: resolve the authenticated user's numeric member ID.
-- SECURITY DEFINER so it bypasses any RLS on public.members.
create or replace function public.get_current_member_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select id from public.members
  where user_id = auth.uid()
  limit 1;
$$;

drop policy if exists "withdrawal_requests_select_own" on public.withdrawal_requests;
create policy "withdrawal_requests_select_own" on public.withdrawal_requests
  for select to authenticated
  using (
    public.is_admin()
    or member_id = public.get_current_member_id()
  );

drop policy if exists "withdrawal_requests_insert_own" on public.withdrawal_requests;
create policy "withdrawal_requests_insert_own" on public.withdrawal_requests
  for insert to authenticated
  with check (
    public.is_admin()
    or member_id = public.get_current_member_id()
  );

drop policy if exists "withdrawal_requests_update_admin" on public.withdrawal_requests;
create policy "withdrawal_requests_update_admin" on public.withdrawal_requests
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

