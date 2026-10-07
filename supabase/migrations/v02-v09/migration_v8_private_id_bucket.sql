-- ═══════════════════════════════════════════════════════════════════
-- Migration v8 — Private ID-photo bucket (HIGH-4)
--
-- The member-ids bucket was public with guessable keys ({memberId}.jpg),
-- so government IDs were world-readable at predictable URLs. This makes
-- the bucket private and restricts BOTH reading (signing) and writing to
-- staff — ID photos are only ever shown in staff-facing member views, so
-- no member/anon can generate a signed URL to view someone's ID.
--
-- ⚠ Coordinated change: deploy the app build that uses signed URLs
-- (createSignedUrl) FIRST, then run this. On the old build (public URLs)
-- images would stop loading once the bucket is private.
--
-- Requires is_staff() (enable_rls_staff.sql). Safe to re-run.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Make the bucket private (no anonymous public URLs).
update storage.buckets set public = false where id = 'member-ids';

-- 2. Lock storage.objects access for this bucket to STAFF only.
--    SELECT permission is what createSignedUrl checks, so restricting it
--    means only staff can mint a viewable URL for an ID photo.
drop policy if exists "member-ids read"   on storage.objects;
drop policy if exists "member-ids write"  on storage.objects;
drop policy if exists "member-ids update" on storage.objects;

create policy "member-ids read" on storage.objects
  for select to authenticated
  using (bucket_id = 'member-ids' and public.is_staff());

create policy "member-ids write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'member-ids' and public.is_staff());

create policy "member-ids update" on storage.objects
  for update to authenticated
  using (bucket_id = 'member-ids' and public.is_staff())
  with check (bucket_id = 'member-ids' and public.is_staff());

-- ── Verify ─────────────────────────────────────────────────────────
select id, public from storage.buckets where id = 'member-ids';
-- Expect: public = false
