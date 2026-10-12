-- ═══════════════════════════════════════════════════════════════════
-- Snapshot: a copy of every public table, inside the same database
--
-- For a project without dashboard backups (free tier). Before the
-- delivery migrations go on production (2026-10-12), this copies each
-- table in `public` into a new schema, snapshot_YYYYMMDD, rows and all.
-- If a migration damages data, the rows can be put back from there.
--
-- What it is not: an off-site backup. If the whole project were lost,
-- so would this be. It does not copy auth users (the migrations never
-- touch them), Storage files, or functions and policies (each migration
-- has a rollback in supabase/rollbacks/ for those).
--
-- Safe: it only creates the new schema and copies into it. It refuses if
-- today's snapshot already exists, so it never overwrites one. The
-- schema is not exposed through the API, and access is revoked from the
-- app's roles, so the copies (members' passwords included) are only
-- readable from the SQL editor.
--
-- Run the whole file at once. The result lists every table with its row
-- count in public and in the snapshot: the two columns must match.
--
-- Remove it once the release has settled:
--   drop schema snapshot_YYYYMMDD cascade;
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  v_schema text := 'snapshot_' || to_char(now() at time zone 'Asia/Manila', 'YYYYMMDD');
  t        record;
begin
  if exists (select 1 from pg_namespace where nspname = v_schema) then
    raise exception 'Refused: % already exists. Drop it first if you really mean to take it again.', v_schema;
  end if;

  execute format('create schema %I', v_schema);
  execute format('revoke all on schema %I from public, anon, authenticated', v_schema);

  for t in
    select c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
     order by c.relname
  loop
    execute format('create table %I.%I as table public.%I', v_schema, t.relname, t.relname);
  end loop;

  execute format('comment on schema %I is %L', v_schema,
                 'Copy of public tables taken ' || now() || ' before the delivery migrations.');
end;
$$;

-- ── Check: every table, rows in public vs the snapshot ─────────────
select c.relname as table_name,
       (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from public.%I', c.relname), false, true, '')))[1]::text::bigint as rows_public,
       (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %I.%I', s.nspname, c.relname), false, true, '')))[1]::text::bigint as rows_snapshot
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
  join lateral (
    select nspname from pg_namespace
     where nspname = 'snapshot_' || to_char(now() at time zone 'Asia/Manila', 'YYYYMMDD')
  ) s on true
 where c.relkind in ('r', 'p')
 order by c.relname;
