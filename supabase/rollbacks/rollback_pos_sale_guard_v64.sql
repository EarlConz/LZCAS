-- ═══════════════════════════════════════════════════════════════════
-- Rollback v64 — POS sale guard and Edit Sale
--
-- Drops the three functions. An app built after v64 then fails at
-- checkout and on Edit Sale: run the app version from before v64 too.
-- Sales already recorded through them are ordinary sales rows and stay.
-- ═══════════════════════════════════════════════════════════════════

drop function if exists public.admin_edit_sale_group(uuid, timestamptz, bigint, jsonb);
drop function if exists public.pos_record_sale(jsonb, bigint, text, timestamptz);
drop function if exists public._item_status(integer, text);

delete from public.schema_migrations where version = 64;

notify pgrst, 'reload schema';
