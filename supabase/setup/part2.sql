-- =====================================================================
-- دكتوري — الجزء 2 من 2: دوال التطبيق، التخزين، الحسابات، الإدارة
-- شغّل الجزء 1 الأول. آمن للتشغيل أكتر من مرة.
-- =====================================================================
drop function if exists public.doctor_my_patients();
drop function if exists public.doctor_incoming_requests();
drop function if exists public.patient_my_doctors();
drop function if exists public.doctor_activate_with_code(text);
drop function if exists public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int);

-- =====================================================================
-- دكتوري — المرحلة الأولى: دوال الشاشات (قوائم جاهزة لكل دور)
-- Read-model functions used by the app screens. Each returns only what
-- that screen needs, after checking who is calling.
-- =====================================================================

-- Who am I? Drives which home screen the app opens.
create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'locale', p.locale, 'is_suspended', p.is_suspended,
    'doctor_status', d.status,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null))
  from profiles p left join doctors d on d.id = p.id
  where p.id = auth.uid();
$$;

-- Doctor: pending requests with the minimum the doctor needs to decide.
-- The patient chose to send these details by sending the request.
create or replace function public.doctor_incoming_requests()
returns table (request_id uuid, patient_name text, gender public.gender, age int,
               message text, share_scope public.share_scope, clinic_name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         r.message, r.share_scope, c.name, r.created_at
  from join_requests r
  join profiles p on p.id = r.patient_id
  left join clinics c on c.id = r.clinic_id
  where r.doctor_id = auth.uid() and r.status = 'pending'
  order by r.created_at;
$$;

-- Doctor: active patients.
create or replace function public.doctor_my_patients()
returns table (link_id uuid, patient_id uuid, patient_name text, gender public.gender, age int,
               scope public.share_scope, started_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, p.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         c.scope, l.started_at
  from care_links l
  join profiles p on p.id = l.patient_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.doctor_id = auth.uid() and l.status = 'active'
  order by p.full_name;
$$;

-- Patient: doctors I am linked to.
create or replace function public.patient_my_doctors()
returns table (link_id uuid, doctor_id uuid, doctor_name text, title text, specialty_ar text,
               specialty_en text, scope public.share_scope, started_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.id, d.id, p.full_name, d.title, s.name_ar, s.name_en, c.scope, l.started_at
  from care_links l
  join doctors d on d.id = l.doctor_id
  join profiles p on p.id = d.id
  left join specialties s on s.id = d.specialty_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.patient_id = auth.uid() and l.status = 'active'
  order by l.started_at desc;
$$;

-- Patient: my requests and their status.
create or replace function public.patient_my_requests()
returns table (request_id uuid, doctor_id uuid, doctor_name text, specialty_ar text, specialty_en text,
               status public.request_status, reject_reason text, created_at timestamptz, responded_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, d.id, p.full_name, s.name_ar, s.name_en, r.status, r.reject_reason, r.created_at, r.responded_at
  from join_requests r
  join doctors d on d.id = r.doctor_id
  join profiles p on p.id = d.id
  left join specialties s on s.id = d.specialty_id
  where r.patient_id = auth.uid()
  order by r.created_at desc
  limit 100;
$$;

-- Admin: doctors by status, with their latest verification documents.
create or replace function public.admin_list_doctors(p_status public.doctor_status default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc) from (
      select d.id, p.full_name, p.email, p.is_suspended, d.status, d.title, d.license_number,
             d.years_experience, d.qualifications, s.name_ar as specialty_ar, d.created_at,
             (select v.documents from doctor_verifications v where v.doctor_id = d.id
              order by v.submitted_at desc limit 1) as documents,
             (select v.note from doctor_verifications v where v.doctor_id = d.id
              order by v.submitted_at desc limit 1) as note,
             (select count(*) from clinics c where c.doctor_id = d.id) as clinics_count
      from doctors d
      join profiles p on p.id = d.id
      left join specialties s on s.id = d.specialty_id
      where p_status is null or d.status = p_status
      limit 200) x), '[]'::jsonb);
end $$;

-- Admin: simple dashboard counters.
create or replace function public.admin_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return jsonb_build_object(
    'patients',         (select count(*) from patients),
    'doctors_verified', (select count(*) from doctors where status = 'verified'),
    'doctors_pending',  (select count(*) from doctors where status = 'pending'),
    'active_links',     (select count(*) from care_links where status = 'active'),
    'pending_requests', (select count(*) from join_requests where status = 'pending'));
end $$;

revoke all on function public.get_my_context(), public.doctor_incoming_requests(),
  public.doctor_my_patients(), public.patient_my_doctors(), public.patient_my_requests(),
  public.admin_list_doctors(public.doctor_status), public.admin_stats() from public, anon;
grant execute on function public.get_my_context(), public.doctor_incoming_requests(),
  public.doctor_my_patients(), public.patient_my_doctors(), public.patient_my_requests(),
  public.admin_list_doctors(public.doctor_status), public.admin_stats() to authenticated;

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

drop policy if exists "verification: doctor uploads to own folder" on storage.objects;
create policy "verification: doctor uploads to own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (select 1 from public.doctors where id = auth.uid())
  );

drop policy if exists "verification: doctor or admin reads" on storage.objects;
create policy "verification: doctor or admin reads"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verification-docs'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );
-- No update/delete policies: submitted documents stay as submitted.

-- =====================================================================
-- دكتوري — 0004: حسابات بالموبايل تنشئها العيادة أو الإدارة + صلاحيات المدير الكاملة
-- * Doctor creates a patient account (phone + password, no confirmation, no SMS),
--   already linked to their clinic.
-- * Admin creates / edits / resets / suspends / deletes any account.
-- Phone accounts log in with a hidden internal email: p<2010xxxxxxxx>@phone.doctori.app
-- (no mail is ever sent to it; the account is created already confirmed).
-- =====================================================================
create extension if not exists pgcrypto with schema extensions;

-- ---------- Columns ----------
alter table public.profiles add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.profiles add column if not exists login_kind text not null default 'email'
  check (login_kind in ('email', 'phone'));
alter table public.consents add column if not exists source text not null default 'patient'
  check (source in ('patient', 'clinic', 'admin'));

-- Deleting an admin or doctor must not be blocked by records that merely point at them.
alter table public.doctors drop constraint if exists doctors_verified_by_fkey,
  add constraint doctors_verified_by_fkey foreign key (verified_by) references public.profiles(id) on delete set null;
alter table public.doctor_verifications drop constraint if exists doctor_verifications_reviewed_by_fkey,
  add constraint doctor_verifications_reviewed_by_fkey foreign key (reviewed_by) references public.profiles(id) on delete set null;
alter table public.care_links drop constraint if exists care_links_ended_by_fkey,
  add constraint care_links_ended_by_fkey foreign key (ended_by) references public.profiles(id) on delete set null;

-- Admin can manage any clinic.
drop policy if exists clinics_admin on public.clinics;
create policy clinics_admin on public.clinics for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists hours_admin on public.clinic_hours;
create policy hours_admin on public.clinic_hours for all using (public.is_admin()) with check (public.is_admin());

-- ---------- Phone helpers ----------
-- Egyptian mobile → 20 1X XXXXXXXX (12 digits). Accepts 01..., 201..., +201..., 00201...
create or replace function public.normalize_eg_phone(p text) returns text
language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d like '0020%' then d := substr(d, 3); end if;
  if d ~ '^01[0125][0-9]{8}$' then return '2' || d; end if;
  if d ~ '^201[0125][0-9]{8}$' then return d; end if;
  raise exception 'invalid phone number' using errcode = 'P0001';
end $$;

create or replace function public.phone_login_email(p text) returns text
language sql immutable as $$ select 'p' || public.normalize_eg_phone(p) || '@phone.doctori.app' $$;

-- ---------- Internal: create a confirmed Supabase Auth user ----------
-- Not callable from the app; used only by the checked functions below.
create or replace function public._create_auth_user(p_email text, p_password text, p_meta jsonb)
returns uuid language plpgsql security definer set search_path = public, extensions, auth as $$
declare v_id uuid := gen_random_uuid(); v_email text := lower(trim(p_email));
begin
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'password should be at least 8 characters' using errcode = 'P0001';
  end if;
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'account already exists' using errcode = 'P0001';
  end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', v_email,
          extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}'::jsonb, coalesce(p_meta, '{}'::jsonb), now(), now(),
          '', '', '', '');
  insert into auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_id::text, v_id,
          jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());
  return v_id;  -- the on_auth_user_created trigger has created the profile + patient/doctor row
end $$;
revoke all on function public._create_auth_user(text, text, jsonb) from public, anon, authenticated;

create or replace function public._set_auth_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'password should be at least 8 characters' using errcode = 'P0001';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
                        updated_at = now()
   where id = p_user;
end $$;
revoke all on function public._set_auth_password(uuid, text) from public, anon, authenticated;

-- =====================================================================
-- Doctor: add a patient to my clinic (account + active link in one step)
-- =====================================================================
create or replace function public.doctor_create_patient(
  p_full_name text, p_phone text, p_password text,
  p_gender public.gender default null, p_birth_date date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid := auth.uid(); v_phone text; v_email text; v_id uuid; v_link uuid;
begin
  if not exists (select 1 from doctors d join profiles p on p.id = d.id
                 where d.id = v_doc and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  if (select count(*) from profiles where created_by = v_doc and created_at > now() - interval '1 day') >= 50 then
    raise exception 'daily account limit reached' using errcode = 'P0001';
  end if;
  v_phone := normalize_eg_phone(p_phone);
  v_email := phone_login_email(v_phone);
  v_id := _create_auth_user(v_email, p_password,
            jsonb_build_object('full_name', trim(p_full_name), 'role', 'patient', 'locale', 'ar'));
  update profiles set phone = v_phone, gender = p_gender, birth_date = p_birth_date,
                      created_by = v_doc, login_kind = 'phone'
   where id = v_id;
  insert into care_links (patient_id, doctor_id) values (v_id, v_doc) returning id into v_link;
  insert into consents (care_link_id, patient_id, doctor_id, scope, source)
  values (v_link, v_id, v_doc, 'full', 'clinic');
  perform write_audit('patient.created_by_clinic', 'profiles', v_id::text,
                      jsonb_build_object('patient_id', v_id, 'doctor_id', v_doc, 'care_link_id', v_link));
  return jsonb_build_object('patient_id', v_id, 'phone', v_phone, 'link_id', v_link);
end $$;

-- Doctor resets the password of a patient their clinic created (patient forgot it).
create or replace function public.doctor_reset_patient_password(p_patient uuid, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles where id = p_patient and created_by = auth.uid())
     or not has_active_link(p_patient, auth.uid()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform _set_auth_password(p_patient, p_password);
  perform write_audit('patient.password_reset_by_clinic', 'profiles', p_patient::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', auth.uid()));
end $$;

-- Doctor's patient list now shows phone and whether the clinic created the account.
drop function if exists public.doctor_my_patients();
create function public.doctor_my_patients()
returns table (link_id uuid, patient_id uuid, patient_name text, gender public.gender, age int,
               scope public.share_scope, started_at timestamptz, phone text, created_by_clinic boolean)
language sql stable security definer set search_path = public as $$
  select l.id, p.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         c.scope, l.started_at, p.phone, (p.created_by = auth.uid())
  from care_links l
  join profiles p on p.id = l.patient_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.doctor_id = auth.uid() and l.status = 'active'
  order by p.full_name;
$$;

-- =====================================================================
-- Admin: full account management
-- =====================================================================
create or replace function public.admin_create_user(
  p_full_name text, p_login text, p_password text, p_role public.user_role default 'patient',
  p_specialty int default null, p_license text default null, p_verified boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_kind text; v_email text; v_phone text; v_id uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  if position('@' in coalesce(p_login, '')) > 0 then
    v_kind := 'email'; v_email := lower(trim(p_login));
  else
    v_kind := 'phone'; v_phone := normalize_eg_phone(p_login); v_email := phone_login_email(v_phone);
  end if;
  v_id := _create_auth_user(v_email, p_password, jsonb_build_object(
            'full_name', trim(p_full_name),
            'role', case when p_role = 'doctor' then 'doctor' else 'patient' end,
            'locale', 'ar'));
  update profiles set created_by = auth.uid(), login_kind = v_kind,
                      phone = coalesce(v_phone, phone),
                      role = p_role
   where id = v_id;
  if p_role = 'doctor' then
    update doctors set specialty_id = p_specialty, license_number = nullif(trim(p_license), ''),
           status = case when p_verified then 'verified'::doctor_status else 'pending'::doctor_status end,
           verified_at = case when p_verified then now() end,
           verified_by = case when p_verified then auth.uid() end
     where id = v_id;
  end if;
  perform write_audit('user.created_by_admin', 'profiles', v_id::text,
                      jsonb_build_object('role', p_role, 'login_kind', v_kind));
  return jsonb_build_object('user_id', v_id, 'login', coalesce(v_phone, v_email), 'login_kind', v_kind);
end $$;

create or replace function public.admin_set_password(p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  perform _set_auth_password(p_user, p_password);
  perform write_audit('user.password_reset_by_admin', 'profiles', p_user::text, '{}'::jsonb);
end $$;

create or replace function public.admin_delete_user(p_user uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
declare v_name text; v_role user_role;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_user = auth.uid() then raise exception 'cannot delete yourself' using errcode = 'P0001'; end if;
  select full_name, role into v_name, v_role from public.profiles where id = p_user;
  if not found then raise exception 'user not found' using errcode = 'P0001'; end if;
  perform write_audit('user.deleted_by_admin', 'profiles', p_user::text,
                      jsonb_build_object('full_name', v_name, 'role', v_role));
  delete from auth.users where id = p_user;   -- cascades to profile, links, clinics…
end $$;

create or replace function public.admin_list_users(p_role public.user_role default null, p_query text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc) from (
      select p.id, p.full_name, p.role, p.phone, p.gender, p.birth_date, p.is_suspended, p.login_kind,
             case when p.login_kind = 'phone' then null else p.email end as email,
             p.created_at, d.status as doctor_status, d.specialty_id, d.license_number,
             (select full_name from profiles c where c.id = p.created_by) as created_by_name
      from profiles p left join doctors d on d.id = p.id
      where (p_role is null or p.role = p_role)
        and (p_query is null or p.full_name ilike '%' || p_query || '%'
             or p.phone like '%' || regexp_replace(p_query, '\D', '', 'g') || '%'
             or p.email ilike '%' || p_query || '%')
      order by p.created_at desc
      limit 300) x), '[]'::jsonb);
end $$;

-- Doctors without a clinic yet (e.g. added by the admin) still appear in search,
-- unless the patient filters by area or working day.
create or replace function public.search_doctors(
  p_query text default null, p_specialty int default null,
  p_governorate int default null, p_city int default null,
  p_lat double precision default null, p_lng double precision default null,
  p_accepting_only boolean default false, p_min_rating numeric default null,
  p_open_weekday smallint default null,
  p_limit int default 20, p_offset int default 0)
returns table (
  doctor_id uuid, full_name text, title text, specialty_ar text, specialty_en text,
  photo_path text, rating_avg numeric, rating_count int, accepting_new boolean,
  clinic_id uuid, clinic_name text, clinic_address text, city_ar text, governorate_ar text,
  lat double precision, lng double precision, distance_km double precision)
language sql stable security definer set search_path = public as $$
  with c as (
    select cl.*,
           case when p_lat is null or p_lng is null or cl.lat is null then null
                else 6371 * 2 * asin(sqrt(
                       power(sin(radians(cl.lat - p_lat) / 2), 2) +
                       cos(radians(p_lat)) * cos(radians(cl.lat)) *
                       power(sin(radians(cl.lng - p_lng) / 2), 2))) end as dist
    from clinics cl
    where cl.is_active
      and (p_governorate is null or cl.governorate_id = p_governorate)
      and (p_city is null or cl.city_id = p_city)
      and (p_open_weekday is null or exists (select 1 from clinic_hours h
                                             where h.clinic_id = cl.id and h.weekday = p_open_weekday))
  ), best as (
    select distinct on (c.doctor_id) c.*
    from c order by c.doctor_id, c.dist nulls last
  )
  select d.id, p.full_name, d.title, s.name_ar, s.name_en, d.photo_path,
         d.rating_avg, d.rating_count, d.accepting_new,
         b.id, b.name, b.address, ci.name_ar, g.name_ar, b.lat, b.lng, round(b.dist::numeric, 2)::double precision
  from doctors d
  join profiles p on p.id = d.id and not p.is_suspended
  left join best b on b.doctor_id = d.id
  left join specialties s on s.id = d.specialty_id
  left join cities ci on ci.id = b.city_id
  left join governorates g on g.id = b.governorate_id
  where auth.uid() is not null
    and d.status = 'verified'
    -- area / working-day filters need a matching clinic; otherwise doctors without clinics still show
    and (b.id is not null or (p_governorate is null and p_city is null and p_open_weekday is null))
    and (p_specialty is null or d.specialty_id = p_specialty or d.sub_specialty_id = p_specialty)
    and (not p_accepting_only or d.accepting_new)
    and (p_min_rating is null or d.rating_avg >= p_min_rating)
    and (p_query is null or p.full_name ilike '%' || p_query || '%'
         or s.name_ar ilike '%' || p_query || '%' or s.name_en ilike '%' || p_query || '%')
  order by b.dist nulls last, d.rating_avg desc, p.full_name
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;

-- =====================================================================
-- Grants
-- =====================================================================
revoke all on function public.normalize_eg_phone(text), public.phone_login_email(text),
  public.doctor_create_patient(text, text, text, public.gender, date),
  public.doctor_reset_patient_password(uuid, text), public.doctor_my_patients(),
  public.admin_create_user(text, text, text, public.user_role, int, text, boolean),
  public.admin_set_password(uuid, text), public.admin_delete_user(uuid),
  public.admin_list_users(public.user_role, text)
from public, anon;
grant execute on function public.normalize_eg_phone(text), public.phone_login_email(text),
  public.doctor_create_patient(text, text, text, public.gender, date),
  public.doctor_reset_patient_password(uuid, text), public.doctor_my_patients(),
  public.admin_create_user(text, text, text, public.user_role, int, text, boolean),
  public.admin_set_password(uuid, text), public.admin_delete_user(uuid),
  public.admin_list_users(public.user_role, text)
to authenticated;

-- =====================================================================
-- دكتوري — 0005: صور البروفايل للمريض والطبيب
-- Public "avatars" bucket (profile photos only — never medical files).
-- Path: <user_id>/avatar_<timestamp>.png ; profiles.avatar_url stores the public URL.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/png', 'image/jpeg'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars: upload own" on storage.objects;
create policy "avatars: upload own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars: update own" on storage.objects;
create policy "avatars: update own"
  on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars: delete own" on storage.objects;
create policy "avatars: delete own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- =====================================================================
-- دكتوري — 0006: إظهار صور البروفايل والتخصص في الشاشات
-- Adds avatar_url (and the doctor's specialty for the themed background)
-- to the read functions. Return shapes change, so each is dropped first.
-- Runs locally too (no storage objects here).
-- =====================================================================
alter table public.profiles add column if not exists avatar_url text
  check (avatar_url is null or length(avatar_url) <= 500);

create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'phone', p.phone, 'login_kind', p.login_kind,
    'locale', p.locale, 'is_suspended', p.is_suspended, 'avatar_url', p.avatar_url,
    'doctor_status', d.status, 'specialty_id', d.specialty_id,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

drop function if exists public.doctor_incoming_requests();
create function public.doctor_incoming_requests()
returns table (request_id uuid, patient_name text, gender public.gender, age int,
               message text, share_scope public.share_scope, clinic_name text, created_at timestamptz,
               avatar_url text)
language sql stable security definer set search_path = public as $$
  select r.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         r.message, r.share_scope, c.name, r.created_at, p.avatar_url
  from join_requests r
  join profiles p on p.id = r.patient_id
  left join clinics c on c.id = r.clinic_id
  where r.doctor_id = auth.uid() and r.status = 'pending'
  order by r.created_at;
$$;

drop function if exists public.doctor_my_patients();
create function public.doctor_my_patients()
returns table (link_id uuid, patient_id uuid, patient_name text, gender public.gender, age int,
               scope public.share_scope, started_at timestamptz, phone text, created_by_clinic boolean,
               avatar_url text)
language sql stable security definer set search_path = public as $$
  select l.id, p.id, p.full_name, p.gender,
         case when p.birth_date is null then null
              else extract(year from age(p.birth_date))::int end,
         c.scope, l.started_at, p.phone, (p.created_by = auth.uid()), p.avatar_url
  from care_links l
  join profiles p on p.id = l.patient_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.doctor_id = auth.uid() and l.status = 'active'
  order by p.full_name;
$$;

drop function if exists public.patient_my_doctors();
create function public.patient_my_doctors()
returns table (link_id uuid, doctor_id uuid, doctor_name text, title text, specialty_ar text,
               specialty_en text, scope public.share_scope, started_at timestamptz, avatar_url text)
language sql stable security definer set search_path = public as $$
  select l.id, d.id, p.full_name, d.title, s.name_ar, s.name_en, c.scope, l.started_at, p.avatar_url
  from care_links l
  join doctors d on d.id = l.doctor_id
  join profiles p on p.id = d.id
  left join specialties s on s.id = d.specialty_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.patient_id = auth.uid() and l.status = 'active'
  order by l.started_at desc;
$$;

drop function if exists public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int);
create function public.search_doctors(
  p_query text default null, p_specialty int default null,
  p_governorate int default null, p_city int default null,
  p_lat double precision default null, p_lng double precision default null,
  p_accepting_only boolean default false, p_min_rating numeric default null,
  p_open_weekday smallint default null,
  p_limit int default 20, p_offset int default 0)
returns table (
  doctor_id uuid, full_name text, title text, specialty_ar text, specialty_en text,
  photo_path text, rating_avg numeric, rating_count int, accepting_new boolean,
  clinic_id uuid, clinic_name text, clinic_address text, city_ar text, governorate_ar text,
  lat double precision, lng double precision, distance_km double precision, avatar_url text)
language sql stable security definer set search_path = public as $$
  with c as (
    select cl.*,
           case when p_lat is null or p_lng is null or cl.lat is null then null
                else 6371 * 2 * asin(sqrt(
                       power(sin(radians(cl.lat - p_lat) / 2), 2) +
                       cos(radians(p_lat)) * cos(radians(cl.lat)) *
                       power(sin(radians(cl.lng - p_lng) / 2), 2))) end as dist
    from clinics cl
    where cl.is_active
      and (p_governorate is null or cl.governorate_id = p_governorate)
      and (p_city is null or cl.city_id = p_city)
      and (p_open_weekday is null or exists (select 1 from clinic_hours h
                                             where h.clinic_id = cl.id and h.weekday = p_open_weekday))
  ), best as (
    select distinct on (c.doctor_id) c.*
    from c order by c.doctor_id, c.dist nulls last
  )
  select d.id, p.full_name, d.title, s.name_ar, s.name_en, d.photo_path,
         d.rating_avg, d.rating_count, d.accepting_new,
         b.id, b.name, b.address, ci.name_ar, g.name_ar, b.lat, b.lng,
         round(b.dist::numeric, 2)::double precision, p.avatar_url
  from doctors d
  join profiles p on p.id = d.id and not p.is_suspended
  left join best b on b.doctor_id = d.id
  left join specialties s on s.id = d.specialty_id
  left join cities ci on ci.id = b.city_id
  left join governorates g on g.id = b.governorate_id
  where auth.uid() is not null
    and d.status = 'verified'
    and (b.id is not null or (p_governorate is null and p_city is null and p_open_weekday is null))
    and (p_specialty is null or d.specialty_id = p_specialty or d.sub_specialty_id = p_specialty)
    and (not p_accepting_only or d.accepting_new)
    and (p_min_rating is null or d.rating_avg >= p_min_rating)
    and (p_query is null or p.full_name ilike '%' || p_query || '%'
         or s.name_ar ilike '%' || p_query || '%' or s.name_en ilike '%' || p_query || '%')
  order by b.dist nulls last, d.rating_avg desc, p.full_name
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;

create or replace function public.get_doctor_public(p_doctor uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', d.id, 'full_name', p.full_name, 'title', d.title, 'bio', d.bio,
    'qualifications', d.qualifications, 'years_experience', d.years_experience,
    'specialty', s.name_ar, 'specialty_en', s.name_en, 'photo_path', d.photo_path,
    'avatar_url', p.avatar_url,
    'public_phone', d.public_phone, 'rating_avg', d.rating_avg, 'rating_count', d.rating_count,
    'accepting_new', d.accepting_new,
    'clinics', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'address', c.address, 'area', c.area,
        'lat', c.lat, 'lng', c.lng, 'phone', c.phone,
        'hours', coalesce((select jsonb_agg(jsonb_build_object('weekday', h.weekday,
                   'opens_at', h.opens_at, 'closes_at', h.closes_at) order by h.weekday, h.opens_at)
                   from clinic_hours h where h.clinic_id = c.id), '[]'::jsonb)))
      from clinics c where c.doctor_id = d.id and c.is_active), '[]'::jsonb))
  from doctors d
  join profiles p on p.id = d.id and not p.is_suspended
  left join specialties s on s.id = d.specialty_id
  where d.id = p_doctor and d.status = 'verified' and auth.uid() is not null;
$$;

create or replace function public.admin_list_users(p_role public.user_role default null, p_query text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(x) order by x.created_at desc) from (
      select p.id, p.full_name, p.role, p.phone, p.gender, p.birth_date, p.is_suspended, p.login_kind,
             case when p.login_kind = 'phone' then null else p.email end as email,
             p.created_at, p.avatar_url, d.status as doctor_status, d.specialty_id, d.license_number,
             (select full_name from profiles c where c.id = p.created_by) as created_by_name
      from profiles p left join doctors d on d.id = p.id
      where (p_role is null or p.role = p_role)
        and (p_query is null or p.full_name ilike '%' || p_query || '%'
             or p.phone like '%' || regexp_replace(p_query, '\D', '', 'g') || '%'
             or p.email ilike '%' || p_query || '%')
      order by p.created_at desc
      limit 300) x), '[]'::jsonb);
