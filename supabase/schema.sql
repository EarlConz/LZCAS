-- Minimal schema — no FK to auth.users, no triggers. Run in SQL Editor.
drop table if exists public.member_transactions cascade;
drop table if exists public.sales cascade;
drop table if exists public.borrows cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.items cascade;
drop table if exists public.members cascade;
drop table if exists public.reseller_levels cascade;
drop table if exists public.profiles cascade;
drop function if exists public.handle_new_user() cascade;

create table public.profiles (
  id uuid primary key,
  username text not null,
  role text not null default 'cashier',
  created_at timestamptz not null default now()
);

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
  id_image_path text, level integer not null default 1
);

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

create table public.reseller_levels (
  level integer not null, user_id uuid not null,
  remittance_min integer not null default 0,
  remittance_max integer not null default 0,
  cash_advance integer not null default 0,
  primary key (level, user_id)
);

-- Upsert admin profile
INSERT INTO public.profiles (id, username, role)
SELECT id, email, 'admin' FROM auth.users WHERE email = 'admin@stockpile.local'
ON CONFLICT (id) DO UPDATE SET role = 'admin';
