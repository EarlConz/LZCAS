-- Run this in the Supabase SQL editor to create online tables matching
-- the current local Drift/SQLite schema.
--
-- This app currently syncs with the Supabase anon key and does not sign in a
-- user yet, so Row Level Security must be disabled for these tables. If RLS is
-- enabled without matching policies, uploads fail with:
-- "new row violates row-level security policy".
--
-- For production, add authentication and owner/team columns before enabling RLS.

create table if not exists public.items (
  id bigint primary key,
  name text not null,
  category text,
  stock integer not null default 0,
  last_updated timestamptz,
  status text
);

create table if not exists public.members (
  id bigint primary key,
  last_name text,
  first_name text,
  middle_name text,
  role text,
  contact_no text,
  birthday text,
  address text,
  referrer text,
  referrer_id bigint,
  qr text,
  id_type text,
  id_number text,
  id_image_path text,
  level integer not null default 1
);

create table if not exists public.sales (
  id bigint primary key,
  item_id bigint not null,
  buyer_id bigint,
  item_name text not null,
  quantity integer not null,
  price integer not null default 0,
  timestamp timestamptz not null default now()
);

create table if not exists public.member_transactions (
  id bigint primary key,
  member_id bigint not null,
  sale_id bigint,
  item_id bigint,
  item_name text,
  quantity integer default 0,
  price integer default 0,
  timestamp timestamptz default now()
);

create table if not exists public.reseller_levels (
  level integer primary key,
  remittance_min integer not null default 0,
  remittance_max integer not null default 0,
  cash_advance integer not null default 0
);

alter table public.items disable row level security;
alter table public.members disable row level security;
alter table public.sales disable row level security;
alter table public.member_transactions disable row level security;
alter table public.reseller_levels disable row level security;
