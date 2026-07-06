-- Minimal schema. Safe to re-run — preserves existing profiles & auth users.
-- Business data tables are dropped and recreated. Profiles are NOT dropped.
drop table if exists public.member_transactions cascade;
drop table if exists public.sales cascade;
drop table if exists public.borrows cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.items cascade;
drop table if exists public.members cascade;
drop table if exists public.pending_requests cascade;

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
alter table public.borrows add column if not exists member_name text;

create table public.sales (
  id bigint generated always as identity primary key,
  user_id uuid not null, item_id bigint not null, buyer_id bigint,
  item_name text not null, quantity integer not null,
  price integer not null default 0, timestamp timestamptz not null default now()
);

create table public.member_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null, member_id bigint not null, sale_id bigint,
  item_id bigint, item_name text, quantity integer default 0,
  price integer default 0, timestamp timestamptz default now()
);

create table public.borrows (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  member_id bigint not null,
  item_id bigint not null,
  item_name text not null,
  quantity integer not null,
  quantity_returned integer not null default 0,
  quantity_remitted integer not null default 0,
  price integer not null default 0,
  borrowed_at timestamptz not null default now(),
  due_date timestamptz not null,
  status text not null default 'active',
  notes text,
  settled_at timestamptz
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
  request_type text not null,          -- 'delete', 'reduce_stock', 'delete_member', 'borrow'
  quantity integer,                    -- for reduce_stock / borrow
  price integer,                       -- for borrow: price per item
  notes text,                          -- for borrow: optional notes
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
alter table public.borrows disable row level security;
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
create index if not exists idx_borrows_user_id on public.borrows (user_id);
create index if not exists idx_stock_movements_user_id on public.stock_movements (user_id);
create index if not exists idx_member_transactions_user_id on public.member_transactions (user_id);
create index if not exists idx_pending_requests_user_id on public.pending_requests (user_id);

-- 2. Date-range queries (timestamp on sales, borrows, stock_movements)
create index if not exists idx_sales_timestamp on public.sales (timestamp desc);
create index if not exists idx_borrows_borrowed_at on public.borrows (borrowed_at desc);
create index if not exists idx_stock_movements_created_at on public.stock_movements (created_at desc);
create index if not exists idx_pending_requests_created_at on public.pending_requests (created_at desc);

-- 3. Foreign-key / join lookups
create index if not exists idx_sales_item_id on public.sales (item_id);
create index if not exists idx_sales_buyer_id on public.sales (buyer_id);
create index if not exists idx_borrows_item_id on public.borrows (item_id);
create index if not exists idx_borrows_member_id on public.borrows (member_id);
create index if not exists idx_stock_movements_item_id on public.stock_movements (item_id);
create index if not exists idx_member_transactions_item_id on public.member_transactions (item_id);
create index if not exists idx_member_transactions_member_id on public.member_transactions (member_id);
create index if not exists idx_member_transactions_sale_id on public.member_transactions (sale_id);
create index if not exists idx_members_referrer_id on public.members (referrer_id);
create index if not exists idx_pending_requests_item_id on public.pending_requests (item_id);
create index if not exists idx_pending_requests_member_id on public.pending_requests (member_id);

-- 4. Status / type partial indexes (low-cardinality columns — smaller & faster)
create index if not exists idx_borrows_status_active
  on public.borrows (status) where status in ('active', 'overdue', 'partially_settled');
create index if not exists idx_pending_requests_pending
  on public.pending_requests (status) where status = 'pending';

-- 5. Composite indexes for frequent multi-column filters
create index if not exists idx_borrows_due_date_status
  on public.borrows (due_date, status);
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

alter table public.packages disable row level security;

-- Link members to packages
alter table public.members add column if not exists package_id bigint
  references public.packages(id);

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
