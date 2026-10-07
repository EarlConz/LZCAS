-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration v74 — Push notifications for announcements
--
-- Stops the pushes: removes the job, the trigger and the functions.
-- Leaves `announcements.pushed_at` in place (dropping it would make a
-- re-apply mark everything pushed again anyway, and it holds nothing
-- anyone reads). Leaves pg_cron enabled, since other jobs may use it.
-- Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'announcement-push';
  end if;
end;
$$;

drop trigger if exists announcements_push on public.announcements;
drop function if exists public.announcements_queue_push();
drop function if exists public.queue_announcement_pushes();

delete from public.schema_migrations where version = 74;
