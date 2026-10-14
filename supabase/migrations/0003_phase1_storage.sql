-- =====================================================================
-- دكتوري — المرحلة الأولى: تخزين مستندات توثيق الأطباء (خاص)
-- Private bucket for doctor verification documents.
-- Path convention: <doctor_uid>/<timestamp>_<filename>
-- Only the doctor (own folder) and admins can read; files are opened
-- through short-lived signed URLs from the app.
-- NOTE: uses Supabase's storage schema — not covered by the local test shim.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verification-docs', 'verification-docs', false, 10485760,
        array['image/jpeg', 'image/png', 'application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy "verification: doctor uploads to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (select 1 from public.doctors where id = auth.uid())
  );

create policy "verification: doctor or admin reads"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );
-- No update/delete policies: submitted documents stay as submitted.
