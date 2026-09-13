-- Rollback for migration v47 — Member saved location.

alter table public.members drop column if exists latitude;
alter table public.members drop column if exists longitude;
alter table public.members drop column if exists location_updated_at;
-- `address` predates v47 (it is the member's mailing address) — keep it.
