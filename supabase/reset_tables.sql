-- ═══════════════════════════════════════════════════════════════════
--  Reset non-essential tables — keeps profiles, categories, packages
--  Run this in the Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Drop transactional tables (order matters due to FK refs) ──
drop table if exists public.earnings_history cascade;
drop table if exists public.member_transactions cascade;
drop table if exists public.borrows cascade;
drop table if exists public.sales cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.pending_requests cascade;
drop table if exists public.items cascade;
drop table if exists public.members cascade;

-- ── 2. Recreate tables ───────────────────────────────────────────

-- Members (referenced by profiles, sales, borrows, etc.)
create table public.members (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  last_name text, first_name text, middle_name text, role text,
  contact_no text, birthday text, address text, referrer text,
  referrer_id bigint, qr text, id_type text, id_number text,
  id_image_path text, email text,
  is_deleted boolean not null default false
);

alter table public.members add column if not exists password text;
alter table public.members add column if not exists package_id bigint
  references public.packages(id);
alter table public.members add column if not exists quota_valid_until timestamptz;
alter table public.members add column if not exists last_remittance_at timestamptz;

-- Items
create table public.items (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  name text not null, category text,
  stock integer not null default 0, last_updated timestamptz, status text
);

-- Sales
create table public.sales (
  id bigint generated always as identity primary key,
  user_id uuid not null, item_id bigint not null, buyer_id bigint,
  item_name text not null, quantity integer not null,
  price integer not null default 0, timestamp timestamptz not null default now(),
  package_id bigint,
  is_remittance boolean not null default false
);
alter table public.sales add column if not exists buyer_name text;
alter table public.sales add column if not exists is_remittance boolean not null default false;
alter table public.sales add column if not exists package_id bigint;

-- Borrows
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
alter table public.borrows add column if not exists member_name text;

-- Member transactions
create table public.member_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null, member_id bigint not null, sale_id bigint,
  item_id bigint, item_name text, quantity integer default 0,
  price integer default 0, timestamp timestamptz default now()
);

-- Stock movements
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

-- Pending requests
create table public.pending_requests (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  item_id bigint,
  item_name text,
  member_id bigint,
  member_name text,
  request_type text not null,
  quantity integer,
  price integer,
  notes text,
  reason text,
  rejection_reason text,
  status text not null default 'pending',
  reviewed_by uuid,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Earnings history
create table public.earnings_history (
  id bigint generated always as identity primary key,
  member_id bigint not null,
  total_earnings integer not null default 0,
  balance integer not null default 0,
  earnings_delta integer not null default 0,
  balance_delta integer not null default 0,
  indirect_bonus integer not null default 0,
  group_sales integer not null default 0,
  repeat_purchase integer not null default 0,
  chairman_bonus integer not null default 0,
  recorded_at timestamptz not null default now()
);

-- ── 3. Recreate indexes ──────────────────────────────────────────
create index if not exists idx_items_user_id on public.items (user_id);
create index if not exists idx_members_user_id on public.members (user_id);
create index if not exists idx_sales_user_id on public.sales (user_id);
create index if not exists idx_borrows_user_id on public.borrows (user_id);
create index if not exists idx_stock_movements_user_id on public.stock_movements (user_id);
create index if not exists idx_member_transactions_user_id on public.member_transactions (user_id);
create index if not exists idx_pending_requests_user_id on public.pending_requests (user_id);

create index if not exists idx_sales_timestamp on public.sales (timestamp desc);
create index if not exists idx_borrows_borrowed_at on public.borrows (borrowed_at desc);
create index if not exists idx_stock_movements_created_at on public.stock_movements (created_at desc);
create index if not exists idx_pending_requests_created_at on public.pending_requests (created_at desc);

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

create index if not exists idx_borrows_status_active
  on public.borrows (status) where status in ('active', 'overdue', 'partially_settled');
create index if not exists idx_pending_requests_pending
  on public.pending_requests (status) where status = 'pending';

create index if not exists idx_borrows_due_date_status
  on public.borrows (due_date, status);
create index if not exists idx_pending_requests_status_created
  on public.pending_requests (status, created_at desc);

create index if not exists idx_earnings_history_member
  on public.earnings_history (member_id, recorded_at desc);

-- ── 4. Disable RLS (app uses anon key) ───────────────────────────
alter table public.items disable row level security;
alter table public.members disable row level security;
alter table public.sales disable row level security;
alter table public.borrows disable row level security;
alter table public.stock_movements disable row level security;
alter table public.member_transactions disable row level security;
alter table public.pending_requests disable row level security;

-- ── 5. Recreate triggers ─────────────────────────────────────────
-- Borrow due-date trigger
create or replace function public.set_borrow_due_date()
returns trigger as $$
begin
  new.due_date := coalesce(new.borrowed_at, now()) + interval '10 days';
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_borrow_due_date on public.borrows;
create trigger trg_borrow_due_date
  before insert on public.borrows
  for each row execute function public.set_borrow_due_date();

-- ── Done ─────────────────────────────────────────────────────────
-- profiles, categories, and packages were NOT touched.
-- All other tables were dropped and recreated fresh.