end $$;

revoke all on function public.get_my_context(), public.doctor_incoming_requests(), public.doctor_my_patients(),
  public.patient_my_doctors(),
  public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int),
  public.get_doctor_public(uuid), public.admin_list_users(public.user_role, text)
from public, anon;
grant execute on function public.get_my_context(), public.doctor_incoming_requests(), public.doctor_my_patients(),
  public.patient_my_doctors(),
  public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int),
  public.get_doctor_public(uuid), public.admin_list_users(public.user_role, text)
to authenticated;

-- =====================================================================
-- دكتوري — 0007: إصلاح رفع صور البروفايل
-- Storage needs a SELECT policy for uploads that may overwrite/check existing files.
-- Avatars are public profile photos, so any signed-in user may read them.
-- =====================================================================
drop policy if exists "avatars: read" on storage.objects;
create policy "avatars: read"
  on storage.objects for select to authenticated
  using (bucket_id = 'avatars');

-- =====================================================================
-- دكتوري — 0008: تفعيل الطبيب بكود من الإدارة عبر واتساب
-- 1. The doctor registers with a mobile number and asks for a code on WhatsApp.
-- 2. The admin issues a 6-digit code (stored hashed, valid 7 days) and sends it.
-- 3. The doctor enters the code → account verified and visible to patients.
-- =====================================================================

create table if not exists public.doctor_activation_codes (
  doctor_id  uuid primary key references public.doctors(id) on delete cascade,
  code_hash  text not null,
  issued_by  uuid references public.profiles(id) on delete set null,
  issued_at  timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts   int not null default 0,
  used_at    timestamptz
);
alter table public.doctor_activation_codes enable row level security;  -- no policies: functions only
revoke all on public.doctor_activation_codes from anon, authenticated;

-- Admin's WhatsApp number that doctors message for their code (editable by the admin).
insert into public.app_settings (key, value) values ('admin_whatsapp', '"201207760898"')
on conflict (key) do nothing;

-- Sign-up keeps the mobile number the user typed (metadata "phone"), normalized when it is Egyptian.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role user_role := case when new.raw_user_meta_data->>'role' = 'doctor'
                           then 'doctor'::user_role else 'patient'::user_role end;
  v_phone text := coalesce(new.phone, nullif(trim(new.raw_user_meta_data->>'phone'), ''));
begin
  if v_phone is not null then
    begin
      v_phone := normalize_eg_phone(v_phone);
    exception when others then
      v_phone := regexp_replace(v_phone, '\D', '', 'g');
    end;
  end if;
  insert into profiles (id, role, full_name, phone, email, locale)
  values (new.id, v_role,
          coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'مستخدم'),
          v_phone, new.email,
          case when new.raw_user_meta_data->>'locale' = 'en' then 'en' else 'ar' end);
  if v_role = 'doctor' then
    insert into doctors (id) values (new.id);
  else
    insert into patients (id) values (new.id);
  end if;
  return new;
end $$;

-- Let trusted functions verify a doctor without being admin (flag set only inside them).
create or replace function public.guard_doctor_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and auth.uid() is not null
     and coalesce(current_setting('doctori.trusted_verify', true), '') <> '1' then
    if new.status is distinct from old.status
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by
       or new.rating_avg is distinct from old.rating_avg
       or new.rating_count is distinct from old.rating_count then
      raise exception 'verification and rating fields are managed by the platform' using errcode = '42501';
    end if;
    if old.status = 'verified' and new.license_number is distinct from old.license_number then
      new.status := 'pending';
      new.verified_at := null;
      new.verified_by := null;
    end if;
  end if;
  return new;
end $$;

