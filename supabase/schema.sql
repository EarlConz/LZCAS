-- Minimal schema. Safe to re-run — preserves existing profiles & auth users.
-- Business data tables are dropped and recreated. Profiles are NOT dropped.
drop table if exists public.member_transactions cascade;
drop table if exists public.sales cascade;
drop table if exists public.borrows cascade;
drop table if exists public.stock_movements cascade;
drop table if exists public.items cascade;
drop table if exists public.members cascade;
drop table if exists public.reseller_levels cascade;

-- Profiles: create only if missing — never drop (preserves admin users)
create table if not exists public.profiles (
  id uuid primary key,
  username text not null,
  email text,
  role text not null default 'cashier',
  created_at timestamptz not null default now()
);

-- Add email column to existing profiles (safe to re-run)
alter table public.profiles add column if not exists email text;

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

-- Trigger: auto-create profile for every new auth user
-- Does NOT overwrite existing profiles (ON CONFLICT DO NOTHING)
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', new.email), 'cashier')
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── RLS disabled for all app tables (app uses anon key) ────────
alter table public.profiles disable row level security;
alter table public.items disable row level security;
alter table public.members disable row level security;
alter table public.sales disable row level security;
alter table public.borrows disable row level security;
alter table public.stock_movements disable row level security;
alter table public.member_transactions disable row level security;
alter table public.reseller_levels disable row level security;

-- ── First admin setup (run once manually) ────────────────────────
-- After creating your admin user via Supabase Dashboard → Authentication,
-- copy the user's UUID and run:
--
--   INSERT INTO public.profiles (id, username, role)
--   VALUES ('<paste-uuid>', '<your-email>', 'admin')
--   ON CONFLICT (id) DO UPDATE SET role = 'admin';
