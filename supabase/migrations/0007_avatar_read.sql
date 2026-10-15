-- =====================================================================
-- دكتوري — 0007: إصلاح رفع صور البروفايل
-- Storage needs a SELECT policy for uploads that may overwrite/check existing files.
-- Avatars are public profile photos, so any signed-in user may read them.
-- =====================================================================
create policy "avatars: read"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');
