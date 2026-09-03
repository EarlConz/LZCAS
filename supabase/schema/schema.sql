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
  member_id bigint,  -- soft link to members(id); FK omitted so a fresh-DB run doesn't require members to exist first
  created_at timestamptz not null default now()
);

-- Add email column to existing profiles (safe to re-run)
alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists member_id bigint;
-- Per-account mobile-login flag (v29): branch_cashier accounts are desktop-only
-- by default; an admin sets this true to allow that account to log in on mobile.
alter table public.profiles add column if not exists mobile_enabled boolean not null default false;

-- Saved cashier/branch location (v37) — for the member "Nearest Cashiers" map.
alter table public.profiles add column if not exists latitude double precision;
alter table public.profiles add column if not exists longitude double precision;
alter table public.profiles add column if not exists address text;
-- Named for the location specifically: a bare `updated_at` on an accounts
-- table invites a future touch-trigger to repoint it. See migration v37.
alter table public.profiles add column if not exists location_updated_at timestamptz;

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

-- Global key/value config (e.g. legacy low_stock_threshold). Created early so
-- later migrations (v10) that reference it work on a fresh DB. RLS off to match
-- live. Safe to re-run.
create table if not exists public.app_config (
  key text primary key,
  value text not null
);
alter table public.app_config disable row level security;

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

create table public.sales (
  id bigint generated always as identity primary key,
  user_id uuid not null, item_id bigint not null, buyer_id bigint,
  item_name text not null, quantity integer not null,
  price integer not null default 0, timestamp timestamptz not null default now(),
  -- Buyer / member name stored at transaction time so names survive deletion
  buyer_name text,
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
  upgrade_referral_bonus integer not null default 0,
  repeat_purchase_json text not null default '{}',
  group_sales_direct integer not null default 0,
  group_sales_indirect integer not null default 0,
  created_at timestamptz not null default now()
);

-- Add upgrade_referral_bonus to existing packages (safe to re-run)
alter table public.packages add column if not exists upgrade_referral_bonus integer not null default 0;

-- Add hierarchy_rank for tier-based upgrade validation (safe to re-run)
-- Higher rank = higher tier. E.g.: Starter=10, Ambassador=20, future: Pro=15.
alter table public.packages add column if not exists hierarchy_rank integer not null default 0;