-- Admin: create (or replace) a code for a doctor. Returns the plain code once, to send on WhatsApp.
create or replace function public.admin_issue_doctor_code(p_doctor uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_code text; v_phone text;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if not exists (select 1 from doctors where id = p_doctor) then
    raise exception 'doctor not found' using errcode = 'P0001';
  end if;
  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into doctor_activation_codes (doctor_id, code_hash, issued_by, issued_at, expires_at, attempts, used_at)
  values (p_doctor, extensions.crypt(v_code, extensions.gen_salt('bf')), auth.uid(), now(), now() + interval '7 days', 0, null)
  on conflict (doctor_id) do update
    set code_hash = excluded.code_hash, issued_by = excluded.issued_by, issued_at = now(),
        expires_at = excluded.expires_at, attempts = 0, used_at = null;
  select phone into v_phone from profiles where id = p_doctor;
  perform write_audit('doctor.activation_code_issued', 'doctors', p_doctor::text, '{}'::jsonb);
  return jsonb_build_object('code', v_code, 'phone', v_phone);
end $$;

-- Doctor: enter the code → verified. Returns {ok, attempts_left} instead of raising on a wrong
-- code, so the failed attempt is saved (a raised error would roll the counter back).
create or replace function public.doctor_activate_with_code(p_code text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r doctor_activation_codes;
begin
  select * into r from doctor_activation_codes where doctor_id = auth.uid() for update;
  if not found then raise exception 'no activation code yet' using errcode = 'P0001'; end if;
  if r.used_at is not null then raise exception 'code already used' using errcode = 'P0001'; end if;
  if r.expires_at < now() then raise exception 'activation code expired' using errcode = 'P0001'; end if;
  if r.attempts >= 5 then raise exception 'too many wrong attempts' using errcode = 'P0001'; end if;

  if extensions.crypt(regexp_replace(coalesce(p_code, ''), '\D', '', 'g'), r.code_hash) <> r.code_hash then
    update doctor_activation_codes set attempts = attempts + 1 where doctor_id = r.doctor_id;
    return jsonb_build_object('ok', false, 'attempts_left', greatest(0, 4 - r.attempts));
  end if;

  perform set_config('doctori.trusted_verify', '1', true);
  update doctors set status = 'verified', verified_at = now(), verified_by = r.issued_by where id = r.doctor_id;
  perform set_config('doctori.trusted_verify', '', true);
  update doctor_activation_codes set used_at = now() where doctor_id = r.doctor_id;
  perform write_audit('doctor.activated_with_code', 'doctors', r.doctor_id::text, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.admin_issue_doctor_code(uuid), public.doctor_activate_with_code(text) from public, anon;
grant execute on function public.admin_issue_doctor_code(uuid), public.doctor_activate_with_code(text) to authenticated;

-- =====================================================================
-- دكتوري — 0009: الملف الطبي، علاجي، الحجوزات، مساعدي الطبيب
-- * medical_entries: notes / photos / videos / files the patient adds to their medical file
-- * medications (+ doses): «علاجي» — added by the patient or prescribed by a linked doctor
-- * appointments: patient books a free slot from the clinic hours; staff confirm / cancel
-- * doctor_assistants: a doctor adds assistant accounts (mobile + password) with chosen permissions
-- Storage policies for the medical files bucket live in 0010 (Supabase-only).
-- =====================================================================

alter type public.user_role add value if not exists 'assistant';

-- ---------------------------------------------------------------------
-- Assistants
-- ---------------------------------------------------------------------
create table if not exists public.doctor_assistants (
  doctor_id        uuid not null references public.doctors(id) on delete cascade,
  assistant_id     uuid not null unique references public.profiles(id) on delete cascade,
  can_bookings     boolean not null default true,
  can_patients     boolean not null default false,
  can_add_patients boolean not null default false,
  can_medical      boolean not null default false,
  created_at       timestamptz not null default now(),
  primary key (doctor_id, assistant_id)
);
alter table public.doctor_assistants enable row level security;
drop policy if exists assistants_read on public.doctor_assistants;
create policy assistants_read on public.doctor_assistants for select using (
  doctor_id = auth.uid() or assistant_id = auth.uid() or public.is_admin());
revoke all on public.doctor_assistants from anon;
grant select on public.doctor_assistants to authenticated;

-- Does the caller act for this doctor with this permission? ('any' = any assistant permission)
create or replace function public.acts_for(p_doctor uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select (auth.uid() = p_doctor and exists (select 1 from profiles p where p.id = p_doctor and not p.is_suspended))
      or exists (
        select 1 from doctor_assistants a join profiles p on p.id = a.assistant_id
        where a.doctor_id = p_doctor and a.assistant_id = auth.uid() and not p.is_suspended
          and case p_perm
                when 'bookings' then a.can_bookings
                when 'patients' then a.can_patients
                when 'add_patients' then a.can_add_patients
                when 'medical' then a.can_medical
                when 'any' then true
                else false end);
$$;

-- Trusted internal updates (role changes made by checked functions).
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and auth.uid() is not null
     and coalesce(current_setting('doctori.trusted', true), '') <> '1' then
    if new.role is distinct from old.role or new.is_suspended is distinct from old.is_suspended
       or new.id is distinct from old.id then
      raise exception 'not allowed to change role or suspension' using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

create or replace function public.doctor_create_assistant(
  p_full_name text, p_phone text, p_password text,
  p_bookings boolean default true, p_patients boolean default false,
  p_add_patients boolean default false, p_medical boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid := auth.uid(); v_phone text; v_id uuid;
begin
  if not exists (select 1 from doctors d join profiles p on p.id = d.id
                 where d.id = v_doc and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then raise exception 'name is required' using errcode = 'P0001'; end if;
  if (select count(*) from doctor_assistants where doctor_id = v_doc) >= 10 then
    raise exception 'assistant limit reached' using errcode = 'P0001';
  end if;
  v_phone := normalize_eg_phone(p_phone);
  v_id := _create_auth_user(phone_login_email(v_phone), p_password,
            jsonb_build_object('full_name', trim(p_full_name), 'role', 'patient', 'locale', 'ar'));
  perform set_config('doctori.trusted', '1', true);
  update profiles set role = 'assistant', phone = v_phone, created_by = v_doc, login_kind = 'phone' where id = v_id;
  perform set_config('doctori.trusted', '', true);
  delete from patients where id = v_id;
  insert into doctor_assistants (doctor_id, assistant_id, can_bookings, can_patients, can_add_patients, can_medical)
  values (v_doc, v_id, p_bookings, p_patients, p_add_patients, p_medical);
  perform write_audit('assistant.created', 'profiles', v_id::text, jsonb_build_object('doctor_id', v_doc));
  return jsonb_build_object('assistant_id', v_id, 'phone', v_phone);
end $$;

create or replace function public.doctor_update_assistant(
  p_assistant uuid, p_bookings boolean, p_patients boolean, p_add_patients boolean, p_medical boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update doctor_assistants set can_bookings = p_bookings, can_patients = p_patients,
         can_add_patients = p_add_patients, can_medical = p_medical
   where doctor_id = auth.uid() and assistant_id = p_assistant;
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('assistant.permissions_changed', 'profiles', p_assistant::text,
    jsonb_build_object('bookings', p_bookings, 'patients', p_patients, 'add_patients', p_add_patients, 'medical', p_medical));
end $$;

create or replace function public.doctor_reset_assistant_password(p_assistant uuid, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from doctor_assistants where doctor_id = auth.uid() and assistant_id = p_assistant) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform _set_auth_password(p_assistant, p_password);
  perform write_audit('assistant.password_reset', 'profiles', p_assistant::text, '{}'::jsonb);
end $$;

create or replace function public.doctor_remove_assistant(p_assistant uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not exists (select 1 from doctor_assistants where doctor_id = auth.uid() and assistant_id = p_assistant) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform write_audit('assistant.removed', 'profiles', p_assistant::text, jsonb_build_object('doctor_id', auth.uid()));
  delete from auth.users where id = p_assistant;
end $$;

create or replace function public.doctor_list_assistants()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'assistant_id', a.assistant_id, 'full_name', p.full_name, 'phone', p.phone, 'avatar_url', p.avatar_url,
           'is_suspended', p.is_suspended, 'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
           'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'created_at', a.created_at)
         order by a.created_at), '[]'::jsonb)
  from doctor_assistants a join profiles p on p.id = a.assistant_id
  where a.doctor_id = auth.uid();
$$;

-- Context now tells an assistant which doctor they work for and what they may do.
create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'phone', p.phone, 'login_kind', p.login_kind,
    'locale', p.locale, 'is_suspended', p.is_suspended, 'avatar_url', p.avatar_url,
    'doctor_status', d.status, 'specialty_id', d.specialty_id,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null),
    'assistant_of', (select jsonb_build_object(
        'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url,
        'doctor_status', dd.status, 'specialty_ar', ds.name_ar, 'specialty_en', ds.name_en,
        'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
        'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical)
      from doctor_assistants a
      join profiles dp on dp.id = a.doctor_id
      join doctors dd on dd.id = a.doctor_id
      left join specialties ds on ds.id = dd.specialty_id
      where a.assistant_id = p.id))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- Doctor functions now also work for permitted assistants (p_doctor = whom they act for)
-- ---------------------------------------------------------------------
drop function if exists public.doctor_incoming_requests();
drop function if exists public.doctor_incoming_requests(uuid);
create function public.doctor_incoming_requests(p_doctor uuid default null)
returns table (request_id uuid, patient_name text, gender public.gender, age int,
               message text, share_scope public.share_scope, clinic_name text, created_at timestamptz,
               avatar_url text)
language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'patients') then return; end if;
  return query
  select r.id, p.full_name, p.gender,
         case when p.birth_date is null then null else extract(year from age(p.birth_date))::int end,
         r.message, r.share_scope, c.name, r.created_at, p.avatar_url
  from join_requests r
  join profiles p on p.id = r.patient_id
  left join clinics c on c.id = r.clinic_id
  where r.doctor_id = v_doc and r.status = 'pending'
  order by r.created_at;
end $$;

drop function if exists public.doctor_my_patients();
drop function if exists public.doctor_my_patients(uuid);
create function public.doctor_my_patients(p_doctor uuid default null)
returns table (link_id uuid, patient_id uuid, patient_name text, gender public.gender, age int,
               scope public.share_scope, started_at timestamptz, phone text, created_by_clinic boolean,
               avatar_url text)
language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not (acts_for(v_doc, 'patients') or acts_for(v_doc, 'medical') or acts_for(v_doc, 'add_patients')) then return; end if;
  return query
  select l.id, p.id, p.full_name, p.gender,
         case when p.birth_date is null then null else extract(year from age(p.birth_date))::int end,
         c.scope, l.started_at, p.phone, (p.created_by = v_doc), p.avatar_url
  from care_links l
  join profiles p on p.id = l.patient_id
  left join consents c on c.care_link_id = l.id and c.revoked_at is null
  where l.doctor_id = v_doc and l.status = 'active'
  order by p.full_name;
end $$;

create or replace function public.respond_join(p_request uuid, p_accept boolean, p_reason text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare r join_requests; v_link uuid;
begin
  select * into r from join_requests where id = p_request for update;
  if not found or not acts_for(r.doctor_id, 'patients') then
    raise exception 'request not found' using errcode = '42501';
  end if;
  if not exists (select 1 from doctors d join profiles p on p.id = d.id
                 where d.id = r.doctor_id and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if r.status <> 'pending' then raise exception 'request already handled' using errcode = 'P0001'; end if;
  if p_accept then
    update join_requests set status = 'accepted', responded_at = now() where id = r.id;
    insert into care_links (patient_id, doctor_id, request_id) values (r.patient_id, r.doctor_id, r.id) returning id into v_link;
    insert into consents (care_link_id, patient_id, doctor_id, scope) values (v_link, r.patient_id, r.doctor_id, r.share_scope);
  else
    update join_requests set status = 'rejected', responded_at = now(), reject_reason = nullif(trim(p_reason), '') where id = r.id;
  end if;
  perform write_audit(case when p_accept then 'join_request.accepted' else 'join_request.rejected' end,
                      'join_requests', r.id::text,
                      jsonb_build_object('patient_id', r.patient_id, 'doctor_id', r.doctor_id, 'care_link_id', v_link));
  return v_link;
end $$;

drop function if exists public.doctor_create_patient(text, text, text, public.gender, date);
drop function if exists public.doctor_create_patient(text, text, text, public.gender, date, uuid);
create function public.doctor_create_patient(
  p_full_name text, p_phone text, p_password text,
  p_gender public.gender default null, p_birth_date date default null, p_doctor uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_phone text; v_id uuid; v_link uuid;
begin
  if not acts_for(v_doc, 'add_patients') or not exists (
       select 1 from doctors d join profiles p on p.id = d.id
       where d.id = v_doc and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then raise exception 'name is required' using errcode = 'P0001'; end if;
  if (select count(*) from profiles where created_by = v_doc and created_at > now() - interval '1 day') >= 50 then
    raise exception 'daily account limit reached' using errcode = 'P0001';
  end if;
  v_phone := normalize_eg_phone(p_phone);
  v_id := _create_auth_user(phone_login_email(v_phone), p_password,
            jsonb_build_object('full_name', trim(p_full_name), 'role', 'patient', 'locale', 'ar'));
  update profiles set phone = v_phone, gender = p_gender, birth_date = p_birth_date,
                      created_by = v_doc, login_kind = 'phone'
   where id = v_id;
  insert into care_links (patient_id, doctor_id) values (v_id, v_doc) returning id into v_link;
  insert into consents (care_link_id, patient_id, doctor_id, scope, source) values (v_link, v_id, v_doc, 'full', 'clinic');
  perform write_audit('patient.created_by_clinic', 'profiles', v_id::text,
                      jsonb_build_object('patient_id', v_id, 'doctor_id', v_doc, 'care_link_id', v_link));
  return jsonb_build_object('patient_id', v_id, 'phone', v_phone, 'link_id', v_link);
end $$;

drop function if exists public.doctor_reset_patient_password(uuid, text);
drop function if exists public.doctor_reset_patient_password(uuid, text, uuid);
create function public.doctor_reset_patient_password(p_patient uuid, p_password text, p_doctor uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'add_patients')
     or not exists (select 1 from profiles where id = p_patient and created_by = v_doc)
     or not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform _set_auth_password(p_patient, p_password);
  perform write_audit('patient.password_reset_by_clinic', 'profiles', p_patient::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc));
end $$;

-- ---------------------------------------------------------------------
-- Medical file
-- ---------------------------------------------------------------------
-- May the caller see this patient's item? (entry_doctor = the doctor it was sent to / prescribed by)
create or replace function public.can_view_medical(p_patient uuid, p_entry_doctor uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() = p_patient or exists (
    select 1 from consents c
    join care_links l on l.id = c.care_link_id and l.status = 'active'
    join doctors d on d.id = c.doctor_id and d.status = 'verified'
    where c.patient_id = p_patient and c.revoked_at is null
      and (c.scope = 'full' or c.doctor_id = p_entry_doctor)
      and acts_for(c.doctor_id, 'medical'));
$$;

create table if not exists public.medical_entries (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients(id) on delete cascade,
  kind         text not null check (kind in ('note', 'image', 'video', 'file')),
  title        text check (title is null or length(title) <= 200),
  body         text check (body is null or length(body) <= 5000),
  storage_path text check (storage_path is null or length(storage_path) <= 400),
  mime_type    text,
  size_bytes   bigint,
  shared_with  uuid references public.doctors(id) on delete set null,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  check (kind = 'note' and body is not null and length(trim(body)) > 0
         or kind <> 'note' and storage_path is not null)
);
create index if not exists idx_medical_entries_patient on public.medical_entries (patient_id, created_at desc);
alter table public.medical_entries enable row level security;
drop policy if exists med_entries_read on public.medical_entries;
create policy med_entries_read on public.medical_entries for select using (public.can_view_medical(patient_id, shared_with));
drop policy if exists med_entries_insert on public.medical_entries;
create policy med_entries_insert on public.medical_entries for insert with check (
  patient_id = auth.uid() and created_by = auth.uid()
  and (shared_with is null or public.has_active_link(auth.uid(), shared_with)));
drop policy if exists med_entries_delete on public.medical_entries;
create policy med_entries_delete on public.medical_entries for delete using (patient_id = auth.uid());
revoke all on public.medical_entries from anon;
grant select, insert, delete on public.medical_entries to authenticated;

create or replace function public.can_view_medical_object(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select can_view_medical(e.patient_id, e.shared_with)
                   from medical_entries e where e.storage_path = p_name limit 1), false);
$$;

create or replace function public.list_medical_entries(p_patient uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'kind', e.kind, 'title', e.title, 'body', e.body, 'storage_path', e.storage_path,
           'mime_type', e.mime_type, 'size_bytes', e.size_bytes, 'created_at', e.created_at,
           'shared_with', e.shared_with, 'shared_with_name', sp.full_name)
         order by e.created_at desc), '[]'::jsonb)
  from medical_entries e
  left join profiles sp on sp.id = e.shared_with
  where e.patient_id = coalesce(p_patient, auth.uid())
    and can_view_medical(e.patient_id, e.shared_with);
$$;

-- ---------------------------------------------------------------------
-- «علاجي» — medications and dose log
-- ---------------------------------------------------------------------
create table if not exists public.medications (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.patients(id) on delete cascade,
  prescribed_by uuid references public.doctors(id) on delete set null,
  name          text not null check (length(trim(name)) between 1 and 120),
  dose          text check (dose is null or length(dose) <= 120),
  every_hours   int not null default 24 check (every_hours in (4, 6, 8, 12, 24)),
  first_time    time not null default '09:00',
  start_date    date not null default ((now() at time zone 'Africa/Cairo')::date),
  end_date      date,
  instructions  text check (instructions is null or length(instructions) <= 1000),
  is_active     boolean not null default true,
  reminders_on  boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);
create index if not exists idx_medications_patient on public.medications (patient_id);
alter table public.medications enable row level security;
drop policy if exists meds_read on public.medications;
create policy meds_read on public.medications for select using (public.can_view_medical(patient_id, prescribed_by));
-- The patient fully manages medicines they added themselves; prescribed ones change through functions.
drop policy if exists meds_insert_own on public.medications;
create policy meds_insert_own on public.medications for insert with check (patient_id = auth.uid() and prescribed_by is null);
drop policy if exists meds_update_own on public.medications;
create policy meds_update_own on public.medications for update
  using (patient_id = auth.uid() and prescribed_by is null)
  with check (patient_id = auth.uid() and prescribed_by is null);
drop policy if exists meds_delete_own on public.medications;
create policy meds_delete_own on public.medications for delete using (patient_id = auth.uid() and prescribed_by is null);
revoke all on public.medications from anon;
grant select, insert, update, delete on public.medications to authenticated;
drop trigger if exists medications_touch on public.medications;
drop trigger if exists medications_touch on public.medications;
create trigger medications_touch before update on public.medications for each row execute function public.touch_updated_at();

create table if not exists public.medication_doses (
  id            bigserial primary key,
  medication_id uuid not null references public.medications(id) on delete cascade,
  patient_id    uuid not null references public.patients(id) on delete cascade,
  taken_at      timestamptz not null default now()
);
create index if not exists idx_doses_med on public.medication_doses (medication_id, taken_at desc);
alter table public.medication_doses enable row level security;
drop policy if exists doses_read on public.medication_doses;
create policy doses_read on public.medication_doses for select using (public.can_view_medical(patient_id, null)
  or exists (select 1 from public.medications m where m.id = medication_id
             and public.can_view_medical(m.patient_id, m.prescribed_by)));
drop policy if exists doses_insert on public.medication_doses;
create policy doses_insert on public.medication_doses for insert with check (
  patient_id = auth.uid() and exists (select 1 from public.medications m where m.id = medication_id and m.patient_id = auth.uid()));
revoke all on public.medication_doses from anon;
grant select, insert on public.medication_doses to authenticated;
grant usage, select on sequence public.medication_doses_id_seq to authenticated;

create or replace function public.list_medications(p_patient uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'name', m.name, 'dose', m.dose, 'every_hours', m.every_hours,
           'first_time', to_char(m.first_time, 'HH24:MI'), 'start_date', m.start_date, 'end_date', m.end_date,
           'instructions', m.instructions, 'is_active', m.is_active, 'reminders_on', m.reminders_on,
           'prescribed_by', m.prescribed_by, 'prescriber_name', pp.full_name, 'created_at', m.created_at,
           'doses_7d', (select count(*) from medication_doses x where x.medication_id = m.id and x.taken_at > now() - interval '7 days'),
           'last_taken', (select max(taken_at) from medication_doses x where x.medication_id = m.id))
         order by m.is_active desc, m.created_at desc), '[]'::jsonb)
  from medications m
  left join profiles pp on pp.id = m.prescribed_by
  where m.patient_id = coalesce(p_patient, auth.uid())
    and can_view_medical(m.patient_id, m.prescribed_by);
$$;

create or replace function public.prescribe_medication(
  p_patient uuid, p_name text, p_dose text, p_every_hours int, p_first_time time,
  p_start_date date default null, p_end_date date default null, p_instructions text default null,
  p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'medical') or not has_active_link(p_patient, v_doc)
     or not exists (select 1 from doctors where id = v_doc and status = 'verified') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into medications (patient_id, prescribed_by, name, dose, every_hours, first_time, start_date, end_date, instructions)
  values (p_patient, v_doc, trim(p_name), nullif(trim(p_dose), ''), p_every_hours, p_first_time,
          coalesce(p_start_date, (now() at time zone 'Africa/Cairo')::date), p_end_date, nullif(trim(p_instructions), ''))
  returning id into v_id;
  perform write_audit('medication.prescribed', 'medications', v_id::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc, 'name', trim(p_name)));
  return v_id;
end $$;

create or replace function public.stop_prescription(p_med uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m medications;
begin
  select * into m from medications where id = p_med;
  if not found or m.prescribed_by is null or not acts_for(m.prescribed_by, 'medical') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update medications set is_active = false where id = p_med;
  perform write_audit('medication.stopped', 'medications', p_med::text,
                      jsonb_build_object('patient_id', m.patient_id, 'doctor_id', m.prescribed_by));
end $$;

-- The patient may silence reminders for any of their medicines (including prescribed ones).
create or replace function public.set_med_reminders(p_med uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update medications set reminders_on = p_on where id = p_med and patient_id = auth.uid();
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $$;

-- ---------------------------------------------------------------------
-- Bookings
-- ---------------------------------------------------------------------
alter table public.doctors add column if not exists appointment_minutes int not null default 20
  check (appointment_minutes between 5 and 120);

do $t$ begin
  create type public.appointment_status as enum ('pending', 'confirmed', 'cancelled', 'completed', 'no_show');
exception when duplicate_object then null; end $t$;

create table if not exists public.appointments (
  id           uuid primary key default gen_random_uuid(),
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  clinic_id    uuid not null references public.clinics(id) on delete cascade,
  patient_id   uuid not null references public.patients(id) on delete cascade,
  starts_at    timestamptz not null,
  ends_at      timestamptz not null,
  status       public.appointment_status not null default 'pending',
  patient_note text check (patient_note is null or length(patient_note) <= 300),
  created_by   uuid references public.profiles(id) on delete set null,
  updated_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create unique index if not exists appointments_slot_taken on public.appointments (doctor_id, starts_at)
  where status in ('pending', 'confirmed');
create index if not exists idx_appointments_doctor_time on public.appointments (doctor_id, starts_at);
create index if not exists idx_appointments_patient on public.appointments (patient_id, starts_at);
alter table public.appointments enable row level security;
drop policy if exists appts_read on public.appointments;
create policy appts_read on public.appointments for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings') or public.is_admin());
revoke all on public.appointments from anon;
grant select on public.appointments to authenticated;
drop trigger if exists appointments_touch on public.appointments;
drop trigger if exists appointments_touch on public.appointments;
create trigger appointments_touch before update on public.appointments for each row execute function public.touch_updated_at();

-- Slots of one clinic on one day (Cairo time), with availability.
create or replace function public.clinic_slots(p_clinic uuid, p_date date)
returns table (starts_at timestamptz, label text, available boolean)
language sql stable security definer set search_path = public as $$
  with c as (
    select cl.id, cl.doctor_id, d.appointment_minutes as m
    from clinics cl join doctors d on d.id = cl.doctor_id
    join profiles p on p.id = d.id and not p.is_suspended
    where cl.id = p_clinic and cl.is_active and d.status = 'verified' and auth.uid() is not null
  ), s as (
    select distinct gs as t, c.doctor_id
    from c join clinic_hours h on h.clinic_id = c.id and h.weekday = extract(dow from p_date)::int
    cross join lateral generate_series(
      (p_date + h.opens_at) at time zone 'Africa/Cairo',
      (p_date + h.closes_at) at time zone 'Africa/Cairo' - make_interval(mins => c.m),
      make_interval(mins => c.m)) gs
  )
  select s.t, to_char(s.t at time zone 'Africa/Cairo', 'HH24:MI'),
         s.t > now() and not exists (select 1 from appointments a
                                     where a.doctor_id = s.doctor_id and a.starts_at = s.t
                                       and a.status in ('pending', 'confirmed'))
  from s order by s.t;
$$;

-- Patient books for themselves (pending); staff book for a linked patient (confirmed).
create or replace function public.book_appointment(
  p_clinic uuid, p_starts_at timestamptz, p_note text default null, p_patient uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_min int; v_patient uuid; v_staff boolean := false; v_id uuid;
begin
  select cl.doctor_id, d.appointment_minutes into v_doc, v_min
  from clinics cl join doctors d on d.id = cl.doctor_id where cl.id = p_clinic;
  if v_doc is null then raise exception 'clinic not found' using errcode = 'P0001'; end if;

  if p_patient is null then
    if not exists (select 1 from patients pa join profiles p on p.id = pa.id where pa.id = auth.uid() and not p.is_suspended) then
      raise exception 'only active patients can book' using errcode = '42501';
    end if;
    v_patient := auth.uid();
    if (select count(*) from appointments where patient_id = v_patient and doctor_id = v_doc
          and status in ('pending', 'confirmed') and starts_at > now()) >= 2 then
      raise exception 'too many upcoming bookings' using errcode = 'P0001';
    end if;
  else
    if not acts_for(v_doc, 'bookings') or not has_active_link(p_patient, v_doc) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
    v_patient := p_patient; v_staff := true;
  end if;

  if not exists (select 1 from clinic_slots(p_clinic, (p_starts_at at time zone 'Africa/Cairo')::date) s
                 where s.starts_at = p_starts_at and s.available) then
    raise exception 'slot not available' using errcode = 'P0001';
  end if;

  insert into appointments (doctor_id, clinic_id, patient_id, starts_at, ends_at, status, patient_note, created_by)
  values (v_doc, p_clinic, v_patient, p_starts_at, p_starts_at + make_interval(mins => v_min),
          case when v_staff then 'confirmed'::appointment_status else 'pending'::appointment_status end,
          nullif(trim(p_note), ''), auth.uid())
  returning id into v_id;
  perform write_audit('appointment.booked', 'appointments', v_id::text,
                      jsonb_build_object('patient_id', v_patient, 'doctor_id', v_doc, 'starts_at', p_starts_at));
  return v_id;
exception when unique_violation then
  raise exception 'slot not available' using errcode = 'P0001';
end $$;

create or replace function public.set_appointment_status(p_id uuid, p_status public.appointment_status)
returns void language plpgsql security definer set search_path = public as $$
declare a appointments;
begin
  select * into a from appointments where id = p_id for update;
  if not found then raise exception 'appointment not found' using errcode = 'P0001'; end if;
  if acts_for(a.doctor_id, 'bookings') then
    null;  -- staff may set any status
  elsif a.patient_id = auth.uid() then
    if p_status <> 'cancelled' or a.starts_at <= now() or a.status not in ('pending', 'confirmed') then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  else
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update appointments set status = p_status, updated_by = auth.uid() where id = p_id;
  perform write_audit('appointment.' || p_status::text, 'appointments', p_id::text,
                      jsonb_build_object('patient_id', a.patient_id, 'doctor_id', a.doctor_id));
end $$;

create or replace function public.doctor_appointments(p_from date, p_to date, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'starts_at', a.starts_at, 'ends_at', a.ends_at, 'status', a.status, 'patient_note', a.patient_note,
      'patient_id', a.patient_id, 'patient_name', p.full_name, 'patient_phone', p.phone, 'patient_avatar', p.avatar_url,
      'clinic_id', a.clinic_id, 'clinic_name', c.name,
      'local_date', to_char(a.starts_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI'))
      order by a.starts_at)
    from appointments a
    join profiles p on p.id = a.patient_id
    join clinics c on c.id = a.clinic_id
    where a.doctor_id = v_doc
      and a.starts_at >= (p_from::timestamp at time zone 'Africa/Cairo')
      and a.starts_at < ((p_to + 1)::timestamp at time zone 'Africa/Cairo')), '[]'::jsonb);
end $$;

create or replace function public.patient_my_appointments()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'starts_at', a.starts_at, 'status', a.status, 'patient_note', a.patient_note,
      'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url,
      'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'clinic_name', c.name, 'clinic_address', c.address, 'lat', c.lat, 'lng', c.lng,
      'local_date', to_char(a.starts_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI'))
      order by a.starts_at desc), '[]'::jsonb)
  from appointments a
  join profiles dp on dp.id = a.doctor_id
  join doctors d on d.id = a.doctor_id
  left join specialties s on s.id = d.specialty_id
  join clinics c on c.id = a.clinic_id
  where a.patient_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.acts_for(uuid, text), public.doctor_create_assistant(text, text, text, boolean, boolean, boolean, boolean),
  public.doctor_update_assistant(uuid, boolean, boolean, boolean, boolean), public.doctor_reset_assistant_password(uuid, text),
  public.doctor_remove_assistant(uuid), public.doctor_list_assistants(), public.get_my_context(),
  public.doctor_incoming_requests(uuid), public.doctor_my_patients(uuid), public.respond_join(uuid, boolean, text),
  public.doctor_create_patient(text, text, text, public.gender, date, uuid),
  public.doctor_reset_patient_password(uuid, text, uuid),
  public.can_view_medical(uuid, uuid), public.can_view_medical_object(text), public.list_medical_entries(uuid),
  public.list_medications(uuid), public.prescribe_medication(uuid, text, text, int, time, date, date, text, uuid),
  public.stop_prescription(uuid), public.set_med_reminders(uuid, boolean),
  public.clinic_slots(uuid, date), public.book_appointment(uuid, timestamptz, text, uuid),
  public.set_appointment_status(uuid, public.appointment_status), public.doctor_appointments(date, date, uuid),
  public.patient_my_appointments()
from public, anon;
grant execute on function public.acts_for(uuid, text), public.doctor_create_assistant(text, text, text, boolean, boolean, boolean, boolean),
  public.doctor_update_assistant(uuid, boolean, boolean, boolean, boolean), public.doctor_reset_assistant_password(uuid, text),
  public.doctor_remove_assistant(uuid), public.doctor_list_assistants(), public.get_my_context(),
  public.doctor_incoming_requests(uuid), public.doctor_my_patients(uuid), public.respond_join(uuid, boolean, text),
  public.doctor_create_patient(text, text, text, public.gender, date, uuid),
  public.doctor_reset_patient_password(uuid, text, uuid),
  public.can_view_medical(uuid, uuid), public.can_view_medical_object(text), public.list_medical_entries(uuid),
  public.list_medications(uuid), public.prescribe_medication(uuid, text, text, int, time, date, date, text, uuid),
  public.stop_prescription(uuid), public.set_med_reminders(uuid, boolean),
  public.clinic_slots(uuid, date), public.book_appointment(uuid, timestamptz, text, uuid),
  public.set_appointment_status(uuid, public.appointment_status), public.doctor_appointments(date, date, uuid),
  public.patient_my_appointments()
to authenticated;

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

drop policy if exists "medical: patient uploads own" on storage.objects;
create policy "medical: patient uploads own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'medical-files'
              and (storage.foldername(name))[1] = auth.uid()::text
              and exists (select 1 from public.patients where id = auth.uid()));

drop policy if exists "medical: read shared" on storage.objects;
create policy "medical: read shared"
  on storage.objects for select to authenticated
  using (bucket_id = 'medical-files'
         and ((storage.foldername(name))[1] = auth.uid()::text or public.can_view_medical_object(name)));

drop policy if exists "medical: patient deletes own" on storage.objects;
create policy "medical: patient deletes own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'medical-files' and (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- دكتوري — 0011: الخطة العلاجية حسب التخصص، مواعيد المتابعة، صورة الدوا لمراجعة الطبيب
-- * case_plans (+ history): the doctor's specialty assessment of a patient — problem, body areas,
--   goal, measurements (weight, height, BP…), course length and sessions. Every change is kept.
-- * followups: dated follow-up appointments the doctor sets for a patient (reminded on the patient's phone).
-- * medications: medicine type (form), photo, and "waiting for the doctor to set the dose".
-- =====================================================================

-- ---------------------------------------------------------------------
-- Medicines: type, photo, doctor review
-- ---------------------------------------------------------------------
alter table public.medications add column if not exists form text
  check (form is null or form in ('tablet', 'capsule', 'syrup', 'injection', 'drops', 'cream', 'inhaler', 'sachet', 'suppository', 'other'));
alter table public.medications add column if not exists photo_path text check (photo_path is null or length(photo_path) <= 400);
alter table public.medications add column if not exists needs_review boolean not null default false;
alter table public.medications add column if not exists review_doctor uuid references public.doctors(id) on delete set null;
alter table public.medications add column if not exists reviewed_at timestamptz;

-- Doctors see a medicine they prescribed, or one the patient sent them to review.
drop policy if exists meds_read on public.medications;
drop policy if exists meds_read on public.medications;
create policy meds_read on public.medications for select
  using (public.can_view_medical(patient_id, coalesce(prescribed_by, review_doctor)));
drop policy if exists meds_insert_own on public.medications;
drop policy if exists meds_insert_own on public.medications;
create policy meds_insert_own on public.medications for insert with check (
  patient_id = auth.uid() and prescribed_by is null
  and (review_doctor is null or public.has_active_link(auth.uid(), review_doctor)));
drop policy if exists meds_update_own on public.medications;
drop policy if exists meds_update_own on public.medications;
create policy meds_update_own on public.medications for update
  using (patient_id = auth.uid() and prescribed_by is null)
  with check (patient_id = auth.uid() and prescribed_by is null
              and (review_doctor is null or public.has_active_link(auth.uid(), review_doctor)));

create or replace function public.can_view_medical_object(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select can_view_medical(e.patient_id, e.shared_with) from medical_entries e where e.storage_path = p_name limit 1),
    (select can_view_medical(m.patient_id, coalesce(m.prescribed_by, m.review_doctor)) from medications m where m.photo_path = p_name limit 1),
    false);
$$;

create or replace function public.list_medications(p_patient uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'name', m.name, 'dose', m.dose, 'form', m.form, 'photo_path', m.photo_path,
           'every_hours', m.every_hours, 'first_time', to_char(m.first_time, 'HH24:MI'),
           'start_date', m.start_date, 'end_date', m.end_date,
           'instructions', m.instructions, 'is_active', m.is_active, 'reminders_on', m.reminders_on,
           'needs_review', m.needs_review, 'review_doctor', m.review_doctor, 'review_doctor_name', rp.full_name,
           'prescribed_by', m.prescribed_by, 'prescriber_name', pp.full_name, 'created_at', m.created_at,
           'doses_7d', (select count(*) from medication_doses x where x.medication_id = m.id and x.taken_at > now() - interval '7 days'),
           'last_taken', (select max(taken_at) from medication_doses x where x.medication_id = m.id))
         order by m.needs_review desc, m.is_active desc, m.created_at desc), '[]'::jsonb)
  from medications m
  left join profiles pp on pp.id = m.prescribed_by
  left join profiles rp on rp.id = m.review_doctor
  where m.patient_id = coalesce(p_patient, auth.uid())
    and can_view_medical(m.patient_id, coalesce(m.prescribed_by, m.review_doctor));
$$;

-- Prescriptions now carry the medicine type (tablet, syrup, injection…).
drop function if exists public.prescribe_medication(uuid, text, text, int, time, date, date, text, uuid);
create or replace function public.prescribe_medication(
  p_patient uuid, p_name text, p_dose text, p_every_hours int, p_first_time time,
  p_start_date date default null, p_end_date date default null, p_instructions text default null,
  p_doctor uuid default null, p_form text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'medical') or not has_active_link(p_patient, v_doc)
     or not exists (select 1 from doctors where id = v_doc and status = 'verified') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into medications (patient_id, prescribed_by, name, dose, form, every_hours, first_time, start_date, end_date, instructions)
  values (p_patient, v_doc, trim(p_name), nullif(trim(p_dose), ''), p_form, p_every_hours, p_first_time,
          coalesce(p_start_date, (now() at time zone 'Africa/Cairo')::date), p_end_date, nullif(trim(p_instructions), ''))
  returning id into v_id;
  perform write_audit('medication.prescribed', 'medications', v_id::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc, 'name', trim(p_name)));
  return v_id;
end $$;

-- Doctor sets the right dose for a medicine the patient photographed and sent.
create or replace function public.review_medication(
  p_med uuid, p_name text, p_dose text, p_every_hours int, p_first_time time,
  p_start_date date default null, p_end_date date default null, p_instructions text default null,
  p_doctor uuid default null, p_form text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); m medications;
begin
  select * into m from medications where id = p_med for update;
  if not found or m.review_doctor is distinct from v_doc or not m.needs_review
     or not acts_for(v_doc, 'medical') or not has_active_link(m.patient_id, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update medications set
    name = coalesce(nullif(trim(p_name), ''), name), dose = nullif(trim(p_dose), ''), form = coalesce(p_form, form),
    every_hours = p_every_hours, first_time = p_first_time,
    start_date = coalesce(p_start_date, (now() at time zone 'Africa/Cairo')::date), end_date = p_end_date,
    instructions = nullif(trim(p_instructions), ''),
    prescribed_by = v_doc, needs_review = false, reviewed_at = now(), is_active = true, reminders_on = true
  where id = p_med;
  perform write_audit('medication.reviewed', 'medications', p_med::text,
                      jsonb_build_object('patient_id', m.patient_id, 'doctor_id', v_doc));
end $$;

create or replace function public.doctor_pending_med_reviews(p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'medical') then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', m.name, 'form', m.form, 'photo_path', m.photo_path, 'instructions', m.instructions,
      'created_at', m.created_at, 'patient_id', m.patient_id, 'patient_name', p.full_name, 'patient_avatar', p.avatar_url)
      order by m.created_at)
    from medications m join profiles p on p.id = m.patient_id
    where m.review_doctor = v_doc and m.needs_review and has_active_link(m.patient_id, v_doc)), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Treatment plan per specialty
