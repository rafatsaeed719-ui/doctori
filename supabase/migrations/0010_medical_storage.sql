-- =====================================================================
-- دكتوري — 0010: تخزين الملف الطبي (خاص)
-- Private bucket. Path: <patient_id>/<timestamp>_<name>. Opened only through short-lived signed URLs.
-- Readable by the patient, and by doctors (or permitted assistants) the patient shares the file with.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('medical-files', 'medical-files', false, 52428800,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic',
              'video/mp4', 'video/quicktime', 'video/3gpp', 'video/webm',
              'application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "medical: patient uploads own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'medical-files'
              and (storage.foldername(name))[1] = auth.uid()::text
              and exists (select 1 from public.patients where id = auth.uid()));

create policy "medical: read shared"
  on storage.objects for select to authenticated
  using (bucket_id = 'medical-files'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.can_view_medical_object(name)));

create policy "medical: patient deletes own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'medical-files' and (storage.foldername(name))[1] = auth.uid()::text);