-- ── Unified Upgrade RPC ─────────────────────────────────────────────
-- Atomically validates, upgrades, and pays the referrer bonus.
-- The upgrade_referral_bonus comes from the TARGET (new) package, NOT the old one.
create or replace function public.process_package_upgrade(
  p_member_id bigint,
  p_target_package_id bigint
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current_rank     integer;
  v_target_rank      integer;
  v_target_name      text;
  v_target_price     integer;
  v_upgrade_bonus    integer;
  v_referrer_id      bigint;
  v_last             record;
begin
  -- 1. Get the member's current package rank (0 if no package)
  select coalesce(pkgs.hierarchy_rank, 0)
    into v_current_rank
    from public.members m
    left join public.packages pkgs on pkgs.id = m.package_id
    where m.id = p_member_id;

  if not found then
    raise exception 'Member not found (id=%)', p_member_id;
  end if;

  -- 2. Get target package details: rank, name, price, and THE upgrade bonus
  select pkgs.hierarchy_rank, pkgs.name, pkgs.price, pkgs.upgrade_referral_bonus
    into v_target_rank, v_target_name, v_target_price, v_upgrade_bonus
    from public.packages pkgs
    where pkgs.id = p_target_package_id;

  if not found then
    raise exception 'Target package not found (id=%)', p_target_package_id;
  end if;

  -- 3. Enforce upgrade-only: target must be strictly higher tier
  if v_target_rank <= v_current_rank then
    raise exception 'Invalid upgrade: target rank (%) must be greater than current rank (%)',
      v_target_rank, v_current_rank;
  end if;

  -- 4. Update the member's package
  update public.members
    set package_id = p_target_package_id
    where id = p_member_id;

  -- 5. Find the referrer
  select m.referrer_id
    into v_referrer_id
    from public.members m
    where m.id = p_member_id;

  -- 6. Pay the upgrade referral bonus (and nothing else — the
  --    Chairman's Bonus is never touched by upgrades)
  if v_referrer_id is not null and v_upgrade_bonus > 0 then
    -- 6a. Wallet ledger entry (drives the live earnings computation)
    insert into public.member_transactions (
      user_id, member_id, item_name, quantity, price, timestamp
    ) values (
      auth.uid(),
      v_referrer_id,
      'Upgrade Bonus — ' || v_target_name,
      1,
      v_upgrade_bonus,
      now()
    );

    -- 6b. Earnings History entry written at upgrade time so the
    --     referrer sees the transaction immediately. Totals carry
    --     forward from the latest snapshot; only the upgrade
    --     component and the total move.
    select total_earnings, balance,
           indirect_bonus, group_sales, passive_income,
           repeat_purchase, chairman_bonus, upgrade_bonus
      into v_last
      from public.earnings_history
      where member_id = v_referrer_id
      order by recorded_at desc
      limit 1;

    insert into public.earnings_history (
      member_id, total_earnings, balance,
      earnings_delta, balance_delta,
      indirect_bonus, group_sales, passive_income,
      repeat_purchase, chairman_bonus, upgrade_bonus
    ) values (
      v_referrer_id,
      coalesce(v_last.total_earnings, 0) + v_upgrade_bonus,
      coalesce(v_last.balance, 0),
      v_upgrade_bonus,
      0,
      coalesce(v_last.indirect_bonus, 0),
      coalesce(v_last.group_sales, 0),
      coalesce(v_last.passive_income, 0),
      coalesce(v_last.repeat_purchase, 0),
      coalesce(v_last.chairman_bonus, 0),
      coalesce(v_last.upgrade_bonus, 0) + v_upgrade_bonus
    );
  end if;
end;
$$;

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
  passive_income integer not null default 0,
  repeat_purchase integer not null default 0,
  chairman_bonus integer not null default 0,
  upgrade_bonus integer not null default 0,
  recorded_at timestamptz not null default now()
);

-- Component columns for pre-existing installs (safe to re-run)
alter table public.earnings_history add column if not exists indirect_bonus integer not null default 0;
alter table public.earnings_history add column if not exists group_sales integer not null default 0;
alter table public.earnings_history add column if not exists passive_income integer not null default 0;
alter table public.earnings_history add column if not exists repeat_purchase integer not null default 0;
alter table public.earnings_history add column if not exists chairman_bonus integer not null default 0;
alter table public.earnings_history add column if not exists upgrade_bonus integer not null default 0;

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

-- ===========================================================================
-- BRANCH STOCK SYSTEM (v30) — two-tier inventory: central (items.stock) +
-- per branch-cashier allocation. See migrations/migration_v30_branch_stock.sql
-- for full documentation. Included here so a fresh DB has the whole system.
-- ===========================================================================

create table if not exists public.branch_stock (
  owner_id   uuid    not null,
  item_id    bigint  not null,
  quantity   integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (owner_id, item_id)
);
alter table public.branch_stock enable row level security;

create table if not exists public.stock_transfers (
  id            bigint generated always as identity primary key,
  item_id       bigint  not null,
  item_name     text    not null,
  to_owner_id   uuid    not null,
  quantity      integer not null,
  transfer_type text    not null default 'give_out'
                  check (transfer_type in ('give_out','return','adjust')),
  created_by    uuid    not null,
  note          text,
  created_at    timestamptz not null default now()
);
alter table public.stock_transfers enable row level security;

create index if not exists idx_branch_stock_owner     on public.branch_stock (owner_id);
create index if not exists idx_stock_transfers_owner   on public.stock_transfers (to_owner_id);
create index if not exists idx_stock_transfers_created on public.stock_transfers (created_at desc);

-- RLS on; reads only (all writes go through SECURITY DEFINER RPCs which bypass
-- RLS). admin/main-cashier see all; a branch cashier sees only their own rows.
grant select on public.branch_stock    to authenticated;
grant select on public.stock_transfers to authenticated;

drop policy if exists branch_stock_select on public.branch_stock;
create policy branch_stock_select on public.branch_stock
  for select to authenticated
  using (public.can_manage_branch_stock() or owner_id = auth.uid());

drop policy if exists stock_transfers_select on public.stock_transfers;
create policy stock_transfers_select on public.stock_transfers
  for select to authenticated
  using (public.can_manage_branch_stock() or to_owner_id = auth.uid());

-- View is security_invoker = true so the RLS above is enforced through it.
create or replace view public.branch_stock_view
with (security_invoker = true) as
select
  bs.owner_id,
  i.id          as id,
  i.name        as name,
  i.category    as category,
  bs.quantity   as stock,
  bs.updated_at as last_updated,
  case
    when bs.quantity <= 0 then 'Out of Stock'
    when bs.quantity < coalesce(c.low_stock_threshold, 50) then 'Low Stock'
    else 'Good'
  end as status
from public.branch_stock bs
join public.items i on i.id = bs.item_id
left join public.categories c on c.name = i.category;

grant select on public.branch_stock_view to authenticated;

create or replace function public.can_manage_branch_stock()
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin','cashier')
  );
$fn$;