-- ---------------------------------------------------------------------
create table if not exists public.case_plans (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references public.patients(id) on delete cascade,
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  specialty_key  text check (specialty_key is null or length(specialty_key) <= 60),
  data           jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object' and pg_column_size(data) < 20000),
  course_weeks   int check (course_weeks is null or course_weeks between 1 and 260),
  sessions_total int check (sessions_total is null or sessions_total between 1 and 500),
  sessions_done  int not null default 0 check (sessions_done >= 0),
  start_date     date,
  status         text not null default 'active' check (status in ('active', 'completed', 'stopped')),
  created_by     uuid references public.profiles(id) on delete set null,
  updated_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists idx_case_plans_patient on public.case_plans (patient_id, doctor_id);
alter table public.case_plans enable row level security;
drop policy if exists plans_read on public.case_plans;
create policy plans_read on public.case_plans for select using (public.can_view_medical(patient_id, doctor_id));
revoke all on public.case_plans from anon;
grant select on public.case_plans to authenticated;
drop trigger if exists case_plans_touch on public.case_plans;
drop trigger if exists case_plans_touch on public.case_plans;
create trigger case_plans_touch before update on public.case_plans for each row execute function public.touch_updated_at();

create table if not exists public.case_plan_history (
  id            bigserial primary key,
  plan_id       uuid not null references public.case_plans(id) on delete cascade,
  data          jsonb not null,
  sessions_done int,
  status        text,
  changed_by    uuid references public.profiles(id) on delete set null,
  changed_at    timestamptz not null default now()
);
alter table public.case_plan_history enable row level security;
drop policy if exists plan_history_read on public.case_plan_history;
create policy plan_history_read on public.case_plan_history for select using (
  exists (select 1 from public.case_plans p where p.id = plan_id and public.can_view_medical(p.patient_id, p.doctor_id)));
revoke all on public.case_plan_history from anon;
grant select on public.case_plan_history to authenticated;

create or replace function public.case_plan_snapshot() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into case_plan_history (plan_id, data, sessions_done, status, changed_by)
  values (new.id, new.data, new.sessions_done, new.status, auth.uid());
  return new;
end $$;
drop trigger if exists case_plans_history on public.case_plans;
drop trigger if exists case_plans_history on public.case_plans;
create trigger case_plans_history after insert or update on public.case_plans
  for each row execute function public.case_plan_snapshot();

create or replace function public.save_case_plan(
  p_plan uuid, p_patient uuid, p_data jsonb, p_specialty_key text default null,
  p_course_weeks int default null, p_sessions_total int default null, p_start_date date default null,
  p_status text default 'active', p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'medical') or not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_plan is null then
    insert into case_plans (patient_id, doctor_id, specialty_key, data, course_weeks, sessions_total, start_date, status,
                            created_by, updated_by)
    values (p_patient, v_doc, p_specialty_key, coalesce(p_data, '{}'::jsonb), p_course_weeks, p_sessions_total,
            coalesce(p_start_date, (now() at time zone 'Africa/Cairo')::date), coalesce(p_status, 'active'), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update case_plans set data = coalesce(p_data, data), specialty_key = coalesce(p_specialty_key, specialty_key),
           course_weeks = p_course_weeks, sessions_total = p_sessions_total,
           start_date = coalesce(p_start_date, start_date), status = coalesce(p_status, status), updated_by = auth.uid()
     where id = p_plan and doctor_id = v_doc and patient_id = p_patient
    returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  perform write_audit('case_plan.saved', 'case_plans', v_id::text, jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc));
  return v_id;
end $$;

create or replace function public.add_plan_session(p_plan uuid, p_delta int default 1)
returns int language plpgsql security definer set search_path = public as $$
declare p case_plans; v_done int;
begin
  select * into p from case_plans where id = p_plan for update;
  if not found or not acts_for(p.doctor_id, 'medical') or not has_active_link(p.patient_id, p.doctor_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  v_done := greatest(0, p.sessions_done + coalesce(p_delta, 1));
  update case_plans set sessions_done = v_done, updated_by = auth.uid(),
         status = case when p.sessions_total is not null and v_done >= p.sessions_total then 'completed' else status end
   where id = p_plan;
  return v_done;
end $$;

create or replace function public.list_case_plans(p_patient uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'patient_id', c.patient_id, 'doctor_id', c.doctor_id, 'doctor_name', dp.full_name,
      'doctor_avatar', dp.avatar_url, 'specialty_key', c.specialty_key, 'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'data', c.data, 'course_weeks', c.course_weeks, 'sessions_total', c.sessions_total, 'sessions_done', c.sessions_done,
      'start_date', c.start_date, 'status', c.status, 'updated_at', c.updated_at,
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.changed_at, 'measures', h.data->'measures',
                                                               'sessions_done', h.sessions_done) order by h.changed_at), '[]'::jsonb)
                  from (select * from case_plan_history h where h.plan_id = c.id order by h.changed_at desc limit 30) h))
      order by (c.status = 'active') desc, c.updated_at desc), '[]'::jsonb)
  from case_plans c
  join profiles dp on dp.id = c.doctor_id
  join doctors d on d.id = c.doctor_id
  left join specialties s on s.id = d.specialty_id
  where c.patient_id = coalesce(p_patient, auth.uid())
    and can_view_medical(c.patient_id, c.doctor_id);
$$;

-- ---------------------------------------------------------------------
-- Follow-up appointments set by the doctor
-- ---------------------------------------------------------------------
create table if not exists public.followups (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients(id) on delete cascade,
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  plan_id      uuid references public.case_plans(id) on delete set null,
  scheduled_at timestamptz not null,
  title        text not null check (length(trim(title)) between 1 and 150),
  notes        text check (notes is null or length(notes) <= 1000),
  status       text not null default 'scheduled' check (status in ('scheduled', 'done', 'cancelled', 'missed')),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_followups_patient on public.followups (patient_id, scheduled_at);
create index if not exists idx_followups_doctor on public.followups (doctor_id, scheduled_at);
alter table public.followups enable row level security;
drop policy if exists followups_read on public.followups;
create policy followups_read on public.followups for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings') or public.acts_for(doctor_id, 'medical') or public.is_admin());
revoke all on public.followups from anon;
grant select on public.followups to authenticated;
drop trigger if exists followups_touch on public.followups;
drop trigger if exists followups_touch on public.followups;
create trigger followups_touch before update on public.followups for each row execute function public.touch_updated_at();

create or replace function public.schedule_followup(
  p_patient uuid, p_at timestamptz, p_title text, p_notes text default null,
  p_plan uuid default null, p_doctor uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid; v_phone text; v_name text;
begin
  if not (acts_for(v_doc, 'bookings') or acts_for(v_doc, 'medical')) or not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_at < now() - interval '1 hour' then raise exception 'date is in the past' using errcode = 'P0001'; end if;
  if p_plan is not null and not exists (select 1 from case_plans where id = p_plan and patient_id = p_patient and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into followups (patient_id, doctor_id, plan_id, scheduled_at, title, notes, created_by)
  values (p_patient, v_doc, p_plan, p_at, trim(p_title), nullif(trim(p_notes), ''), auth.uid())
  returning id into v_id;
  select phone, full_name into v_phone, v_name from profiles where id = p_patient;
  perform write_audit('followup.scheduled', 'followups', v_id::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc, 'at', p_at));
  return jsonb_build_object('id', v_id, 'patient_phone', v_phone, 'patient_name', v_name);
end $$;

create or replace function public.set_followup_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare f followups;
begin
  select * into f from followups where id = p_id for update;
  if not found or not (acts_for(f.doctor_id, 'bookings') or acts_for(f.doctor_id, 'medical')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_status not in ('scheduled', 'done', 'cancelled', 'missed') then raise exception 'invalid status' using errcode = 'P0001'; end if;
  update followups set status = p_status where id = p_id;
end $$;

create or replace function public.patient_followups(p_patient uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'scheduled_at', f.scheduled_at, 'title', f.title, 'notes', f.notes, 'status', f.status,
      'doctor_id', f.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url, 'plan_id', f.plan_id,
      'local_date', to_char(f.scheduled_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(f.scheduled_at at time zone 'Africa/Cairo', 'HH24:MI'))
      order by f.scheduled_at desc), '[]'::jsonb)
  from followups f join profiles dp on dp.id = f.doctor_id
  where f.patient_id = coalesce(p_patient, auth.uid())
    and (f.patient_id = auth.uid() or acts_for(f.doctor_id, 'bookings') or acts_for(f.doctor_id, 'medical'));
$$;

create or replace function public.doctor_followups(p_from date, p_to date, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not (acts_for(v_doc, 'bookings') or acts_for(v_doc, 'medical')) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', f.id, 'scheduled_at', f.scheduled_at, 'title', f.title, 'notes', f.notes, 'status', f.status,
      'patient_id', f.patient_id, 'patient_name', p.full_name, 'patient_phone', p.phone, 'patient_avatar', p.avatar_url,
      'local_date', to_char(f.scheduled_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(f.scheduled_at at time zone 'Africa/Cairo', 'HH24:MI'))
      order by f.scheduled_at)
    from followups f join profiles p on p.id = f.patient_id
    where f.doctor_id = v_doc
      and f.scheduled_at >= (p_from::timestamp at time zone 'Africa/Cairo')
      and f.scheduled_at < ((p_to + 1)::timestamp at time zone 'Africa/Cairo')), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.prescribe_medication(uuid, text, text, int, time, date, date, text, uuid, text) from public, anon;
grant execute on function public.prescribe_medication(uuid, text, text, int, time, date, date, text, uuid, text) to authenticated;
revoke all on function public.can_view_medical_object(text), public.list_medications(uuid),
  public.review_medication(uuid, text, text, int, time, date, date, text, uuid, text), public.doctor_pending_med_reviews(uuid),
  public.save_case_plan(uuid, uuid, jsonb, text, int, int, date, text, uuid), public.add_plan_session(uuid, int),
  public.list_case_plans(uuid), public.schedule_followup(uuid, timestamptz, text, text, uuid, uuid),
  public.set_followup_status(uuid, text), public.patient_followups(uuid), public.doctor_followups(date, date, uuid)
from public, anon;
grant execute on function public.can_view_medical_object(text), public.list_medications(uuid),
  public.review_medication(uuid, text, text, int, time, date, date, text, uuid, text), public.doctor_pending_med_reviews(uuid),
  public.save_case_plan(uuid, uuid, jsonb, text, int, int, date, text, uuid), public.add_plan_session(uuid, int),
  public.list_case_plans(uuid), public.schedule_followup(uuid, timestamptz, text, text, uuid, uuid),
  public.set_followup_status(uuid, text), public.patient_followups(uuid), public.doctor_followups(date, date, uuid)
to authenticated;

-- =====================================================================
-- دكتوري — 0012: رصيدي اليومي (إيرادات الحالات + المصروفات + الصافي)
-- * doctor_income: each paid case — كشف / إعادة / تحليل / أشعة / جلسة / إجراء / أخرى.
-- * doctor_expenses: what the doctor spent — type, amount, reason.
-- * Day / month / year summaries and a calendar of cases + net per day (Cairo dates).
-- * Doctors can let an assistant (receptionist) record and see the ledger: can_finance.
-- =====================================================================

alter table public.doctor_assistants add column if not exists can_finance boolean not null default false;
alter table public.doctors add column if not exists price_list jsonb not null default '{}'::jsonb
  check (jsonb_typeof(price_list) = 'object' and pg_column_size(price_list) < 4000);

create or replace function public.acts_for(p_doctor uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select (auth.uid() = p_doctor and exists (select 1 from profiles p where p.id = p_doctor and not p.is_suspended))
      or exists (
        select 1 from doctor_assistants a join profiles p on p.id = a.assistant_id
        where a.doctor_id = p_doctor and a.assistant_id = auth.uid() and not p.is_suspended
          and case p_perm
                when 'bookings' then a.can_bookings
                when 'patients' then a.can_patients
                when 'add_patients' then a.can_add_patients
                when 'medical' then a.can_medical
                when 'finance' then a.can_finance
                when 'any' then true
                else false end);
$$;

create table if not exists public.doctor_income (
  id             uuid primary key default gen_random_uuid(),
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  patient_id     uuid references public.patients(id) on delete set null,
  patient_name   text check (patient_name is null or length(patient_name) <= 120),
  kind           text not null check (kind in ('visit', 'revisit', 'lab', 'xray', 'session', 'procedure', 'other')),
  amount         numeric(12,2) not null check (amount > 0 and amount < 10000000),
  paid_on        date not null,
  note           text check (note is null or length(note) <= 300),
  appointment_id uuid references public.appointments(id) on delete set null,
  created_by     uuid references public.profiles(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists idx_doctor_income_day on public.doctor_income (doctor_id, paid_on);
alter table public.doctor_income enable row level security;
drop policy if exists income_read on public.doctor_income;
create policy income_read on public.doctor_income for select using (public.acts_for(doctor_id, 'finance'));
revoke all on public.doctor_income from anon;
grant select on public.doctor_income to authenticated;

create table if not exists public.doctor_expenses (
  id          uuid primary key default gen_random_uuid(),
  doctor_id   uuid not null references public.doctors(id) on delete cascade,
  category    text not null check (category in ('rent', 'salaries', 'supplies', 'utilities', 'equipment',
                                                'maintenance', 'lab', 'marketing', 'transport', 'other')),
  amount      numeric(12,2) not null check (amount > 0 and amount < 10000000),
  spent_on    date not null,
  reason      text check (reason is null or length(reason) <= 300),
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists idx_doctor_expenses_day on public.doctor_expenses (doctor_id, spent_on);
alter table public.doctor_expenses enable row level security;
drop policy if exists expenses_read on public.doctor_expenses;
create policy expenses_read on public.doctor_expenses for select using (public.acts_for(doctor_id, 'finance'));
revoke all on public.doctor_expenses from anon;
grant select on public.doctor_expenses to authenticated;

-- ---------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------
create or replace function public.save_income(
  p_id uuid, p_kind text, p_amount numeric, p_on date default null,
  p_patient uuid default null, p_patient_name text default null, p_note text default null,
  p_appointment uuid default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_patient is not null and not exists (select 1 from care_links where patient_id = p_patient and doctor_id = v_doc)
     and not exists (select 1 from appointments where patient_id = p_patient and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_appointment is not null and not exists (select 1 from appointments where id = p_appointment and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into doctor_income (doctor_id, patient_id, patient_name, kind, amount, paid_on, note, appointment_id, created_by)
    values (v_doc, p_patient, nullif(trim(p_patient_name), ''), p_kind, p_amount,
            coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_note), ''), p_appointment, auth.uid())
    returning id into v_id;
  else
    update doctor_income set patient_id = p_patient, patient_name = nullif(trim(p_patient_name), ''), kind = p_kind,
           amount = p_amount, paid_on = coalesce(p_on, paid_on), note = nullif(trim(p_note), ''),
           appointment_id = coalesce(p_appointment, appointment_id)
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.save_expense(
  p_id uuid, p_category text, p_amount numeric, p_on date default null, p_reason text default null,
  p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into doctor_expenses (doctor_id, category, amount, spent_on, reason, created_by)
    values (v_doc, p_category, p_amount, coalesce(p_on, (now() at time zone 'Africa/Cairo')::date),
            nullif(trim(p_reason), ''), auth.uid())
    returning id into v_id;
  else
    update doctor_expenses set category = p_category, amount = p_amount, spent_on = coalesce(p_on, spent_on),
           reason = nullif(trim(p_reason), '')
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.delete_finance_entry(p_type text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_amount numeric;
begin
  if p_type = 'income' then
    select doctor_id, amount into v_doc, v_amount from doctor_income where id = p_id;
  elsif p_type = 'expense' then
    select doctor_id, amount into v_doc, v_amount from doctor_expenses where id = p_id;
  end if;
  if v_doc is null or not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_type = 'income' then delete from doctor_income where id = p_id; else delete from doctor_expenses where id = p_id; end if;
  perform write_audit('finance.deleted', case when p_type = 'income' then 'doctor_income' else 'doctor_expenses' end,
                      p_id::text, jsonb_build_object('doctor_id', v_doc, 'amount', v_amount));
end $$;

create or replace function public.set_price_list(p_prices jsonb, p_doctor uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if auth.uid() is distinct from v_doc or not acts_for(v_doc, 'finance') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update doctors set price_list = coalesce(p_prices, '{}'::jsonb) where id = v_doc;
end $$;

create or replace function public.set_assistant_finance(p_assistant uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  update doctor_assistants set can_finance = coalesce(p_on, false)
   where doctor_id = auth.uid() and assistant_id = p_assistant;
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('assistant.permissions_changed', 'profiles', p_assistant::text, jsonb_build_object('finance', p_on));
end $$;

-- ---------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------
create or replace function public.finance_day(p_day date default null, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_day date := coalesce(p_day, (now() at time zone 'Africa/Cairo')::date);
        v_in numeric; v_out numeric; v_cases int;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  select coalesce(sum(amount), 0), count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text))
    into v_in, v_cases from doctor_income where doctor_id = v_doc and paid_on = v_day;
  select coalesce(sum(amount), 0) into v_out from doctor_expenses where doctor_id = v_doc and spent_on = v_day;
  return jsonb_build_object(
    'day', v_day, 'income', v_in, 'expenses', v_out, 'net', v_in - v_out, 'cases', v_cases,
    'by_kind', (select coalesce(jsonb_object_agg(kind, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                from (select kind, count(*) n, sum(amount) s from doctor_income
                      where doctor_id = v_doc and paid_on = v_day group by kind) k),
    'income_items', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', i.id, 'kind', i.kind, 'amount', i.amount, 'note', i.note, 'patient_id', i.patient_id,
          'patient_name', coalesce(p.full_name, i.patient_name), 'patient_avatar', p.avatar_url,
          'created_at', i.created_at, 'by', cb.full_name) order by i.created_at), '[]'::jsonb)
        from doctor_income i left join profiles p on p.id = i.patient_id left join profiles cb on cb.id = i.created_by
        where i.doctor_id = v_doc and i.paid_on = v_day),
    'expense_items', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', e.id, 'category', e.category, 'amount', e.amount, 'reason', e.reason,
          'created_at', e.created_at, 'by', cb.full_name) order by e.created_at), '[]'::jsonb)
        from doctor_expenses e left join profiles cb on cb.id = e.created_by
        where e.doctor_id = v_doc and e.spent_on = v_day),
    'prices', (select price_list from doctors where id = v_doc));
end $$;

create or replace function public.finance_month(p_year int, p_month int, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_from date := make_date(p_year, p_month, 1);
        v_to date := (make_date(p_year, p_month, 1) + interval '1 month')::date;
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with inc as (
      select paid_on d, sum(amount) s, count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) c
      from doctor_income where doctor_id = v_doc and paid_on >= v_from and paid_on < v_to group by paid_on),
    exp as (
      select spent_on d, sum(amount) s from doctor_expenses
      where doctor_id = v_doc and spent_on >= v_from and spent_on < v_to group by spent_on),
    days as (
      select coalesce(inc.d, exp.d) d, coalesce(inc.s, 0) i, coalesce(exp.s, 0) e, coalesce(inc.c, 0) c
      from inc full join exp on exp.d = inc.d)
    select jsonb_build_object(
      'year', p_year, 'month', p_month,
      'days', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'income', i, 'expenses', e, 'net', i - e, 'cases', c)
                                         order by d), '[]'::jsonb) from days),
      'income', (select coalesce(sum(i), 0) from days),
      'expenses', (select coalesce(sum(e), 0) from days),
      'net', (select coalesce(sum(i - e), 0) from days),
      'cases', (select coalesce(sum(c), 0) from days),
      'by_kind', (select coalesce(jsonb_object_agg(kind, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                  from (select kind, count(*) n, sum(amount) s from doctor_income
                        where doctor_id = v_doc and paid_on >= v_from and paid_on < v_to group by kind) k),
      'by_category', (select coalesce(jsonb_object_agg(category, jsonb_build_object('count', n, 'amount', s)), '{}'::jsonb)
                      from (select category, count(*) n, sum(amount) s from doctor_expenses
                            where doctor_id = v_doc and spent_on >= v_from and spent_on < v_to group by category) k)));
end $$;

create or replace function public.finance_year(p_year int, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not acts_for(v_doc, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  return (
    with m as (select generate_series(1, 12) mo),
    inc as (select extract(month from paid_on)::int mo, sum(amount) s, count(*) c from doctor_income
            where doctor_id = v_doc and extract(year from paid_on) = p_year group by 1),
    exp as (select extract(month from spent_on)::int mo, sum(amount) s from doctor_expenses
            where doctor_id = v_doc and extract(year from spent_on) = p_year group by 1)
    select jsonb_build_object('year', p_year,
      'months', jsonb_agg(jsonb_build_object('month', m.mo, 'income', coalesce(inc.s, 0), 'expenses', coalesce(exp.s, 0),
                                             'net', coalesce(inc.s, 0) - coalesce(exp.s, 0), 'entries', coalesce(inc.c, 0))
                          order by m.mo),
      'income', coalesce(sum(inc.s), 0), 'expenses', coalesce(sum(exp.s), 0),
      'net', coalesce(sum(inc.s), 0) - coalesce(sum(exp.s), 0))
    from m left join inc on inc.mo = m.mo left join exp on exp.mo = m.mo);
end $$;

-- Assistants list and context include the finance permission.
create or replace function public.doctor_list_assistants()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'assistant_id', a.assistant_id, 'full_name', p.full_name, 'phone', p.phone, 'avatar_url', p.avatar_url,
           'is_suspended', p.is_suspended, 'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
           'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'can_finance', a.can_finance,
           'created_at', a.created_at)
         order by a.created_at), '[]'::jsonb)
  from doctor_assistants a join profiles p on p.id = a.assistant_id
  where a.doctor_id = auth.uid();
$$;

create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'phone', p.phone, 'login_kind', p.login_kind,
    'locale', p.locale, 'is_suspended', p.is_suspended, 'avatar_url', p.avatar_url,
    'doctor_status', d.status, 'specialty_id', d.specialty_id,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null),
    'assistant_of', (select jsonb_build_object(
        'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url,
        'doctor_status', dd.status, 'specialty_ar', ds.name_ar, 'specialty_en', ds.name_en,
        'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
        'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'can_finance', a.can_finance)
      from doctor_assistants a
      join profiles dp on dp.id = a.doctor_id
      join doctors dd on dd.id = a.doctor_id
      left join specialties ds on ds.id = dd.specialty_id
      where a.assistant_id = p.id))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

