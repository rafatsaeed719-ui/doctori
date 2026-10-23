-- =====================================================================
-- دكتوري — 0016: صور العروض والإعلانات (عامة)
-- Public bucket; each user uploads only inside their own folder <uid>/…
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('offers', 'offers', true, 3145728, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "offers: upload own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'offers' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "offers: read"
  on storage.objects for select to authenticated
  using (bucket_id = 'offers');
create policy "offers: delete own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'offers' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
