-- Rollback for migration v37 — Cashier / Branch Cashier saved location.

drop index if exists public.idx_profiles_cashier_location;
alter table public.profiles drop column if exists latitude;
alter table public.profiles drop column if exists longitude;
alter table public.profiles drop column if exists address;
alter table public.profiles drop column if exists updated_at;