revoke all on function public.save_income(uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.save_expense(uuid, text, numeric, date, text, uuid), public.delete_finance_entry(text, uuid),
  public.set_price_list(jsonb, uuid), public.set_assistant_finance(uuid, boolean),
  public.finance_day(date, uuid), public.finance_month(int, int, uuid), public.finance_year(int, uuid)
from public, anon;
grant execute on function public.save_income(uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.save_expense(uuid, text, numeric, date, text, uuid), public.delete_finance_entry(text, uuid),
  public.set_price_list(jsonb, uuid), public.set_assistant_finance(uuid, boolean),
  public.finance_day(date, uuid), public.finance_month(int, int, uuid), public.finance_year(int, uuid)
to authenticated;

-- =====================================================================
-- دكتوري — 0013: الروشتة
-- * prescriptions: what the doctor wrote — diagnosis, medicines (name, type, dose, how often, days, notes).
--   Sent to a linked patient in the app (and optionally added to «علاجي» with reminders),
--   or written for a walk-in by name to print / share as PDF.
-- * doctors.rx_settings: the prescription look — clinic logo, phones, WhatsApp, header and footer lines.
-- =====================================================================

alter table public.doctors add column if not exists rx_settings jsonb not null default '{}'::jsonb
  check (jsonb_typeof(rx_settings) = 'object' and pg_column_size(rx_settings) < 6000);

create table if not exists public.prescriptions (
  id            uuid primary key default gen_random_uuid(),
  doctor_id     uuid not null references public.doctors(id) on delete cascade,
  patient_id    uuid references public.patients(id) on delete set null,
  patient_name  text check (patient_name is null or length(patient_name) <= 120),
  patient_age   text check (patient_age is null or length(patient_age) <= 20),
  clinic_id     uuid references public.clinics(id) on delete set null,
  diagnosis     text check (diagnosis is null or length(diagnosis) <= 1000),
  items         jsonb not null default '[]'::jsonb check (jsonb_typeof(items) = 'array' and pg_column_size(items) < 30000),
  notes         text check (notes is null or length(notes) <= 1500),
  next_visit    date,
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists idx_prescriptions_doctor on public.prescriptions (doctor_id, created_at);
create index if not exists idx_prescriptions_patient on public.prescriptions (patient_id, created_at);
alter table public.prescriptions enable row level security;
drop policy if exists rx_read on public.prescriptions;
create policy rx_read on public.prescriptions for select
  using (patient_id = auth.uid() or public.acts_for(doctor_id, 'medical'));
revoke all on public.prescriptions from anon;
grant select on public.prescriptions to authenticated;

create or replace function public.create_prescription(
  p_patient uuid, p_patient_name text, p_items jsonb, p_diagnosis text default null, p_notes text default null,
  p_clinic uuid default null, p_next_visit date default null, p_add_to_meds boolean default true,
  p_patient_age text default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid; it jsonb; v_every int; v_days int;
begin
  if not acts_for(v_doc, 'medical') or not exists (select 1 from doctors where id = v_doc and status = 'verified') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_patient is not null and not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_patient is null and length(trim(coalesce(p_patient_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'add at least one medicine' using errcode = 'P0001';
  end if;
  if p_clinic is not null and not exists (select 1 from clinics where id = p_clinic and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into prescriptions (doctor_id, patient_id, patient_name, patient_age, clinic_id, diagnosis, items, notes, next_visit, created_by)
  values (v_doc, p_patient,
          coalesce(nullif(trim(p_patient_name), ''), (select full_name from profiles where id = p_patient)),
          nullif(trim(p_patient_age), ''), p_clinic, nullif(trim(p_diagnosis), ''), p_items, nullif(trim(p_notes), ''),
          p_next_visit, auth.uid())
  returning id into v_id;

  -- Linked patient: each medicine also goes to «علاجي» with phone reminders.
  if p_patient is not null and coalesce(p_add_to_meds, true) then
    for it in select * from jsonb_array_elements(p_items) loop
      continue when length(trim(coalesce(it->>'name', ''))) = 0;
      v_every := case when (it->>'every_hours') ~ '^\d+$' and (it->>'every_hours')::int in (4, 6, 8, 12, 24)
                      then (it->>'every_hours')::int else null end;
      continue when v_every is null;
      v_days := case when (it->>'days') ~ '^\d+$' then least((it->>'days')::int, 365) else null end;
      insert into medications (patient_id, prescribed_by, name, dose, form, every_hours, first_time, start_date, end_date, instructions)
      values (p_patient, v_doc, left(trim(it->>'name'), 120), nullif(left(trim(coalesce(it->>'dose', '')), 120), ''),
              case when it->>'form' in ('tablet', 'capsule', 'syrup', 'injection', 'drops', 'cream', 'inhaler', 'sachet',
                                        'suppository', 'other') then it->>'form' end,
              v_every, coalesce(nullif(it->>'first_time', '')::time, '09:00'),
              (now() at time zone 'Africa/Cairo')::date,
              case when v_days is not null and v_days > 0 then (now() at time zone 'Africa/Cairo')::date + v_days - 1 end,
              nullif(left(trim(coalesce(it->>'instructions', '')), 1000), ''));
    end loop;
  end if;
  perform write_audit('prescription.created', 'prescriptions', v_id::text,
                      jsonb_build_object('patient_id', p_patient, 'doctor_id', v_doc));
  return v_id;
end $$;

-- Everything needed to draw a prescription: doctor, specialty, clinics, logo and contact settings.
create or replace function public.rx_header(p_doctor uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'doctor_id', d.id, 'doctor_name', p.full_name, 'title', d.title, 'avatar_url', p.avatar_url,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en, 'qualifications', d.qualifications,
    'public_phone', d.public_phone, 'settings', d.rx_settings,
    'clinics', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'address', c.address,
                                                             'area', c.area, 'phone', c.phone,
                                                             'city', ci.name_ar, 'governorate', g.name_ar)
                                          order by c.created_at), '[]'::jsonb)
                from clinics c left join cities ci on ci.id = c.city_id left join governorates g on g.id = c.governorate_id
                where c.doctor_id = d.id and c.is_active))
  from doctors d join profiles p on p.id = d.id left join specialties s on s.id = d.specialty_id
  where d.id = coalesce(p_doctor, auth.uid());
$$;

create or replace function public.set_rx_settings(p_settings jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from doctors where id = auth.uid()) then raise exception 'not allowed' using errcode = '42501'; end if;
  update doctors set rx_settings = coalesce(p_settings, '{}'::jsonb) where id = auth.uid();
end $$;

create or replace function public.list_prescriptions(p_patient uuid default null, p_doctor uuid default null, p_limit int default 50)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select r.created_at, jsonb_build_object(
      'id', r.id, 'doctor_id', r.doctor_id, 'patient_id', r.patient_id, 'patient_name', r.patient_name,
      'patient_age', r.patient_age, 'clinic_id', r.clinic_id, 'diagnosis', r.diagnosis, 'items', r.items,
      'notes', r.notes, 'next_visit', r.next_visit, 'created_at', r.created_at,
      'doctor_name', dp.full_name, 'specialty_en', s.name_en) j
    from prescriptions r
    join profiles dp on dp.id = r.doctor_id
    join doctors d on d.id = r.doctor_id
    left join specialties s on s.id = d.specialty_id
    where (p_patient is null or r.patient_id = p_patient)
      and (p_doctor is null or r.doctor_id = p_doctor)
      and (r.patient_id = auth.uid() or acts_for(r.doctor_id, 'medical'))
      and (p_patient is not null or p_doctor is not null or r.patient_id = auth.uid())
    order by r.created_at desc
    limit least(coalesce(p_limit, 50), 200)) x;
$$;

revoke all on function public.create_prescription(uuid, text, jsonb, text, text, uuid, date, boolean, text, uuid),
  public.rx_header(uuid), public.set_rx_settings(jsonb), public.list_prescriptions(uuid, uuid, int) from public, anon;
grant execute on function public.create_prescription(uuid, text, jsonb, text, text, uuid, date, boolean, text, uuid),
  public.rx_header(uuid), public.set_rx_settings(jsonb), public.list_prescriptions(uuid, uuid, int) to authenticated;

-- =====================================================================
-- دكتوري — 0014: تأكيد حسابات الإيميل تلقائياً
-- The free Supabase mailer only delivers to the project team and a few emails per hour,
-- so doctors never got the confirmation link. Doctors are verified by the admin's WhatsApp
-- activation code instead, so email accounts are confirmed as soon as they are created.
-- =====================================================================
create or replace function public.auto_confirm_email() returns trigger
language plpgsql security definer set search_path = public, auth as $$
begin
  if new.email is not null and new.email_confirmed_at is null then
    new.email_confirmed_at := now();
  end if;
  return new;
end $$;
revoke all on function public.auto_confirm_email() from public, anon, authenticated;

drop trigger if exists auto_confirm_email on auth.users;
drop trigger if exists auto_confirm_email on auth.users;
create trigger auto_confirm_email before insert on auth.users
  for each row execute function public.auto_confirm_email();

-- Accounts that signed up and are still waiting for the email.
update auth.users set email_confirmed_at = now()
 where email is not null and email_confirmed_at is null and deleted_at is null;

-- =====================================================================
-- دكتوري — 0015: عروض الأطباء + إعلانات الإدارة
-- * doctor_offers: a verified doctor announces something at their clinic (an operation, the visit price,
--   a service, a discount). Shown to every user of the app; patients book with the offer in one tap.
--   The admin can hide any offer.
-- * announcements: the platform owner posts to doctors, patients or everyone; shown at the top of the
--   home screen until the user closes it or it ends.
-- * Public "offers" bucket for their pictures (each user uploads only in their own folder).
-- =====================================================================

create table if not exists public.doctor_offers (
  id           uuid primary key default gen_random_uuid(),
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  clinic_id    uuid references public.clinics(id) on delete set null,
  kind         text not null default 'service'
               check (kind in ('operation', 'visit_price', 'service', 'discount', 'package', 'other')),
  title        text not null check (length(trim(title)) between 3 and 120),
  body         text check (body is null or length(body) <= 1500),
  price        numeric(12,2) check (price is null or (price >= 0 and price < 10000000)),
  old_price    numeric(12,2) check (old_price is null or (old_price >= 0 and old_price < 10000000)),
  image_url    text check (image_url is null or length(image_url) <= 500),
  valid_until  date,
  is_active    boolean not null default true,
  hidden_by_admin boolean not null default false,
  views        int not null default 0,
  bookings     int not null default 0,
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_doctor_offers_doctor on public.doctor_offers (doctor_id, created_at);
alter table public.doctor_offers enable row level security;
drop policy if exists offers_read on public.doctor_offers;
create policy offers_read on public.doctor_offers for select using (
  public.acts_for(doctor_id, 'any') or public.is_admin()
  or (is_active and not hidden_by_admin
      and (valid_until is null or valid_until >= (now() at time zone 'Africa/Cairo')::date)
      and exists (select 1 from public.doctors d where d.id = doctor_id and d.status = 'verified')));
revoke all on public.doctor_offers from anon;
grant select on public.doctor_offers to authenticated;
drop trigger if exists doctor_offers_touch on public.doctor_offers;
drop trigger if exists doctor_offers_touch on public.doctor_offers;
create trigger doctor_offers_touch before update on public.doctor_offers for each row execute function public.touch_updated_at();

create table if not exists public.announcements (
  id         uuid primary key default gen_random_uuid(),
  audience   text not null default 'all' check (audience in ('all', 'doctors', 'patients')),
  title      text not null check (length(trim(title)) between 2 and 120),
  body       text check (body is null or length(body) <= 2000),
  image_url  text check (image_url is null or length(image_url) <= 500),
  link_url   text check (link_url is null or (length(link_url) <= 500 and link_url ~* '^https?://')),
  ends_on    date,
  is_active  boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.announcements enable row level security;
drop policy if exists announcements_admin_read on public.announcements;
create policy announcements_admin_read on public.announcements for select using (public.is_admin());
revoke all on public.announcements from anon;
grant select on public.announcements to authenticated;

create table if not exists public.announcement_dismissals (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  dismissed_at    timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_dismissals enable row level security;
revoke all on public.announcement_dismissals from anon, authenticated;

-- ---------------------------------------------------------------------
-- Offers
-- ---------------------------------------------------------------------
create or replace function public.save_offer(
  p_id uuid, p_title text, p_kind text default 'service', p_body text default null,
  p_price numeric default null, p_old_price numeric default null, p_image_url text default null,
  p_valid_until date default null, p_clinic uuid default null, p_active boolean default true,
  p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not (auth.uid() = v_doc or acts_for(v_doc, 'bookings'))
     or not exists (select 1 from doctors d join profiles p on p.id = d.id
                    where d.id = v_doc and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if p_clinic is not null and not exists (select 1 from clinics where id = p_clinic and doctor_id = v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    if (select count(*) from doctor_offers where doctor_id = v_doc and created_at > now() - interval '1 day') >= 5 then
      raise exception 'daily offer limit reached' using errcode = 'P0001';
    end if;
    insert into doctor_offers (doctor_id, clinic_id, kind, title, body, price, old_price, image_url, valid_until, is_active, created_by)
    values (v_doc, p_clinic, coalesce(p_kind, 'service'), trim(p_title), nullif(trim(p_body), ''), p_price, p_old_price,
            nullif(trim(p_image_url), ''), p_valid_until, coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update doctor_offers set clinic_id = p_clinic, kind = coalesce(p_kind, kind), title = trim(p_title),
           body = nullif(trim(p_body), ''), price = p_price, old_price = p_old_price,
           image_url = nullif(trim(p_image_url), ''), valid_until = p_valid_until, is_active = coalesce(p_active, is_active)
     where id = p_id and doctor_id = v_doc
    returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  perform write_audit('offer.saved', 'doctor_offers', v_id::text, jsonb_build_object('doctor_id', v_doc));
  return v_id;
end $$;

create or replace function public.delete_offer(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  select doctor_id into v_doc from doctor_offers where id = p_id;
  if v_doc is null or not (auth.uid() = v_doc or acts_for(v_doc, 'bookings') or is_admin()) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from doctor_offers where id = p_id;
  perform write_audit('offer.deleted', 'doctor_offers', p_id::text, jsonb_build_object('doctor_id', v_doc));
end $$;

create or replace function public.admin_hide_offer(p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update doctor_offers set hidden_by_admin = coalesce(p_hidden, true) where id = p_id;
  perform write_audit('offer.hidden', 'doctor_offers', p_id::text, jsonb_build_object('hidden', p_hidden));
end $$;

-- Offers feed. p_mine = the doctor's own (any state); admin sees everything incl. hidden.
create or replace function public.list_offers(
  p_specialty int default null, p_governorate int default null, p_doctor uuid default null,
  p_mine boolean default false, p_limit int default 60)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x.j order by x.created_at desc), '[]'::jsonb) from (
    select o.created_at, jsonb_build_object(
      'id', o.id, 'doctor_id', o.doctor_id, 'kind', o.kind, 'title', o.title, 'body', o.body,
      'price', o.price, 'old_price', o.old_price, 'image_url', o.image_url, 'valid_until', o.valid_until,
      'is_active', o.is_active, 'hidden_by_admin', o.hidden_by_admin, 'views', o.views, 'bookings', o.bookings,
      'created_at', o.created_at,
      'doctor_name', p.full_name, 'doctor_avatar', p.avatar_url, 'doctor_title', d.title,
      'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'clinic_name', c.name, 'clinic_address', c.address, 'clinic_phone', c.phone,
      'city', ci.name_ar, 'governorate', g.name_ar) j
    from doctor_offers o
    join doctors d on d.id = o.doctor_id
    join profiles p on p.id = d.id
    left join specialties s on s.id = d.specialty_id
    left join clinics c on c.id = coalesce(o.clinic_id,
         (select c2.id from clinics c2 where c2.doctor_id = d.id and c2.is_active order by c2.created_at limit 1))
    left join cities ci on ci.id = c.city_id
    left join governorates g on g.id = c.governorate_id
    where case
            when coalesce(p_mine, false) then acts_for(o.doctor_id, 'any') and o.doctor_id = coalesce(p_doctor, o.doctor_id)
            when is_admin() and p_doctor is null and p_specialty is null and p_governorate is null then true
            else o.is_active and not o.hidden_by_admin and d.status = 'verified' and not p.is_suspended
                 and (o.valid_until is null or o.valid_until >= (now() at time zone 'Africa/Cairo')::date)
          end
      and (p_specialty is null or d.specialty_id = p_specialty)
      and (p_governorate is null or c.governorate_id = p_governorate)
      and (p_doctor is null or o.doctor_id = p_doctor)
    order by o.created_at desc
    limit least(coalesce(p_limit, 60), 200)) x;
$$;

create or replace function public.offer_event(p_id uuid, p_event text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  if p_event = 'view' then
    update doctor_offers set views = views + 1 where id = p_id and doctor_id <> auth.uid();
  elsif p_event = 'booking' then
    update doctor_offers set bookings = bookings + 1 where id = p_id and doctor_id <> auth.uid();
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Admin announcements
-- ---------------------------------------------------------------------
create or replace function public.admin_save_announcement(
  p_id uuid, p_title text, p_body text default null, p_audience text default 'all',
  p_image_url text default null, p_link_url text default null, p_ends_on date default null, p_active boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_id is null then
    insert into announcements (audience, title, body, image_url, link_url, ends_on, is_active, created_by)
    values (coalesce(p_audience, 'all'), trim(p_title), nullif(trim(p_body), ''), nullif(trim(p_image_url), ''),
            nullif(trim(p_link_url), ''), p_ends_on, coalesce(p_active, true), auth.uid())
    returning id into v_id;
  else
    update announcements set audience = coalesce(p_audience, audience), title = trim(p_title), body = nullif(trim(p_body), ''),
           image_url = nullif(trim(p_image_url), ''), link_url = nullif(trim(p_link_url), ''), ends_on = p_ends_on,
           is_active = coalesce(p_active, is_active)
     where id = p_id returning id into v_id;
  end if;
  perform write_audit('announcement.saved', 'announcements', v_id::text, jsonb_build_object('audience', p_audience));
  return v_id;
end $$;

create or replace function public.admin_delete_announcement(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  delete from announcements where id = p_id;
end $$;

create or replace function public.admin_list_announcements()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'audience', a.audience, 'title', a.title, 'body', a.body, 'image_url', a.image_url,
      'link_url', a.link_url, 'ends_on', a.ends_on, 'is_active', a.is_active, 'created_at', a.created_at,
      'dismissed', (select count(*) from announcement_dismissals x where x.announcement_id = a.id))
      order by a.created_at desc) from announcements a), '[]'::jsonb);
end $$;

-- What the signed-in user should see on their home screen.
create or replace function public.my_announcements()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', a.id, 'title', a.title, 'body', a.body, 'image_url', a.image_url, 'link_url', a.link_url,
      'audience', a.audience, 'created_at', a.created_at) order by a.created_at desc), '[]'::jsonb)
  from announcements a, profiles me
  where me.id = auth.uid()
    and a.is_active
    and (a.ends_on is null or a.ends_on >= (now() at time zone 'Africa/Cairo')::date)
    and (a.audience = 'all'
         or (a.audience = 'doctors' and me.role in ('doctor', 'assistant', 'admin'))
         or (a.audience = 'patients' and me.role in ('patient', 'admin')))
    and not exists (select 1 from announcement_dismissals x where x.announcement_id = a.id and x.user_id = me.id);
$$;

create or replace function public.dismiss_announcement(p_id uuid)
returns void language sql security definer set search_path = public as $$
  insert into announcement_dismissals (announcement_id, user_id)
  select p_id, auth.uid() where auth.uid() is not null and exists (select 1 from announcements where id = p_id)
  on conflict do nothing;
$$;

revoke all on function public.save_offer(uuid, text, text, text, numeric, numeric, text, date, uuid, boolean, uuid),
  public.delete_offer(uuid), public.admin_hide_offer(uuid, boolean),
  public.list_offers(int, int, uuid, boolean, int), public.offer_event(uuid, text),
  public.admin_save_announcement(uuid, text, text, text, text, text, date, boolean), public.admin_delete_announcement(uuid),
  public.admin_list_announcements(), public.my_announcements(), public.dismiss_announcement(uuid)
from public, anon;
grant execute on function public.save_offer(uuid, text, text, text, numeric, numeric, text, date, uuid, boolean, uuid),
  public.delete_offer(uuid), public.admin_hide_offer(uuid, boolean),
  public.list_offers(int, int, uuid, boolean, int), public.offer_event(uuid, text),
  public.admin_save_announcement(uuid, text, text, text, text, text, date, boolean), public.admin_delete_announcement(uuid),
  public.admin_list_announcements(), public.my_announcements(), public.dismiss_announcement(uuid)
to authenticated;

-- =====================================================================
-- دكتوري — 0016: صور العروض والإعلانات (عامة)
-- Public bucket; each user uploads only inside their own folder <uid>/…
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('offers', 'offers', true, 3145728, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "offers: upload own" on storage.objects;
create policy "offers: upload own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'offers' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "offers: read" on storage.objects;
create policy "offers: read"
  on storage.objects for select to authenticated
  using (bucket_id = 'offers');
drop policy if exists "offers: delete own" on storage.objects;
create policy "offers: delete own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'offers' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- =====================================================================
-- دكتوري — 0017: دور الانتظار، المخزن، التقارير، العمليات، الشات، البيانات الطبية الأساسية،
--                 الإشعارات، تقييم الدكتور
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Notifications (written by the features below; read live by the app)
-- ---------------------------------------------------------------------
create table if not exists public.notifications (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (length(kind) <= 40),
  title      text not null check (length(title) <= 200),
  body       text check (body is null or length(body) <= 500),
  ref        jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists idx_notifications_user on public.notifications (user_id, created_at);
alter table public.notifications enable row level security;
drop policy if exists notifications_own on public.notifications;
create policy notifications_own on public.notifications for select using (user_id = auth.uid());
revoke all on public.notifications from anon;
grant select on public.notifications to authenticated;

-- Internal: notify one user.
create or replace function public._notify(p_user uuid, p_kind text, p_title text, p_body text default null,
                                          p_ref jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, title, body, ref)
  select p_user, p_kind, left(p_title, 200), left(p_body, 500), coalesce(p_ref, '{}'::jsonb)
  where p_user is not null and p_user is distinct from auth.uid();
$$;
-- Internal: notify a doctor and their assistants who hold a permission.
create or replace function public._notify_clinic(p_doctor uuid, p_perm text, p_kind text, p_title text,
                                                 p_body text default null, p_ref jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  perform _notify(p_doctor, p_kind, p_title, p_body, p_ref);
  for u in select assistant_id from doctor_assistants
           where doctor_id = p_doctor
             and case p_perm when 'bookings' then can_bookings when 'patients' then can_patients
                             when 'medical' then can_medical when 'finance' then can_finance else false end loop
    perform _notify(u, p_kind, p_title, p_body, p_ref);
  end loop;
end $$;
revoke all on function public._notify(uuid, text, text, text, jsonb), public._notify_clinic(uuid, text, text, text, text, jsonb)
  from public, anon, authenticated;

create or replace function public.my_notifications(p_limit int default 60)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'unread', (select count(*) from notifications where user_id = auth.uid() and read_at is null),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'title', n.title, 'body', n.body,
                                                           'ref', n.ref, 'created_at', n.created_at, 'read', n.read_at is not null)
                                        order by n.created_at desc)
                       from (select * from notifications where user_id = auth.uid()
                             order by created_at desc limit least(coalesce(p_limit, 60), 200)) n), '[]'::jsonb));
$$;

create or replace function public.mark_notifications_read(p_upto bigint default null)
returns void language sql security definer set search_path = public as $$
  update notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_upto is null or id <= p_upto);
$$;

-- Events → notifications
create or replace function public.trg_appointment_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_when text := to_char(new.starts_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM');
        v_doc text; v_pat text;
begin
  select full_name into v_doc from profiles where id = new.doctor_id;
  select full_name into v_pat from profiles where id = new.patient_id;
  if tg_op = 'INSERT' then
    if auth.uid() = new.patient_id then
      perform _notify_clinic(new.doctor_id, 'bookings', 'booking', 'حجز جديد 📅', coalesce(v_pat, '') || ' — ' || v_when,
                             jsonb_build_object('appointment_id', new.id));
    else
      perform _notify(new.patient_id, 'booking', 'اتحجزلك ميعاد 📅', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when,
                      jsonb_build_object('appointment_id', new.id));
    end if;
  elsif new.status is distinct from old.status then
    if new.status = 'confirmed' then
      perform _notify(new.patient_id, 'booking', 'حجزك اتأكد ✓', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when,
                      jsonb_build_object('appointment_id', new.id));
    elsif new.status = 'cancelled' then
      if auth.uid() = new.patient_id then
        perform _notify_clinic(new.doctor_id, 'bookings', 'booking', 'حجز اتلغى', coalesce(v_pat, '') || ' — ' || v_when,
                               jsonb_build_object('appointment_id', new.id));
      else
        perform _notify(new.patient_id, 'booking', 'حجزك اتلغى', 'د. ' || coalesce(v_doc, '') || ' — ' || v_when ||
                        '. ممكن تحجز ميعاد تاني.', jsonb_build_object('appointment_id', new.id));
      end if;
    elsif new.status = 'completed' then
      perform _notify(new.patient_id, 'review', 'ألف سلامة عليك 💙', 'قيّم زيارتك لـد. ' || coalesce(v_doc, ''),
                      jsonb_build_object('doctor_id', new.doctor_id, 'appointment_id', new.id));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists appointments_notify on public.appointments;
drop trigger if exists appointments_notify on public.appointments;
create trigger appointments_notify after insert or update of status on public.appointments
  for each row execute function public.trg_appointment_notify();

create or replace function public.trg_rx_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.patient_id is not null then
    perform _notify(new.patient_id, 'prescription', 'روشتة جديدة 📝',
                    'د. ' || coalesce((select full_name from profiles where id = new.doctor_id), '') || ' كتبلك روشتة',
                    jsonb_build_object('prescription_id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists prescriptions_notify on public.prescriptions;
drop trigger if exists prescriptions_notify on public.prescriptions;
create trigger prescriptions_notify after insert on public.prescriptions for each row execute function public.trg_rx_notify();

create or replace function public.trg_followup_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform _notify(new.patient_id, 'followup', 'ميعاد متابعة 🔁',
                  new.title || ' — ' || to_char(new.scheduled_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM'),
                  jsonb_build_object('followup_id', new.id));
  return new;
end $$;
drop trigger if exists followups_notify on public.followups;
drop trigger if exists followups_notify on public.followups;
create trigger followups_notify after insert on public.followups for each row execute function public.trg_followup_notify();

create or replace function public.trg_med_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.needs_review and new.review_doctor is not null then
    perform _notify_clinic(new.review_doctor, 'medical', 'med_review', 'دوا محتاج تحدد جرعته 💊',
                           coalesce((select full_name from profiles where id = new.patient_id), '') || ' بعت صورة دوا',
                           jsonb_build_object('medication_id', new.id));
  elsif tg_op = 'INSERT' and new.prescribed_by is not null then
    perform _notify(new.patient_id, 'medication', 'علاج جديد من دكتورك 💊', new.name, jsonb_build_object('medication_id', new.id));
  elsif tg_op = 'UPDATE' and old.needs_review and not new.needs_review then
    perform _notify(new.patient_id, 'medication', 'الدكتور حدد جرعة دواك ✓', new.name || coalesce(' — ' || new.dose, ''),
                    jsonb_build_object('medication_id', new.id));
  end if;
  return new;
end $$;
drop trigger if exists medications_notify on public.medications;
drop trigger if exists medications_notify on public.medications;
create trigger medications_notify after insert or update of needs_review on public.medications
  for each row execute function public.trg_med_notify();

create or replace function public.trg_join_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform _notify_clinic(new.doctor_id, 'patients', 'join', 'طلب انضمام جديد 👋',
                           coalesce((select full_name from profiles where id = new.patient_id), ''), '{}'::jsonb);
  elsif new.status is distinct from old.status and new.status in ('accepted', 'rejected') then
    perform _notify(new.patient_id, 'join',
                    case when new.status = 'accepted' then 'الدكتور قبل طلبك ✓' else 'الدكتور اعتذر عن طلبك' end,
                    'د. ' || coalesce((select full_name from profiles where id = new.doctor_id), ''), '{}'::jsonb);
  end if;
  return new;
end $$;
drop trigger if exists join_requests_notify on public.join_requests;
drop trigger if exists join_requests_notify on public.join_requests;
create trigger join_requests_notify after insert or update of status on public.join_requests
  for each row execute function public.trg_join_notify();

-- ---------------------------------------------------------------------
-- 2) Waiting queue (today, per clinic)
-- ---------------------------------------------------------------------
create table if not exists public.clinic_queue (
  id             uuid primary key default gen_random_uuid(),
  clinic_id      uuid not null references public.clinics(id) on delete cascade,
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  day            date not null,
  number         int not null,
  patient_id     uuid references public.patients(id) on delete set null,
  patient_name   text check (patient_name is null or length(patient_name) <= 120),
  appointment_id uuid references public.appointments(id) on delete set null,
  status         text not null default 'waiting' check (status in ('waiting', 'called', 'in_room', 'done', 'skipped')),
  created_at     timestamptz not null default now(),
  called_at      timestamptz,
  done_at        timestamptz,
  unique (clinic_id, day, number)
);
create unique index if not exists clinic_queue_one_per_appt on public.clinic_queue (appointment_id) where appointment_id is not null;
alter table public.clinic_queue enable row level security;
drop policy if exists queue_read on public.clinic_queue;
create policy queue_read on public.clinic_queue for select using (patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings'));
revoke all on public.clinic_queue from anon;
grant select on public.clinic_queue to authenticated;

create or replace function public._queue_add(p_clinic uuid, p_patient uuid, p_name text, p_appt uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date; v_no int; v_id uuid;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  perform pg_advisory_xact_lock(hashtext(p_clinic::text || v_day::text));
  select coalesce(max(number), 0) + 1 into v_no from clinic_queue where clinic_id = p_clinic and day = v_day;
  insert into clinic_queue (clinic_id, doctor_id, day, number, patient_id, patient_name, appointment_id)
  values (p_clinic, v_doc, v_day, v_no, p_patient,
          coalesce(nullif(trim(p_name), ''), (select full_name from profiles where id = p_patient)), p_appt)
  returning id into v_id;
  return v_id;
end $$;
revoke all on function public._queue_add(uuid, uuid, text, uuid) from public, anon, authenticated;

-- Staff: add a walk-in or a booked patient to today's queue.
create or replace function public.queue_add(p_clinic uuid, p_patient uuid default null, p_name text default null,
                                            p_appointment uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_existing uuid;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_appointment is not null then
    select id into v_existing from clinic_queue where appointment_id = p_appointment;
    if v_existing is not null then return v_existing; end if;
    select patient_id into p_patient from appointments where id = p_appointment and doctor_id = v_doc;
  end if;
  if p_patient is null and length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'name is required' using errcode = 'P0001';
  end if;
  return _queue_add(p_clinic, p_patient, p_name, p_appointment);
end $$;

-- Patient: "I arrived" for today's booking.
create or replace function public.queue_checkin(p_appointment uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare a appointments; v_existing uuid;
begin
  select * into a from appointments where id = p_appointment and patient_id = auth.uid();
  if not found or a.status not in ('pending', 'confirmed')
     or (a.starts_at at time zone 'Africa/Cairo')::date <> (now() at time zone 'Africa/Cairo')::date then
    raise exception 'check-in is only for today''s booking' using errcode = 'P0001';
  end if;
  select id into v_existing from clinic_queue where appointment_id = p_appointment;
  if v_existing is not null then return v_existing; end if;
  v_existing := _queue_add(a.clinic_id, a.patient_id, null, a.id);
  perform _notify_clinic(a.doctor_id, 'bookings', 'queue', 'مريض وصل العيادة 🚶',
                         coalesce((select full_name from profiles where id = a.patient_id), ''), '{}'::jsonb);
  return v_existing;
end $$;

create or replace function public.queue_set_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare q clinic_queue;
begin
  select * into q from clinic_queue where id = p_id for update;
  if not found or not acts_for(q.doctor_id, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_status not in ('waiting', 'called', 'in_room', 'done', 'skipped') then
    raise exception 'invalid status' using errcode = 'P0001';
  end if;
  update clinic_queue set status = p_status,
         called_at = case when p_status = 'called' then now() else called_at end,
         done_at = case when p_status in ('done', 'skipped') then now() else done_at end
   where id = p_id;
  if p_status = 'called' and q.patient_id is not null then
    perform _notify(q.patient_id, 'queue', 'دورك جه! 🔔', 'اتفضل ادخل للدكتور — رقمك ' || q.number,
                    jsonb_build_object('queue_id', q.id));
  end if;
  if p_status = 'done' and q.appointment_id is not null then
    update appointments set status = 'completed', updated_by = auth.uid()
     where id = q.appointment_id and status in ('pending', 'confirmed');
  end if;
end $$;

-- Staff: call the next waiting number.
create or replace function public.queue_call_next(p_clinic uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date; q clinic_queue;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  update clinic_queue set status = 'done', done_at = now()
   where clinic_id = p_clinic and day = v_day and status in ('called', 'in_room');
  select * into q from clinic_queue where clinic_id = p_clinic and day = v_day and status = 'waiting'
   order by number limit 1;
  if not found then return null; end if;
  perform queue_set_status(q.id, 'called');
  return jsonb_build_object('id', q.id, 'number', q.number, 'patient_name', q.patient_name);
end $$;

create or replace function public.queue_today(p_clinic uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid; v_day date := (now() at time zone 'Africa/Cairo')::date;
begin
  select doctor_id into v_doc from clinics where id = p_clinic;
  if v_doc is null or not acts_for(v_doc, 'bookings') then raise exception 'not allowed' using errcode = '42501'; end if;
  return jsonb_build_object(
    'minutes', (select appointment_minutes from doctors where id = v_doc),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', q.id, 'number', q.number, 'status', q.status, 'patient_id', q.patient_id, 'patient_name', q.patient_name,
        'patient_phone', p.phone, 'patient_avatar', p.avatar_url, 'appointment_id', q.appointment_id,
        'created_at', q.created_at, 'called_at', q.called_at) order by q.number)
      from clinic_queue q left join profiles p on p.id = q.patient_id
      where q.clinic_id = p_clinic and q.day = v_day), '[]'::jsonb),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'patient_id', a.patient_id, 'patient_name', p.full_name,
        'time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI'), 'status', a.status) order by a.starts_at)
      from appointments a join profiles p on p.id = a.patient_id
      where a.clinic_id = p_clinic and a.status in ('pending', 'confirmed')
        and (a.starts_at at time zone 'Africa/Cairo')::date = v_day
        and not exists (select 1 from clinic_queue q where q.appointment_id = a.id)), '[]'::jsonb));
end $$;

-- Patient: my place in today's queue(s).
create or replace function public.my_queue()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id, 'number', q.number, 'status', q.status, 'clinic_name', c.name, 'doctor_name', dp.full_name,
      'now_serving', (select max(number) from clinic_queue x where x.clinic_id = q.clinic_id and x.day = q.day
                        and x.status in ('called', 'in_room', 'done')),
      'ahead', (select count(*) from clinic_queue x where x.clinic_id = q.clinic_id and x.day = q.day
                  and x.status = 'waiting' and x.number < q.number),
      'minutes', d.appointment_minutes) order by q.created_at), '[]'::jsonb)
  from clinic_queue q
  join clinics c on c.id = q.clinic_id
  join doctors d on d.id = q.doctor_id
  join profiles dp on dp.id = q.doctor_id
  where q.patient_id = auth.uid() and q.day = (now() at time zone 'Africa/Cairo')::date
    and q.status in ('waiting', 'called', 'in_room');
$$;

-- ---------------------------------------------------------------------
-- 3) Inventory
-- ---------------------------------------------------------------------
create table if not exists public.inventory_items (
  id         uuid primary key default gen_random_uuid(),
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 120),
  category   text check (category is null or length(category) <= 60),
  unit       text check (unit is null or length(unit) <= 30),
  qty        numeric(12,2) not null default 0,
  min_qty    numeric(12,2) not null default 0 check (min_qty >= 0),
  unit_cost  numeric(12,2) check (unit_cost is null or unit_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_inventory_doctor on public.inventory_items (doctor_id);
alter table public.inventory_items enable row level security;
drop policy if exists inventory_read on public.inventory_items;
create policy inventory_read on public.inventory_items for select
  using (public.acts_for(doctor_id, 'finance') or public.acts_for(doctor_id, 'bookings'));
revoke all on public.inventory_items from anon;
grant select on public.inventory_items to authenticated;
drop trigger if exists inventory_items_touch on public.inventory_items;
drop trigger if exists inventory_items_touch on public.inventory_items;
create trigger inventory_items_touch before update on public.inventory_items for each row execute function public.touch_updated_at();

create table if not exists public.inventory_moves (
  id         bigserial primary key,
  item_id    uuid not null references public.inventory_items(id) on delete cascade,
  delta      numeric(12,2) not null check (delta <> 0),
  reason     text not null check (reason in ('purchase', 'use', 'adjust', 'expired', 'return')),
  note       text check (note is null or length(note) <= 200),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.inventory_moves enable row level security;
drop policy if exists inventory_moves_read on public.inventory_moves;
create policy inventory_moves_read on public.inventory_moves for select using (
  exists (select 1 from public.inventory_items i where i.id = item_id
          and (public.acts_for(i.doctor_id, 'finance') or public.acts_for(i.doctor_id, 'bookings'))));
revoke all on public.inventory_moves from anon;
grant select on public.inventory_moves to authenticated;

create or replace function public._can_stock(p_doctor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select acts_for(p_doctor, 'finance') or acts_for(p_doctor, 'bookings');
$$;

create or replace function public.save_inventory_item(p_id uuid, p_name text, p_category text default null,
  p_unit text default null, p_min_qty numeric default 0, p_unit_cost numeric default null,
  p_initial_qty numeric default 0, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid;
begin
  if not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into inventory_items (doctor_id, name, category, unit, min_qty, unit_cost, qty)
    values (v_doc, trim(p_name), nullif(trim(p_category), ''), nullif(trim(p_unit), ''), coalesce(p_min_qty, 0), p_unit_cost,
            greatest(coalesce(p_initial_qty, 0), 0))
    returning id into v_id;
    if coalesce(p_initial_qty, 0) > 0 then
      insert into inventory_moves (item_id, delta, reason, note, created_by) values (v_id, p_initial_qty, 'adjust', 'رصيد أول المدة', auth.uid());
    end if;
  else
    update inventory_items set name = trim(p_name), category = nullif(trim(p_category), ''), unit = nullif(trim(p_unit), ''),
           min_qty = coalesce(p_min_qty, 0), unit_cost = p_unit_cost
     where id = p_id and doctor_id = v_doc returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.delete_inventory_item(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  select doctor_id into v_doc from inventory_items where id = p_id;
  if v_doc is null or not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from inventory_items where id = p_id;
end $$;

-- Stock in (+) or out (−). A purchase with a cost can also be recorded as a clinic expense.
create or replace function public.inventory_move(p_item uuid, p_delta numeric, p_reason text, p_note text default null,
                                                 p_cost numeric default null, p_record_expense boolean default false)
returns numeric language plpgsql security definer set search_path = public as $$
declare i inventory_items; v_qty numeric;
begin
  select * into i from inventory_items where id = p_item for update;
  if not found or not _can_stock(i.doctor_id) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'quantity is required' using errcode = 'P0001'; end if;
  if i.qty + p_delta < 0 then raise exception 'not enough stock' using errcode = 'P0001'; end if;
  insert into inventory_moves (item_id, delta, reason, note, created_by) values (p_item, p_delta, p_reason, nullif(trim(p_note), ''), auth.uid());
  update inventory_items set qty = qty + p_delta,
         unit_cost = case when p_reason = 'purchase' and p_cost is not null and p_delta > 0 then round(p_cost / p_delta, 2) else unit_cost end
   where id = p_item returning qty into v_qty;
  if coalesce(p_record_expense, false) and p_reason = 'purchase' and coalesce(p_cost, 0) > 0
     and acts_for(i.doctor_id, 'finance') then
    insert into doctor_expenses (doctor_id, category, amount, spent_on, reason, created_by)
    values (i.doctor_id, 'supplies', p_cost, (now() at time zone 'Africa/Cairo')::date, 'شراء ' || i.name || ' (' || p_delta || ')', auth.uid());
  end if;
  if v_qty <= i.min_qty and i.qty > i.min_qty then
    perform _notify_clinic(i.doctor_id, 'bookings', 'stock', 'صنف قرب يخلص ⚠️', i.name || ' — الباقي ' || v_qty, jsonb_build_object('item_id', i.id));
  end if;
  return v_qty;
end $$;

create or replace function public.list_inventory(p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
begin
  if not _can_stock(v_doc) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', i.id, 'name', i.name, 'category', i.category, 'unit', i.unit, 'qty', i.qty, 'min_qty', i.min_qty,
      'unit_cost', i.unit_cost, 'low', i.qty <= i.min_qty, 'updated_at', i.updated_at,
      'moves', (select coalesce(jsonb_agg(jsonb_build_object('delta', m.delta, 'reason', m.reason, 'note', m.note,
                                                             'at', m.created_at, 'by', p.full_name) order by m.created_at desc), '[]'::jsonb)
                from (select * from inventory_moves where item_id = i.id order by created_at desc limit 15) m
                left join profiles p on p.id = m.created_by))
      order by (i.qty <= i.min_qty) desc, i.name) from inventory_items i where i.doctor_id = v_doc), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 4) Reports
-- ---------------------------------------------------------------------
create or replace function public.doctor_reports(p_from date, p_to date, p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid());
        v_from timestamptz := p_from::timestamp at time zone 'Africa/Cairo';
        v_to timestamptz := (p_to + 1)::timestamp at time zone 'Africa/Cairo';
        v_fin boolean;
begin
  if not (acts_for(v_doc, 'bookings') or acts_for(v_doc, 'finance')) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_fin := acts_for(v_doc, 'finance');
  return jsonb_build_object(
    'appointments', (select jsonb_build_object(
        'total', count(*),
        'completed', count(*) filter (where status = 'completed'),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'no_show', count(*) filter (where status = 'no_show'),
        'pending', count(*) filter (where status in ('pending', 'confirmed')))
      from appointments where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to),
    'by_weekday', (select coalesce(jsonb_object_agg(wd, n), '{}'::jsonb) from (
        select extract(dow from starts_at at time zone 'Africa/Cairo')::int wd, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status <> 'cancelled' group by 1) x),
    'by_hour', (select coalesce(jsonb_object_agg(h, n), '{}'::jsonb) from (
        select extract(hour from starts_at at time zone 'Africa/Cairo')::int h, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status <> 'cancelled' group by 1) x),
    'by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'visits', n) order by d), '[]'::jsonb) from (
        select (starts_at at time zone 'Africa/Cairo')::date d, count(*) n from appointments
        where doctor_id = v_doc and starts_at >= v_from and starts_at < v_to and status in ('completed', 'confirmed', 'pending')
        group by 1) x),
    'new_patients', (select count(*) from care_links where doctor_id = v_doc and started_at >= v_from and started_at < v_to),
    'active_patients', (select count(*) from care_links where doctor_id = v_doc and status = 'active'),
    'prescriptions', (select count(*) from prescriptions where doctor_id = v_doc and created_at >= v_from and created_at < v_to),
    'followups', (select count(*) from followups where doctor_id = v_doc and scheduled_at >= v_from and scheduled_at < v_to),
    'surgeries', (select count(*) from surgeries where doctor_id = v_doc and scheduled_at >= v_from and scheduled_at < v_to),
    'rating', (select jsonb_build_object('avg', rating_avg, 'count', rating_count) from doctors where id = v_doc),
    'finance', case when v_fin then jsonb_build_object(
        'income', (select coalesce(sum(amount), 0) from doctor_income where doctor_id = v_doc and paid_on between p_from and p_to),
        'expenses', (select coalesce(sum(amount), 0) from doctor_expenses where doctor_id = v_doc and spent_on between p_from and p_to),
        'top_services', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'count', n, 'amount', s) order by s desc), '[]'::jsonb)
                         from (select kind, count(*) n, sum(amount) s from doctor_income
                               where doctor_id = v_doc and paid_on between p_from and p_to group by kind) k),
        'by_month', (select coalesce(jsonb_agg(jsonb_build_object('month', m, 'income', i, 'expenses', e) order by m), '[]'::jsonb) from (
              select m, sum(i) i, sum(e) e from (
                select to_char(paid_on, 'YYYY-MM') m, amount i, 0 e from doctor_income where doctor_id = v_doc and paid_on between p_from and p_to
                union all
                select to_char(spent_on, 'YYYY-MM'), 0, amount from doctor_expenses where doctor_id = v_doc and spent_on between p_from and p_to) u
              group by m) y)) end,
    'offers', (select coalesce(jsonb_agg(jsonb_build_object('title', title, 'views', views, 'bookings', bookings) order by views desc), '[]'::jsonb)
               from (select * from doctor_offers where doctor_id = v_doc order by views desc limit 5) o));