create or replace function public.transfer_stock_to_branch(
  p_item_id bigint, p_owner_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $fn$
declare v_central integer; v_name text; v_username text;
begin
  if not public.can_manage_branch_stock() then raise exception 'Not authorized to transfer stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be a positive number'; end if;
  select username into v_username from public.profiles where id = p_owner_id and role = 'branch_cashier';
  if v_username is null then raise exception 'Recipient is not a branch cashier'; end if;
  select stock, name into v_central, v_name from public.items where id = p_item_id for update;
  if v_central is null then raise exception 'Item % not found', p_item_id; end if;
  if v_central < p_quantity then
    raise exception 'Not enough central stock for % (have %, need %)', v_name, v_central, p_quantity;
  end if;
  update public.items set stock = stock - p_quantity, last_updated = now() where id = p_item_id;
  insert into public.branch_stock (owner_id, item_id, quantity, updated_at)
  values (p_owner_id, p_item_id, p_quantity, now())
  on conflict (owner_id, item_id)
    do update set quantity = public.branch_stock.quantity + excluded.quantity, updated_at = now();
  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, v_name, p_owner_id, p_quantity, 'give_out', auth.uid(), p_note);
  insert into public.stock_movements (user_id, item_id, item_name, quantity, movement_type, reason)
  values (auth.uid(), p_item_id, v_name, p_quantity, 'transfer_out',
    case when p_note is not null and length(trim(p_note)) > 0
         then v_username || ' - ' || p_note else v_username end);
end; $fn$;

create or replace function public.return_branch_stock(
  p_item_id bigint, p_owner_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $fn$
declare v_branch integer; v_name text; v_username text;
begin
  if not public.can_manage_branch_stock() then raise exception 'Not authorized to return stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be a positive number'; end if;
  select quantity into v_branch from public.branch_stock where owner_id = p_owner_id and item_id = p_item_id for update;
  select name into v_name from public.items where id = p_item_id;
  select username into v_username from public.profiles where id = p_owner_id;
  if coalesce(v_branch, 0) < p_quantity then
    raise exception 'Not enough branch stock to return for % (have %, need %)', coalesce(v_name,'item'), coalesce(v_branch,0), p_quantity;
  end if;
  update public.branch_stock set quantity = quantity - p_quantity, updated_at = now() where owner_id = p_owner_id and item_id = p_item_id;
  update public.items set stock = stock + p_quantity, last_updated = now() where id = p_item_id;
  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, coalesce(v_name,''), p_owner_id, -p_quantity, 'return', auth.uid(), p_note);
  insert into public.stock_movements (user_id, item_id, item_name, quantity, movement_type, reason)
  values (auth.uid(), p_item_id, coalesce(v_name,''), p_quantity, 'transfer_in',
    case when p_note is not null and length(trim(p_note)) > 0
         then coalesce(v_username,'branch') || ' - ' || p_note else coalesce(v_username,'branch') end);
end; $fn$;

create or replace function public.adjust_branch_stock(
  p_item_id bigint, p_owner_id uuid, p_new_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $fn$
declare v_old integer; v_name text;
begin
  if not public.can_manage_branch_stock() then raise exception 'Not authorized to adjust stock'; end if;
  if p_new_quantity is null or p_new_quantity < 0 then raise exception 'New quantity must be zero or greater'; end if;
  select quantity into v_old from public.branch_stock where owner_id = p_owner_id and item_id = p_item_id for update;
  v_old := coalesce(v_old, 0);
  select name into v_name from public.items where id = p_item_id;
  insert into public.branch_stock (owner_id, item_id, quantity, updated_at)
  values (p_owner_id, p_item_id, p_new_quantity, now())
  on conflict (owner_id, item_id) do update set quantity = excluded.quantity, updated_at = now();
  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, coalesce(v_name,''), p_owner_id, p_new_quantity - v_old, 'adjust', auth.uid(), p_note);
end; $fn$;

create or replace function public.record_branch_sale(
  p_item_id bigint, p_quantity integer, p_price integer default 0,
  p_buyer_id bigint default null, p_buyer_name text default null, p_timestamp timestamptz default null
) returns bigint language plpgsql security definer set search_path = public as $fn$
declare v_qty integer; v_name text; v_sale_id bigint;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'branch_cashier') then
    raise exception 'Only a branch cashier can record a branch sale';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be a positive number'; end if;
  select quantity into v_qty from public.branch_stock where owner_id = auth.uid() and item_id = p_item_id for update;
  select name into v_name from public.items where id = p_item_id;
  if coalesce(v_qty, 0) < p_quantity then
    raise exception 'Not enough branch stock for % (have %, need %)', coalesce(v_name,'item'), coalesce(v_qty,0), p_quantity;
  end if;
  update public.branch_stock set quantity = quantity - p_quantity, updated_at = now() where owner_id = auth.uid() and item_id = p_item_id;
  insert into public.sales (user_id, item_id, item_name, quantity, price, buyer_id, buyer_name, timestamp)
  values (auth.uid(), p_item_id, coalesce(v_name,''), p_quantity, p_price, p_buyer_id, p_buyer_name, coalesce(p_timestamp, now()))
  returning id into v_sale_id;
  return v_sale_id;
end; $fn$;

grant execute on function public.can_manage_branch_stock() to authenticated;
grant execute on function public.transfer_stock_to_branch(bigint, uuid, integer, text) to authenticated;
grant execute on function public.return_branch_stock(bigint, uuid, integer, text) to authenticated;
grant execute on function public.adjust_branch_stock(bigint, uuid, integer, text) to authenticated;
grant execute on function public.record_branch_sale(bigint, integer, integer, bigint, text, timestamptz) to authenticated;

