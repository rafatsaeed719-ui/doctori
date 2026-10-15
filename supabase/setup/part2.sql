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