end $$;

-- ---------------------------------------------------------------------
-- 5) Surgeries
-- ---------------------------------------------------------------------
create table if not exists public.surgeries (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients(id) on delete cascade,
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  name         text not null check (length(trim(name)) between 2 and 150),
  place        text check (place is null or length(place) <= 150),
  scheduled_at timestamptz,
  status       text not null default 'planned' check (status in ('planned', 'preparing', 'done', 'recovery', 'closed', 'cancelled')),
  prep         jsonb not null default '[]'::jsonb check (jsonb_typeof(prep) = 'array'),
  post         jsonb not null default '[]'::jsonb check (jsonb_typeof(post) = 'array'),
  notes        text check (notes is null or length(notes) <= 2000),
  fee          numeric(12,2) check (fee is null or fee >= 0),
  created_by   uuid references public.profiles(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists idx_surgeries_doctor on public.surgeries (doctor_id, scheduled_at);
create index if not exists idx_surgeries_patient on public.surgeries (patient_id);
alter table public.surgeries enable row level security;
drop policy if exists surgeries_read on public.surgeries;
create policy surgeries_read on public.surgeries for select using (public.can_view_medical(patient_id, doctor_id));
revoke all on public.surgeries from anon;
grant select on public.surgeries to authenticated;
drop trigger if exists surgeries_touch on public.surgeries;
drop trigger if exists surgeries_touch on public.surgeries;
create trigger surgeries_touch before update on public.surgeries for each row execute function public.touch_updated_at();

create or replace function public.save_surgery(p_id uuid, p_patient uuid, p_name text, p_scheduled_at timestamptz default null,
  p_place text default null, p_status text default 'planned', p_prep jsonb default '[]'::jsonb, p_post jsonb default '[]'::jsonb,
  p_notes text default null, p_fee numeric default null, p_doctor uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doc uuid := coalesce(p_doctor, auth.uid()); v_id uuid; v_old text;
begin
  if not acts_for(v_doc, 'medical') or not has_active_link(p_patient, v_doc) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into surgeries (patient_id, doctor_id, name, place, scheduled_at, status, prep, post, notes, fee, created_by)
    values (p_patient, v_doc, trim(p_name), nullif(trim(p_place), ''), p_scheduled_at, coalesce(p_status, 'planned'),
            coalesce(p_prep, '[]'::jsonb), coalesce(p_post, '[]'::jsonb), nullif(trim(p_notes), ''), p_fee, auth.uid())
    returning id into v_id;
    perform _notify(p_patient, 'surgery', 'تجهيز للعملية 🏥',
                    trim(p_name) || coalesce(' — ' || to_char(p_scheduled_at at time zone 'Africa/Cairo', 'YYYY/MM/DD HH12:MI AM'), ''),
                    jsonb_build_object('surgery_id', v_id));
  else
    select status into v_old from surgeries where id = p_id and doctor_id = v_doc and patient_id = p_patient;
    update surgeries set name = trim(p_name), place = nullif(trim(p_place), ''), scheduled_at = p_scheduled_at,
           status = coalesce(p_status, status), prep = coalesce(p_prep, prep), post = coalesce(p_post, post),
           notes = nullif(trim(p_notes), ''), fee = p_fee
     where id = p_id and doctor_id = v_doc and patient_id = p_patient returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
    if v_old is distinct from p_status then
      perform _notify(p_patient, 'surgery', 'تحديث عن عمليتك', trim(p_name), jsonb_build_object('surgery_id', v_id));
    end if;
  end if;
  return v_id;
end $$;

create or replace function public.list_surgeries(p_patient uuid default null, p_doctor uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', s.id, 'patient_id', s.patient_id, 'patient_name', pp.full_name, 'doctor_id', s.doctor_id, 'doctor_name', dp.full_name,
      'name', s.name, 'place', s.place, 'scheduled_at', s.scheduled_at, 'status', s.status, 'prep', s.prep, 'post', s.post,
      'notes', s.notes, 'fee', case when acts_for(s.doctor_id, 'medical') then s.fee end, 'updated_at', s.updated_at)
      order by s.scheduled_at desc nulls first), '[]'::jsonb)
  from surgeries s join profiles pp on pp.id = s.patient_id join profiles dp on dp.id = s.doctor_id
  where (p_patient is null or s.patient_id = p_patient)
    and (p_doctor is null or s.doctor_id = p_doctor)
    and (p_patient is not null or p_doctor is not null or s.patient_id = auth.uid())
    and can_view_medical(s.patient_id, s.doctor_id);
$$;

-- ---------------------------------------------------------------------
-- 6) Chat between a patient and a clinic
-- ---------------------------------------------------------------------
create table if not exists public.messages (
  id         bigserial primary key,
  patient_id uuid not null references public.patients(id) on delete cascade,
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  sender_id  uuid references public.profiles(id) on delete set null,
  from_patient boolean not null,
  body       text not null check (length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);
create index if not exists idx_messages_thread on public.messages (doctor_id, patient_id, id);
alter table public.messages enable row level security;
drop policy if exists messages_read on public.messages;
create policy messages_read on public.messages for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'patients') or public.acts_for(doctor_id, 'bookings'));
revoke all on public.messages from anon;
grant select on public.messages to authenticated;

create or replace function public._can_chat_staff(p_doctor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select acts_for(p_doctor, 'patients') or acts_for(p_doctor, 'bookings');
$$;

create or replace function public.send_message(p_doctor uuid, p_body text, p_patient uuid default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_patient uuid; v_from_patient boolean; v_id bigint; v_name text;
begin
  if p_patient is null or p_patient = auth.uid() then
    v_patient := auth.uid(); v_from_patient := true;
    if not exists (select 1 from care_links where patient_id = v_patient and doctor_id = p_doctor and status = 'active')
       and not exists (select 1 from appointments where patient_id = v_patient and doctor_id = p_doctor) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  else
    v_patient := p_patient; v_from_patient := false;
    if not _can_chat_staff(p_doctor)
       or (not exists (select 1 from care_links where patient_id = v_patient and doctor_id = p_doctor)
           and not exists (select 1 from appointments where patient_id = v_patient and doctor_id = p_doctor)) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  end if;
  if (select count(*) from messages where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'too many messages' using errcode = 'P0001';
  end if;
  insert into messages (patient_id, doctor_id, sender_id, from_patient, body)
  values (v_patient, p_doctor, auth.uid(), v_from_patient, trim(p_body)) returning id into v_id;
  select full_name into v_name from profiles where id = auth.uid();
  if v_from_patient then
    perform _notify_clinic(p_doctor, 'patients', 'chat', 'رسالة من ' || coalesce(v_name, ''), left(trim(p_body), 140),
                           jsonb_build_object('patient_id', v_patient, 'doctor_id', p_doctor));
  else
    perform _notify(v_patient, 'chat', 'رسالة من العيادة 💬', left(trim(p_body), 140),
                    jsonb_build_object('patient_id', v_patient, 'doctor_id', p_doctor));
  end if;
  return v_id;
end $$;

create or replace function public.chat_messages(p_doctor uuid, p_patient uuid default null, p_before bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_patient uuid := coalesce(p_patient, auth.uid()); v_staff boolean;
begin
  v_staff := v_patient <> auth.uid();
  if v_staff and not _can_chat_staff(p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  update messages set read_at = now()
   where doctor_id = p_doctor and patient_id = v_patient and read_at is null and from_patient = v_staff;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'body', m.body, 'from_patient', m.from_patient,
                                                       'sender', p.full_name, 'created_at', m.created_at, 'read', m.read_at is not null)
                                    order by m.id)
                   from (select * from messages where doctor_id = p_doctor and patient_id = v_patient
                           and (p_before is null or id < p_before) order by id desc limit 80) m
                   left join profiles p on p.id = m.sender_id), '[]'::jsonb);
end $$;

-- Conversations list: for a patient (their clinics) or for clinic staff (their patients).
create or replace function public.chat_threads(p_doctor uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if p_doctor is null then
    return coalesce((select jsonb_agg(t.j order by t.last_at desc nulls last) from (
      select max(m.created_at) last_at, jsonb_build_object(
        'doctor_id', d.id, 'name', dp.full_name, 'avatar_url', dp.avatar_url,
        'last', (select body from messages x where x.doctor_id = d.id and x.patient_id = auth.uid() order by id desc limit 1),
        'last_at', max(m.created_at),
        'unread', count(m.id) filter (where not m.from_patient and m.read_at is null)) j
      from doctors d join profiles dp on dp.id = d.id
      left join messages m on m.doctor_id = d.id and m.patient_id = auth.uid()
      where exists (select 1 from care_links l where l.doctor_id = d.id and l.patient_id = auth.uid() and l.status = 'active')
         or exists (select 1 from messages x where x.doctor_id = d.id and x.patient_id = auth.uid())
      group by d.id, dp.full_name, dp.avatar_url) t), '[]'::jsonb);
  end if;
  if not _can_chat_staff(p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(t.j order by t.last_at desc) from (
    select max(m.created_at) last_at, jsonb_build_object(
      'patient_id', m.patient_id, 'name', pp.full_name, 'avatar_url', pp.avatar_url, 'phone', pp.phone,
      'last', (select body from messages x where x.doctor_id = p_doctor and x.patient_id = m.patient_id order by id desc limit 1),
      'last_at', max(m.created_at),
      'unread', count(*) filter (where m.from_patient and m.read_at is null)) j
    from messages m join profiles pp on pp.id = m.patient_id
    where m.doctor_id = p_doctor
    group by m.patient_id, pp.full_name, pp.avatar_url, pp.phone) t), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- 7) Basic health profile
-- ---------------------------------------------------------------------
create table if not exists public.patient_health (
  patient_id     uuid primary key references public.patients(id) on delete cascade,
  blood_type     text check (blood_type is null or blood_type in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  allergies      text[] not null default '{}',
  chronic        text[] not null default '{}',
  medications    text check (medications is null or length(medications) <= 1000),
  past_surgeries text check (past_surgeries is null or length(past_surgeries) <= 1000),
  family_history text check (family_history is null or length(family_history) <= 1000),
  smoker         boolean,
  pregnant       boolean,
  height_cm      numeric(5,1) check (height_cm is null or height_cm between 30 and 260),
  weight_kg      numeric(5,1) check (weight_kg is null or weight_kg between 1 and 400),
  emergency_name  text check (emergency_name is null or length(emergency_name) <= 120),
  emergency_phone text check (emergency_phone is null or length(emergency_phone) <= 30),
  updated_by     uuid references public.profiles(id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table public.patient_health enable row level security;
drop policy if exists health_read on public.patient_health;
create policy health_read on public.patient_health for select using (
  patient_id = auth.uid() or exists (select 1 from public.care_links l where l.patient_id = patient_health.patient_id
                                     and l.status = 'active' and public.acts_for(l.doctor_id, 'medical')));
revoke all on public.patient_health from anon;
grant select on public.patient_health to authenticated;

create or replace function public._can_health(p_patient uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() = p_patient or exists (select 1 from care_links l where l.patient_id = p_patient
                                            and l.status = 'active' and acts_for(l.doctor_id, 'medical'));
$$;

create or replace function public.get_health(p_patient uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := coalesce(p_patient, auth.uid()); r jsonb;
begin
  if not _can_health(v) then raise exception 'not allowed' using errcode = '42501'; end if;
  select to_jsonb(h) - 'patient_id' || jsonb_build_object('updated_by_name', p.full_name,
         'birth_date', pr.birth_date, 'gender', pr.gender) into r
    from patient_health h left join profiles p on p.id = h.updated_by join profiles pr on pr.id = h.patient_id
   where h.patient_id = v;
  if r is null then
    select jsonb_build_object('birth_date', birth_date, 'gender', gender, 'allergies', '[]'::jsonb, 'chronic', '[]'::jsonb, 'empty', true)
      into r from profiles where id = v;
  end if;
  return r;
end $$;

create or replace function public.save_health(p_patient uuid, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := coalesce(p_patient, auth.uid());
begin
  if not _can_health(v) then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into patient_health (patient_id, blood_type, allergies, chronic, medications, past_surgeries, family_history,
                              smoker, pregnant, height_cm, weight_kg, emergency_name, emergency_phone, updated_by, updated_at)
  values (v, nullif(p_data->>'blood_type', ''),
          coalesce((select array_agg(left(trim(x), 80)) from jsonb_array_elements_text(coalesce(p_data->'allergies', '[]')) x where trim(x) <> ''), '{}'),
          coalesce((select array_agg(left(trim(x), 80)) from jsonb_array_elements_text(coalesce(p_data->'chronic', '[]')) x where trim(x) <> ''), '{}'),
          nullif(trim(p_data->>'medications'), ''), nullif(trim(p_data->>'past_surgeries'), ''),
          nullif(trim(p_data->>'family_history'), ''), (p_data->>'smoker')::boolean, (p_data->>'pregnant')::boolean,
          nullif(p_data->>'height_cm', '')::numeric, nullif(p_data->>'weight_kg', '')::numeric,
          nullif(trim(p_data->>'emergency_name'), ''), nullif(trim(p_data->>'emergency_phone'), ''), auth.uid(), now())
  on conflict (patient_id) do update set
    blood_type = excluded.blood_type, allergies = excluded.allergies, chronic = excluded.chronic,
    medications = excluded.medications, past_surgeries = excluded.past_surgeries, family_history = excluded.family_history,
    smoker = excluded.smoker, pregnant = excluded.pregnant, height_cm = excluded.height_cm, weight_kg = excluded.weight_kg,
    emergency_name = excluded.emergency_name, emergency_phone = excluded.emergency_phone,
    updated_by = auth.uid(), updated_at = now();
end $$;

-- ---------------------------------------------------------------------
-- 8) Doctor reviews
-- ---------------------------------------------------------------------
create table if not exists public.doctor_reviews (
  id         uuid primary key default gen_random_uuid(),
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  patient_id uuid not null references public.patients(id) on delete cascade,
  stars      smallint not null check (stars between 1 and 5),
  comment    text check (comment is null or length(comment) <= 600),
  hidden     boolean not null default false,
  reply      text check (reply is null or length(reply) <= 600),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (doctor_id, patient_id)
);
alter table public.doctor_reviews enable row level security;
drop policy if exists reviews_read on public.doctor_reviews;
create policy reviews_read on public.doctor_reviews for select using (not hidden or patient_id = auth.uid()
  or public.acts_for(doctor_id, 'any') or public.is_admin());
revoke all on public.doctor_reviews from anon;
grant select on public.doctor_reviews to authenticated;

create or replace function public._refresh_rating(p_doctor uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('doctori.trusted_verify', '1', true);
  update doctors set
    rating_avg = coalesce((select round(avg(stars)::numeric, 2) from doctor_reviews where doctor_id = p_doctor and not hidden), 0),
    rating_count = (select count(*) from doctor_reviews where doctor_id = p_doctor and not hidden)
  where id = p_doctor;
  perform set_config('doctori.trusted_verify', '', true);
end $$;
revoke all on function public._refresh_rating(uuid) from public, anon, authenticated;

create or replace function public.submit_review(p_doctor uuid, p_stars int, p_comment text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from appointments where doctor_id = p_doctor and patient_id = auth.uid() and status = 'completed')
     and not exists (select 1 from care_links where doctor_id = p_doctor and patient_id = auth.uid()) then
    raise exception 'only patients of this doctor can review' using errcode = '42501';
  end if;
  insert into doctor_reviews (doctor_id, patient_id, stars, comment)
  values (p_doctor, auth.uid(), p_stars, nullif(trim(p_comment), ''))
  on conflict (doctor_id, patient_id) do update set stars = excluded.stars, comment = excluded.comment, updated_at = now();
  perform _refresh_rating(p_doctor);
  perform _notify(p_doctor, 'review', 'تقييم جديد ⭐ ' || p_stars, left(coalesce(trim(p_comment), ''), 140), '{}'::jsonb);
end $$;

create or replace function public.reply_review(p_id uuid, p_reply text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update doctor_reviews set reply = nullif(trim(p_reply), '') where id = p_id and doctor_id = auth.uid();
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $$;

create or replace function public.admin_hide_review(p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_doc uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  update doctor_reviews set hidden = coalesce(p_hidden, true) where id = p_id returning doctor_id into v_doc;
  if v_doc is not null then perform _refresh_rating(v_doc); end if;
end $$;

create or replace function public.doctor_reviews_list(p_doctor uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'avg', (select rating_avg from doctors where id = p_doctor),
    'count', (select rating_count from doctors where id = p_doctor),
    'mine', (select jsonb_build_object('stars', stars, 'comment', comment) from doctor_reviews
             where doctor_id = p_doctor and patient_id = auth.uid()),
    'can_review', exists (select 1 from appointments where doctor_id = p_doctor and patient_id = auth.uid() and status = 'completed')
                  or exists (select 1 from care_links where doctor_id = p_doctor and patient_id = auth.uid()),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', r.id, 'stars', r.stars, 'comment', r.comment, 'reply', r.reply, 'created_at', r.created_at, 'hidden', r.hidden,
        'name', case when acts_for(p_doctor, 'any') or is_admin() then p.full_name
                     else split_part(p.full_name, ' ', 1) end) order by r.created_at desc)
      from (select * from doctor_reviews where doctor_id = p_doctor
              and (not hidden or acts_for(p_doctor, 'any') or is_admin()) order by created_at desc limit 100) r
      join profiles p on p.id = r.patient_id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------
-- Live updates for the app (Supabase Realtime) where available
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.clinic_queue; exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------
revoke all on function public.my_notifications(int), public.mark_notifications_read(bigint),
  public.queue_add(uuid, uuid, text, uuid), public.queue_checkin(uuid), public.queue_set_status(uuid, text),
  public.queue_call_next(uuid), public.queue_today(uuid), public.my_queue(),
  public._can_stock(uuid), public.save_inventory_item(uuid, text, text, text, numeric, numeric, numeric, uuid),
  public.delete_inventory_item(uuid), public.inventory_move(uuid, numeric, text, text, numeric, boolean), public.list_inventory(uuid),
  public.doctor_reports(date, date, uuid),
  public.save_surgery(uuid, uuid, text, timestamptz, text, text, jsonb, jsonb, text, numeric, uuid), public.list_surgeries(uuid, uuid),
  public._can_chat_staff(uuid), public.send_message(uuid, text, uuid), public.chat_messages(uuid, uuid, bigint), public.chat_threads(uuid),
  public._can_health(uuid), public.get_health(uuid), public.save_health(uuid, jsonb),
  public.submit_review(uuid, int, text), public.reply_review(uuid, text), public.admin_hide_review(uuid, boolean),
  public.doctor_reviews_list(uuid)
from public, anon;
grant execute on function public.my_notifications(int), public.mark_notifications_read(bigint),
  public.queue_add(uuid, uuid, text, uuid), public.queue_checkin(uuid), public.queue_set_status(uuid, text),
  public.queue_call_next(uuid), public.queue_today(uuid), public.my_queue(),
  public._can_stock(uuid), public.save_inventory_item(uuid, text, text, text, numeric, numeric, numeric, uuid),
  public.delete_inventory_item(uuid), public.inventory_move(uuid, numeric, text, text, numeric, boolean), public.list_inventory(uuid),
  public.doctor_reports(date, date, uuid),
  public.save_surgery(uuid, uuid, text, timestamptz, text, text, jsonb, jsonb, text, numeric, uuid), public.list_surgeries(uuid, uuid),
  public._can_chat_staff(uuid), public.send_message(uuid, text, uuid), public.chat_messages(uuid, uuid, bigint), public.chat_threads(uuid),
  public._can_health(uuid), public.get_health(uuid), public.save_health(uuid, jsonb),
  public.submit_review(uuid, int, text), public.reply_review(uuid, text), public.admin_hide_review(uuid, boolean),
  public.doctor_reviews_list(uuid)
to authenticated;

-- =====================================================================
-- دكتوري — 0018: المراكز الطبية (عيادة فيها أكتر من دكتور وأكتر من تخصص)
-- * centers: the place (name, address, location, logo) with an owner (a doctor, or a manager account).
-- * center_members: owner / manager / reception staff and the doctors working there.
--   Each doctor has a share % of income (optionally per service kind); the rest is the center's.
-- * Each doctor gets a clinic row at the center (clinics.center_id) → bookings, hours and queue work as usual,
--   and center staff can run them for every doctor in the center.
-- * Income recorded at the center is the doctor's income row tagged with center_id; center expenses are separate.
--   Reports: per doctor (income, doctor share, center share, cases) and the center total net.
-- =====================================================================

create table if not exists public.centers (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (length(trim(name)) between 2 and 120),
  owner_id       uuid not null references public.profiles(id) on delete restrict,
  phone          text check (phone is null or length(phone) <= 30),
  address        text check (address is null or length(address) <= 300),
  governorate_id int references public.governorates(id),
  city_id        int references public.cities(id),
  area           text check (area is null or length(area) <= 120),
  lat            double precision check (lat is null or lat between -90 and 90),
  lng            double precision check (lng is null or lng between -180 and 180),
  logo_url       text check (logo_url is null or length(logo_url) <= 500),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
drop trigger if exists centers_touch on public.centers;
drop trigger if exists centers_touch on public.centers;
create trigger centers_touch before update on public.centers for each row execute function public.touch_updated_at();

create table if not exists public.center_members (
  center_id     uuid not null references public.centers(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  role          text not null check (role in ('owner', 'manager', 'reception', 'doctor')),
  status        text not null default 'active' check (status in ('invited', 'active', 'left')),
  share_percent numeric(5,2) check (share_percent is null or share_percent between 0 and 100),
  share_by_kind jsonb not null default '{}'::jsonb check (jsonb_typeof(share_by_kind) = 'object'),
  can_finance   boolean not null default false,
  clinic_id     uuid references public.clinics(id) on delete set null,
  invited_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  primary key (center_id, user_id, role)
);
create index if not exists idx_center_members_user on public.center_members (user_id);

alter table public.clinics add column if not exists center_id uuid references public.centers(id) on delete set null;
alter table public.doctor_income add column if not exists center_id uuid references public.centers(id) on delete set null;
create index if not exists idx_doctor_income_center on public.doctor_income (center_id, paid_on);

create table if not exists public.center_expenses (
  id         uuid primary key default gen_random_uuid(),
  center_id  uuid not null references public.centers(id) on delete cascade,
  category   text not null check (category in ('rent', 'salaries', 'supplies', 'utilities', 'equipment',
                                               'maintenance', 'lab', 'marketing', 'transport', 'other')),
  amount     numeric(12,2) not null check (amount > 0 and amount < 10000000),
  spent_on   date not null,
  reason     text check (reason is null or length(reason) <= 300),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_center_expenses_day on public.center_expenses (center_id, spent_on);

-- ---------------------------------------------------------------------
-- Who may do what
-- ---------------------------------------------------------------------
-- Staff of a center: owner/manager always; reception per flags. p_need: 'staff' | 'finance' | 'admin'
create or replace function public.center_can(p_center uuid, p_need text default 'staff') returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or exists (
    select 1 from center_members m join profiles p on p.id = m.user_id
    where m.center_id = p_center and m.user_id = auth.uid() and m.status = 'active' and not p.is_suspended
      and m.role in ('owner', 'manager', 'reception')
      and case p_need
            when 'staff' then true
            when 'finance' then m.role in ('owner', 'manager') or m.can_finance
            when 'admin' then m.role in ('owner', 'manager')
            when 'owner' then m.role = 'owner'
            else false end);
$$;

-- Center staff run bookings, patients and new patient accounts for every doctor working in their center.
create or replace function public.acts_for(p_doctor uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select (auth.uid() = p_doctor and exists (select 1 from profiles p where p.id = p_doctor and not p.is_suspended))
      or exists (
        select 1 from doctor_assistants a join profiles p on p.id = a.assistant_id
        where a.doctor_id = p_doctor and a.assistant_id = auth.uid() and not p.is_suspended
          and case p_perm
                when 'bookings' then a.can_bookings
                when 'patients' then a.can_patients
                when 'add_patients' then a.can_add_patients
                when 'medical' then a.can_medical
                when 'finance' then a.can_finance
                when 'any' then true
                else false end)
      or (p_perm in ('bookings', 'patients', 'add_patients', 'any') and exists (
        select 1 from center_members s
        join center_members d on d.center_id = s.center_id and d.user_id = p_doctor and d.role = 'doctor' and d.status = 'active'
        join profiles sp on sp.id = s.user_id and not sp.is_suspended
        join centers c on c.id = s.center_id and c.is_active
        where s.user_id = auth.uid() and s.status = 'active' and s.role in ('owner', 'manager', 'reception')));
$$;

alter table public.centers enable row level security;
alter table public.center_members enable row level security;
alter table public.center_expenses enable row level security;
drop policy if exists centers_read on public.centers;
create policy centers_read on public.centers for select using (true);
drop policy if exists center_members_read on public.center_members;
create policy center_members_read on public.center_members for select using (user_id = auth.uid() or public.center_can(center_id));
drop policy if exists center_expenses_read on public.center_expenses;
create policy center_expenses_read on public.center_expenses for select using (public.center_can(center_id, 'finance'));
revoke all on public.centers, public.center_members, public.center_expenses from anon;
grant select on public.centers, public.center_members, public.center_expenses to authenticated;

-- Staff manage the hours of the doctors' center clinics.
drop policy if exists hours_center_write on public.clinic_hours;
drop policy if exists hours_center_write on public.clinic_hours;
create policy hours_center_write on public.clinic_hours for all
  using (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.center_id is not null
                 and public.center_can(c.center_id, 'admin')))
  with check (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.center_id is not null
                      and public.center_can(c.center_id, 'admin')));

-- ---------------------------------------------------------------------
-- Creating a center and its people
-- ---------------------------------------------------------------------
create or replace function public._center_doctor_clinic(p_center uuid, p_doctor uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare c centers; v_id uuid;
begin
  select * into c from centers where id = p_center;
  select id into v_id from clinics where doctor_id = p_doctor and center_id = p_center limit 1;
  if v_id is null then
    insert into clinics (doctor_id, name, address, governorate_id, city_id, area, lat, lng, phone, center_id)
    values (p_doctor, c.name, coalesce(c.address, c.name), c.governorate_id, c.city_id, c.area, c.lat, c.lng, c.phone, p_center)
    returning id into v_id;
  else
    update clinics set is_active = true where id = v_id;
  end if;
  update center_members set clinic_id = v_id where center_id = p_center and user_id = p_doctor and role = 'doctor';
  return v_id;
end $$;

-- A verified doctor opens a center (and works in it). The admin can open one for any account.
create or replace function public.create_center(p_name text, p_phone text default null, p_address text default null,
  p_governorate int default null, p_city int default null, p_area text default null,
  p_lat double precision default null, p_lng double precision default null, p_owner uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_owner uuid := coalesce(p_owner, auth.uid()); v_id uuid; v_is_doc boolean;
begin
  if p_owner is not null and p_owner <> auth.uid() and not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  v_is_doc := exists (select 1 from doctors where id = v_owner and status = 'verified');
  if not is_admin() and not v_is_doc then raise exception 'doctor account is not active' using errcode = '42501'; end if;
  if not is_admin() and (select count(*) from centers where owner_id = v_owner) >= 3 then
    raise exception 'center limit reached' using errcode = 'P0001';
  end if;
  insert into centers (name, owner_id, phone, address, governorate_id, city_id, area, lat, lng)
  values (trim(p_name), v_owner, nullif(trim(p_phone), ''), nullif(trim(p_address), ''), p_governorate, p_city,
          nullif(trim(p_area), ''), p_lat, p_lng)
  returning id into v_id;
  insert into center_members (center_id, user_id, role, invited_by) values (v_id, v_owner, 'owner', auth.uid());
  if v_is_doc then
    insert into center_members (center_id, user_id, role, share_percent, invited_by) values (v_id, v_owner, 'doctor', 100, auth.uid());
    perform _center_doctor_clinic(v_id, v_owner);
  end if;
  perform write_audit('center.created', 'centers', v_id::text, jsonb_build_object('owner', v_owner));
  return v_id;
end $$;

-- Admin: a center whose owner is not a doctor — creates the manager's phone login.
create or replace function public.admin_create_center(p_name text, p_owner_name text, p_owner_phone text, p_password text,
  p_address text default null, p_governorate int default null, p_city int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text; v_user uuid; v_center uuid;
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  v_phone := normalize_eg_phone(p_owner_phone);
  v_user := _create_auth_user(phone_login_email(v_phone), p_password,
              jsonb_build_object('full_name', trim(p_owner_name), 'role', 'patient', 'locale', 'ar'));
  perform set_config('doctori.trusted', '1', true);
  update profiles set role = 'assistant', phone = v_phone, login_kind = 'phone', created_by = auth.uid() where id = v_user;
  perform set_config('doctori.trusted', '', true);
  delete from patients where id = v_user;
  v_center := create_center(p_name, v_phone, p_address, p_governorate, p_city, null, null, null, v_user);
  return jsonb_build_object('center_id', v_center, 'user_id', v_user, 'phone', v_phone);
end $$;

create or replace function public.update_center(p_center uuid, p_name text, p_phone text, p_address text,
  p_governorate int default null, p_city int default null, p_area text default null,
  p_lat double precision default null, p_lng double precision default null, p_logo_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update centers set name = trim(p_name), phone = nullif(trim(p_phone), ''), address = nullif(trim(p_address), ''),
         governorate_id = p_governorate, city_id = p_city, area = nullif(trim(p_area), ''), lat = p_lat, lng = p_lng,
         logo_url = nullif(trim(p_logo_url), '')
   where id = p_center;
  update clinics set name = trim(p_name), address = coalesce(nullif(trim(p_address), ''), trim(p_name)),
         governorate_id = p_governorate, city_id = p_city, area = nullif(trim(p_area), ''), lat = p_lat, lng = p_lng,
         phone = nullif(trim(p_phone), '')
   where center_id = p_center;
end $$;

-- Invite a doctor by mobile or email (they accept from their app), with their share of income.
create or replace function public.center_invite_doctor(p_center uuid, p_login text, p_share numeric default 50)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_doc uuid; v_login text := lower(trim(coalesce(p_login, ''))); v_phone text;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  if v_login like '%@%' then
    select p.id into v_doc from profiles p join doctors d on d.id = p.id where lower(p.email) = v_login;
  else
    begin v_phone := normalize_eg_phone(v_login); exception when others then v_phone := null; end;
    select p.id into v_doc from profiles p join doctors d on d.id = p.id
     where v_phone is not null and (p.phone = v_phone or lower(p.email) = 'p' || v_phone || '@phone.doctori.app') limit 1;
  end if;
  if v_doc is null then raise exception 'doctor not found' using errcode = 'P0001'; end if;
  insert into center_members (center_id, user_id, role, status, share_percent, invited_by)
  values (p_center, v_doc, 'doctor', 'invited', coalesce(p_share, 50), auth.uid())
  on conflict (center_id, user_id, role) do update
    set status = case when center_members.status = 'active' then 'active' else 'invited' end,
        share_percent = excluded.share_percent;
  perform _notify(v_doc, 'center', 'دعوة للانضمام لمركز طبي 🏥',
                  (select name from centers where id = p_center) || ' — نسبتك ' || coalesce(p_share, 50) || '٪',
                  jsonb_build_object('center_id', p_center));
  return jsonb_build_object('doctor_id', v_doc, 'name', (select full_name from profiles where id = v_doc));
end $$;

create or replace function public.center_respond_invite(p_center uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from center_members where center_id = p_center and user_id = auth.uid()
                 and role = 'doctor' and status = 'invited') then
    raise exception 'no invitation' using errcode = 'P0001';
  end if;
  if p_accept then
    update center_members set status = 'active' where center_id = p_center and user_id = auth.uid() and role = 'doctor';
    perform _center_doctor_clinic(p_center, auth.uid());
  else
    delete from center_members where center_id = p_center and user_id = auth.uid() and role = 'doctor';
  end if;
  perform _notify((select owner_id from centers where id = p_center), 'center',
                  case when p_accept then 'دكتور انضم للمركز ✓' else 'دكتور اعتذر عن الانضمام' end,
                  (select full_name from profiles where id = auth.uid()), jsonb_build_object('center_id', p_center));
end $$;

create or replace function public.center_set_share(p_center uuid, p_doctor uuid, p_share numeric, p_by_kind jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update center_members set share_percent = p_share, share_by_kind = coalesce(p_by_kind, '{}'::jsonb)
   where center_id = p_center and user_id = p_doctor and role = 'doctor';
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('center.share_changed', 'centers', p_center::text, jsonb_build_object('doctor', p_doctor, 'share', p_share));
end $$;

-- Owner removes a doctor (or a doctor leaves): their center clinic stops taking bookings.
create or replace function public.center_remove_doctor(p_center uuid, p_doctor uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (center_can(p_center, 'admin') or auth.uid() = p_doctor) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_doctor = (select owner_id from centers where id = p_center) and auth.uid() = p_doctor then
    raise exception 'owner cannot leave' using errcode = 'P0001';
  end if;
  update center_members set status = 'left' where center_id = p_center and user_id = p_doctor and role = 'doctor';
  update clinics set is_active = false where center_id = p_center and doctor_id = p_doctor;
end $$;

-- Reception / manager accounts (phone + password, like assistants).
create or replace function public.center_add_staff(p_center uuid, p_full_name text, p_phone text, p_password text,
                                                   p_role text default 'reception', p_can_finance boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_phone text; v_id uuid;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_role not in ('reception', 'manager') then raise exception 'invalid role' using errcode = 'P0001'; end if;
  if (select count(*) from center_members where center_id = p_center and role in ('reception', 'manager')) >= 20 then
    raise exception 'staff limit reached' using errcode = 'P0001';
  end if;
  v_phone := normalize_eg_phone(p_phone);
  v_id := _create_auth_user(phone_login_email(v_phone), p_password,
            jsonb_build_object('full_name', trim(p_full_name), 'role', 'patient', 'locale', 'ar'));
  perform set_config('doctori.trusted', '1', true);
  update profiles set role = 'assistant', phone = v_phone, login_kind = 'phone', created_by = auth.uid() where id = v_id;
  perform set_config('doctori.trusted', '', true);
  delete from patients where id = v_id;
  insert into center_members (center_id, user_id, role, can_finance, invited_by)
  values (p_center, v_id, p_role, coalesce(p_can_finance, false) or p_role = 'manager', auth.uid());
  return jsonb_build_object('user_id', v_id, 'phone', v_phone);
end $$;

create or replace function public.center_update_staff(p_center uuid, p_user uuid, p_can_finance boolean, p_active boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  update center_members set can_finance = coalesce(p_can_finance, false), status = case when p_active then 'active' else 'left' end
   where center_id = p_center and user_id = p_user and role in ('reception', 'manager');
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
end $$;

create or replace function public.center_reset_staff_password(p_center uuid, p_user uuid, p_password text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin')
     or not exists (select 1 from center_members where center_id = p_center and user_id = p_user and role in ('reception', 'manager')) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  perform _set_auth_password(p_user, p_password);
end $$;

-- Center staff set a doctor's working hours at the center: [{"weekday":0,"opens":"17:00","closes":"22:00"}, …]
create or replace function public.center_set_hours(p_center uuid, p_doctor uuid, p_hours jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_clinic uuid; h jsonb;
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  select clinic_id into v_clinic from center_members where center_id = p_center and user_id = p_doctor and role = 'doctor' and status = 'active';
  if v_clinic is null then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from clinic_hours where clinic_id = v_clinic;
  for h in select * from jsonb_array_elements(coalesce(p_hours, '[]'::jsonb)) loop
    insert into clinic_hours (clinic_id, weekday, opens_at, closes_at)
    values (v_clinic, (h->>'weekday')::smallint, (h->>'opens')::time, (h->>'closes')::time);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------
create or replace function public.my_centers()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'center_id', c.id, 'name', c.name, 'logo_url', c.logo_url, 'role', m.role, 'status', m.status,
      'share_percent', m.share_percent, 'can_finance', m.can_finance,
      'owner_name', op.full_name, 'doctors', (select count(*) from center_members x where x.center_id = c.id
                                              and x.role = 'doctor' and x.status = 'active'))
      order by (m.status = 'invited') desc, c.name), '[]'::jsonb)
  from center_members m join centers c on c.id = m.center_id join profiles op on op.id = c.owner_id
  where m.user_id = auth.uid() and m.status in ('active', 'invited');
$$;

create or replace function public.center_doctors(p_center uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_day date := (now() at time zone 'Africa/Cairo')::date;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'doctor_id', m.user_id, 'name', p.full_name, 'avatar_url', p.avatar_url, 'phone', p.phone, 'status', m.status,
      'specialty_ar', s.name_ar, 'specialty_en', s.name_en, 'doctor_status', d.status,
      'share_percent', m.share_percent, 'share_by_kind', m.share_by_kind, 'clinic_id', m.clinic_id,
      'hours', (select coalesce(jsonb_agg(jsonb_build_object('weekday', h.weekday, 'opens', to_char(h.opens_at, 'HH24:MI'),
                                                            'closes', to_char(h.closes_at, 'HH24:MI')) order by h.weekday, h.opens_at), '[]'::jsonb)
                from clinic_hours h where h.clinic_id = m.clinic_id),
      'today_bookings', (select count(*) from appointments a where a.clinic_id = m.clinic_id and a.status in ('pending', 'confirmed', 'completed')
                           and (a.starts_at at time zone 'Africa/Cairo')::date = v_day),
      'waiting', (select count(*) from clinic_queue q where q.clinic_id = m.clinic_id and q.day = v_day and q.status = 'waiting'))
      order by (m.status = 'active') desc, p.full_name)
    from center_members m join profiles p on p.id = m.user_id join doctors d on d.id = m.user_id
    left join specialties s on s.id = d.specialty_id
    where m.center_id = p_center and m.role = 'doctor' and m.status in ('active', 'invited')), '[]'::jsonb);
end $$;

create or replace function public.center_staff(p_center uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not center_can(p_center, 'admin') then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', p.full_name, 'phone', p.phone,
      'role', m.role, 'status', m.status, 'can_finance', m.can_finance, 'avatar_url', p.avatar_url) order by m.role, p.full_name)
    from center_members m join profiles p on p.id = m.user_id
    where m.center_id = p_center and m.role in ('owner', 'manager', 'reception')), '[]'::jsonb);
end $$;

create or replace function public.center_appointments(p_center uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'starts_at', a.starts_at, 'status', a.status, 'patient_note', a.patient_note,
      'patient_id', a.patient_id, 'patient_name', pp.full_name, 'patient_phone', pp.phone, 'patient_avatar', pp.avatar_url,
      'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
      'clinic_id', a.clinic_id,
      'local_date', to_char(a.starts_at at time zone 'Africa/Cairo', 'YYYY-MM-DD'),
      'local_time', to_char(a.starts_at at time zone 'Africa/Cairo', 'HH24:MI')) order by a.starts_at)
    from appointments a join clinics c on c.id = a.clinic_id and c.center_id = p_center
    join profiles pp on pp.id = a.patient_id join profiles dp on dp.id = a.doctor_id
    join doctors d on d.id = a.doctor_id left join specialties s on s.id = d.specialty_id
    where a.starts_at >= (p_from::timestamp at time zone 'Africa/Cairo')
      and a.starts_at < ((p_to + 1)::timestamp at time zone 'Africa/Cairo')), '[]'::jsonb);
end $$;

-- Doctor's share of one income row.
create or replace function public._doctor_cut(p_center uuid, p_doctor uuid, p_kind text, p_amount numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select round(p_amount * coalesce((m.share_by_kind->>p_kind)::numeric, m.share_percent, 100) / 100, 2)
  from center_members m where m.center_id = p_center and m.user_id = p_doctor and m.role = 'doctor';
$$;

-- ---------------------------------------------------------------------
-- Money
-- ---------------------------------------------------------------------
create or replace function public.center_save_income(p_center uuid, p_doctor uuid, p_kind text, p_amount numeric,
  p_on date default null, p_patient uuid default null, p_patient_name text default null, p_note text default null,
  p_appointment uuid default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  if not exists (select 1 from center_members where center_id = p_center and user_id = p_doctor and role = 'doctor' and status = 'active') then
    raise exception 'doctor is not in this center' using errcode = 'P0001';
  end if;
  if p_patient is not null and not exists (select 1 from care_links where patient_id = p_patient and doctor_id = p_doctor)
     and not exists (select 1 from appointments where patient_id = p_patient and doctor_id = p_doctor) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_id is null then
    insert into doctor_income (doctor_id, center_id, patient_id, patient_name, kind, amount, paid_on, note, appointment_id, created_by)
    values (p_doctor, p_center, p_patient, nullif(trim(p_patient_name), ''), p_kind, p_amount,
            coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_note), ''), p_appointment, auth.uid())
    returning id into v_id;
  else
    if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
    update doctor_income set doctor_id = p_doctor, kind = p_kind, amount = p_amount, paid_on = coalesce(p_on, paid_on),
           patient_id = p_patient, patient_name = nullif(trim(p_patient_name), ''), note = nullif(trim(p_note), '')
     where id = p_id and center_id = p_center returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.center_save_expense(p_center uuid, p_category text, p_amount numeric, p_on date default null,
                                                      p_reason text default null, p_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_id is null then
    insert into center_expenses (center_id, category, amount, spent_on, reason, created_by)
    values (p_center, p_category, p_amount, coalesce(p_on, (now() at time zone 'Africa/Cairo')::date), nullif(trim(p_reason), ''), auth.uid())
    returning id into v_id;
  else
    update center_expenses set category = p_category, amount = p_amount, spent_on = coalesce(p_on, spent_on), reason = nullif(trim(p_reason), '')
     where id = p_id and center_id = p_center returning id into v_id;
    if v_id is null then raise exception 'not allowed' using errcode = '42501'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.center_delete_entry(p_center uuid, p_type text, p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not center_can(p_center, 'finance') then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_type = 'income' then
    delete from doctor_income where id = p_id and center_id = p_center;
  else
    delete from center_expenses where id = p_id and center_id = p_center;
  end if;
  if not found then raise exception 'not allowed' using errcode = '42501'; end if;
  perform write_audit('center.entry_deleted', 'centers', p_center::text, jsonb_build_object('type', p_type, 'id', p_id));
end $$;

-- The center ledger for a period: per doctor (income, their share, center share, cases), expenses, and the net.
-- Reception without finance rights sees only today's entries they need (no totals of doctor shares).
create or replace function public.center_finance(p_center uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_fin boolean;
begin
  if not center_can(p_center) then raise exception 'not allowed' using errcode = '42501'; end if;
  v_fin := center_can(p_center, 'finance');
  return (
    with inc as (
      select i.*, _doctor_cut(p_center, i.doctor_id, i.kind, i.amount) as dcut
      from doctor_income i where i.center_id = p_center and i.paid_on between p_from and p_to),
    per as (
      select doctor_id, sum(amount) income, sum(dcut) doctor_share, count(*) entries,
             count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) cases
      from inc group by doctor_id),
    exp as (select * from center_expenses where center_id = p_center and spent_on between p_from and p_to)
    select jsonb_build_object(
      'can_finance', v_fin,
      'income', (select coalesce(sum(amount), 0) from inc),
      'doctor_shares', case when v_fin then (select coalesce(sum(dcut), 0) from inc) end,
      'center_share', case when v_fin then (select coalesce(sum(amount - dcut), 0) from inc) end,
      'expenses', case when v_fin then (select coalesce(sum(amount), 0) from exp) end,
      'net', case when v_fin then (select coalesce(sum(amount - dcut), 0) from inc) - (select coalesce(sum(amount), 0) from exp) end,
      'cases', (select coalesce(sum(cases), 0) from per),
      'doctors', (select coalesce(jsonb_agg(jsonb_build_object(
            'doctor_id', per.doctor_id, 'name', p.full_name, 'avatar_url', p.avatar_url, 'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
            'income', per.income, 'cases', per.cases,
            'doctor_share', case when v_fin then per.doctor_share end,
            'center_share', case when v_fin then per.income - per.doctor_share end,
            'share_percent', m.share_percent) order by per.income desc), '[]'::jsonb)
          from per join profiles p on p.id = per.doctor_id join doctors d on d.id = per.doctor_id
          left join specialties s on s.id = d.specialty_id
          left join center_members m on m.center_id = p_center and m.user_id = per.doctor_id and m.role = 'doctor'),
      'by_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d, 'income', i, 'cases', c) order by d), '[]'::jsonb)
                 from (select paid_on d, sum(amount) i, count(distinct coalesce(patient_id::text, nullif(patient_name, ''), id::text)) c
                       from inc group by paid_on) x),
      'income_items', (select coalesce(jsonb_agg(jsonb_build_object(
            'id', i.id, 'doctor_id', i.doctor_id, 'doctor_name', dp.full_name, 'kind', i.kind, 'amount', i.amount,
            'doctor_share', case when v_fin then i.dcut end, 'paid_on', i.paid_on, 'note', i.note,
            'patient_name', coalesce(pp.full_name, i.patient_name), 'by', cb.full_name) order by i.paid_on desc, i.created_at desc), '[]'::jsonb)
          from (select * from inc order by paid_on desc, created_at desc limit 300) i
          join profiles dp on dp.id = i.doctor_id left join profiles pp on pp.id = i.patient_id left join profiles cb on cb.id = i.created_by),
      'expense_items', case when v_fin then (select coalesce(jsonb_agg(jsonb_build_object(
            'id', e.id, 'category', e.category, 'amount', e.amount, 'spent_on', e.spent_on, 'reason', e.reason, 'by', cb.full_name)
            order by e.spent_on desc, e.created_at desc), '[]'::jsonb)
          from exp e left join profiles cb on cb.id = e.created_by) else '[]'::jsonb end));
end $$;

-- A doctor sees what the centers they work in recorded for them (income and their share).
create or replace function public.doctor_center_earnings(p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('center_id', c.id, 'name', c.name, 'income', x.income, 'my_share', x.share, 'cases', x.n)
                            order by c.name), '[]'::jsonb)
  from (select center_id, sum(amount) income, sum(_doctor_cut(center_id, doctor_id, kind, amount)) share, count(*) n
        from doctor_income where doctor_id = auth.uid() and center_id is not null and paid_on between p_from and p_to
        group by center_id) x
  join centers c on c.id = x.center_id;
$$;

-- Context: tells the app which centers the user runs (for the center home screen).
create or replace function public.get_my_context()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'role', p.role, 'full_name', p.full_name, 'email', p.email,
    'phone', p.phone, 'login_kind', p.login_kind,
    'locale', p.locale, 'is_suspended', p.is_suspended, 'avatar_url', p.avatar_url,
    'doctor_status', d.status, 'specialty_id', d.specialty_id,
    'specialty_ar', s.name_ar, 'specialty_en', s.name_en,
    'has_pending_verification', exists (select 1 from doctor_verifications v
                                        where v.doctor_id = p.id and v.decision is null),
    'assistant_of', (select jsonb_build_object(
        'doctor_id', a.doctor_id, 'doctor_name', dp.full_name, 'doctor_avatar', dp.avatar_url,
        'doctor_status', dd.status, 'specialty_ar', ds.name_ar, 'specialty_en', ds.name_en,
        'can_bookings', a.can_bookings, 'can_patients', a.can_patients,
        'can_add_patients', a.can_add_patients, 'can_medical', a.can_medical, 'can_finance', a.can_finance)
      from doctor_assistants a
      join profiles dp on dp.id = a.doctor_id
      join doctors dd on dd.id = a.doctor_id
      left join specialties ds on ds.id = dd.specialty_id
      where a.assistant_id = p.id limit 1),
    'centers', (select coalesce(jsonb_agg(jsonb_build_object('center_id', c.id, 'name', c.name, 'role', m.role,
                                                             'can_finance', m.can_finance or m.role in ('owner', 'manager'))
                                          order by c.name), '[]'::jsonb)
                from center_members m join centers c on c.id = m.center_id
                where m.user_id = p.id and m.status = 'active' and m.role in ('owner', 'manager', 'reception')))
  from profiles p
  left join doctors d on d.id = p.id
  left join specialties s on s.id = d.specialty_id
  where p.id = auth.uid();
$$;

revoke all on function public.center_can(uuid, text), public._center_doctor_clinic(uuid, uuid), public._doctor_cut(uuid, uuid, text, numeric)
  from public, anon;
revoke all on function public._center_doctor_clinic(uuid, uuid) from authenticated;
grant execute on function public.center_can(uuid, text), public._doctor_cut(uuid, uuid, text, numeric) to authenticated;
revoke all on function public.create_center(text, text, text, int, int, text, double precision, double precision, uuid),
  public.admin_create_center(text, text, text, text, text, int, int),
  public.update_center(uuid, text, text, text, int, int, text, double precision, double precision, text),
  public.center_invite_doctor(uuid, text, numeric), public.center_respond_invite(uuid, boolean),
  public.center_set_share(uuid, uuid, numeric, jsonb), public.center_remove_doctor(uuid, uuid),
  public.center_add_staff(uuid, text, text, text, text, boolean), public.center_update_staff(uuid, uuid, boolean, boolean),
  public.center_reset_staff_password(uuid, uuid, text), public.center_set_hours(uuid, uuid, jsonb),
  public.my_centers(), public.center_doctors(uuid), public.center_staff(uuid), public.center_appointments(uuid, date, date),
  public.center_save_income(uuid, uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.center_save_expense(uuid, text, numeric, date, text, uuid), public.center_delete_entry(uuid, text, uuid),
  public.center_finance(uuid, date, date), public.doctor_center_earnings(date, date)
from public, anon;
grant execute on function public.create_center(text, text, text, int, int, text, double precision, double precision, uuid),
  public.admin_create_center(text, text, text, text, text, int, int),
  public.update_center(uuid, text, text, text, int, int, text, double precision, double precision, text),
  public.center_invite_doctor(uuid, text, numeric), public.center_respond_invite(uuid, boolean),
  public.center_set_share(uuid, uuid, numeric, jsonb), public.center_remove_doctor(uuid, uuid),
  public.center_add_staff(uuid, text, text, text, text, boolean), public.center_update_staff(uuid, uuid, boolean, boolean),
  public.center_reset_staff_password(uuid, uuid, text), public.center_set_hours(uuid, uuid, jsonb),
  public.my_centers(), public.center_doctors(uuid), public.center_staff(uuid), public.center_appointments(uuid, date, date),
  public.center_save_income(uuid, uuid, text, numeric, date, uuid, text, text, uuid, uuid),
  public.center_save_expense(uuid, text, numeric, date, text, uuid), public.center_delete_entry(uuid, text, uuid),
  public.center_finance(uuid, date, date), public.doctor_center_earnings(date, date)
to authenticated;


-- =====================================================================
-- حسابات اتسجلت قبل ما الجداول تتعمل: نعملها ملفات
-- =====================================================================
insert into public.profiles (id, role, full_name, email, locale)
select u.id,
       case when u.raw_user_meta_data->>'role' = 'doctor' then 'doctor'::public.user_role else 'patient'::public.user_role end,
       coalesce(nullif(trim(u.raw_user_meta_data->>'full_name'), ''), 'مستخدم'), u.email, 'ar'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);
insert into public.patients (id)
select p.id from public.profiles p where p.role = 'patient'
  and not exists (select 1 from public.patients x where x.id = p.id);
insert into public.doctors (id)
select p.id from public.profiles p where p.role = 'doctor'
  and not exists (select 1 from public.doctors x where x.id = p.id);

-- =====================================================================
-- تأكيد حساب المدير وجعله مديراً
-- =====================================================================
update auth.users set email_confirmed_at = coalesce(email_confirmed_at, now())
 where lower(email) = 'rafatsaeed719@gmail.com';
update public.profiles set role = 'admin', is_suspended = false
 where lower(email) = 'rafatsaeed719@gmail.com';

-- تحديث ذاكرة السيرفر عشان التطبيق يشوف الدوال الجديدة فوراً
notify pgrst, 'reload schema';

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_my_context') as "دالة التطبيق",
  (select role::text from public.profiles where lower(email) = 'rafatsaeed719@gmail.com') as "الصلاحية";
