-- =====================================================================
-- دكتوري — كود الإعداد الكامل (قاعدة البيانات + التحديثات + حساب المدير)
-- آمن للتشغيل على مشروع جديد. لو فيه إعداد ناقص من محاولة سابقة، بيتنظف الأول.
-- =====================================================================
do $reset$
begin
  if to_regclass('public.profiles') is null then
    drop table if exists public.audit_log, public.consents, public.care_links, public.join_requests,
      public.clinic_hours, public.clinics, public.doctor_verifications, public.doctors, public.patients,
      public.app_settings, public.cities, public.governorates, public.specialties cascade;
    drop type if exists public.user_role, public.doctor_status, public.request_status,
      public.link_status, public.share_scope, public.gender cascade;
  end if;
end $reset$;
drop trigger if exists on_auth_user_created on auth.users;
drop policy if exists "verification: doctor uploads to own folder" on storage.objects;
drop policy if exists "verification: doctor or admin reads" on storage.objects;

-- =====================================================================
-- دكتوري — المرحلة الأولى: الحسابات، الأطباء، العيادات، البحث، طلبات الانضمام
-- Doctori — Phase 1 core schema + Row Level Security
-- Target: Supabase (PostgreSQL 15+). Run once in SQL Editor or via `supabase db push`.
-- Security model: every table has RLS; sensitive state changes go through
-- SECURITY DEFINER functions that check the caller and write the audit log.
-- =====================================================================

-- ---------- Types ----------
create type public.user_role      as enum ('patient', 'doctor', 'admin');
create type public.doctor_status  as enum ('pending', 'verified', 'rejected', 'suspended');
create type public.request_status as enum ('pending', 'accepted', 'rejected', 'cancelled');
create type public.link_status    as enum ('active', 'ended');
create type public.share_scope    as enum ('full', 'own_uploads');
create type public.gender         as enum ('male', 'female');

-- ---------- Lookup tables (managed by admin) ----------
create table public.specialties (
  id         serial primary key,
  parent_id  int references public.specialties(id),
  name_ar    text not null,
  name_en    text not null,
  is_active  boolean not null default true,
  sort_order int not null default 0
);

create table public.governorates (
  id      serial primary key,
  name_ar text not null unique,
  name_en text not null unique
);

create table public.cities (
  id             serial primary key,
  governorate_id int not null references public.governorates(id),
  name_ar        text not null,
  name_en        text not null,
  unique (governorate_id, name_ar)
);

create table public.app_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);

-- ---------- Accounts ----------
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         public.user_role not null default 'patient',
  full_name    text not null check (length(trim(full_name)) between 2 and 120),
  phone        text,
  email        text,
  gender       public.gender,
  birth_date   date check (birth_date is null or birth_date > '1900-01-01'),
  locale       text not null default 'ar' check (locale in ('ar', 'en')),
  is_suspended boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.patients (
  id                uuid primary key references public.profiles(id) on delete cascade,
  emergency_contact text,
  created_at        timestamptz not null default now()
);

create table public.doctors (
  id               uuid primary key references public.profiles(id) on delete cascade,
  specialty_id     int references public.specialties(id),
  sub_specialty_id int references public.specialties(id),
  title            text,                 -- e.g. أخصائي / استشاري
  bio              text check (bio is null or length(bio) <= 2000),
  qualifications   text,
  years_experience int check (years_experience between 0 and 70),
  license_number   text,
  photo_path       text,                 -- storage path (public avatars bucket)
  public_phone     text,                 -- phone the doctor allows patients to see
  status           public.doctor_status not null default 'pending',
  accepting_new    boolean not null default true,
  verified_at      timestamptz,
  verified_by      uuid references public.profiles(id),
  rating_avg       numeric(3,2) not null default 0,
  rating_count     int not null default 0,
  created_at       timestamptz not null default now()
);

create table public.doctor_verifications (
  id           uuid primary key default gen_random_uuid(),
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  documents    jsonb not null default '[]'::jsonb,   -- private storage paths
  note         text,
  submitted_at timestamptz not null default now(),
  decision     public.doctor_status,                  -- verified / rejected
  reviewed_by  uuid references public.profiles(id),
  reviewed_at  timestamptz,
  review_notes text
);

-- ---------- Clinics ----------
create table public.clinics (
  id             uuid primary key default gen_random_uuid(),
  doctor_id      uuid not null references public.doctors(id) on delete cascade,
  name           text not null,
  address        text not null,
  governorate_id int references public.governorates(id),
  city_id        int references public.cities(id),
  area           text,
  lat            double precision check (lat between -90 and 90),
  lng            double precision check (lng between -180 and 180),
  phone          text,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table public.clinic_hours (
  id        uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  weekday   smallint not null check (weekday between 0 and 6),  -- 0 = Sunday
  opens_at  time not null,
  closes_at time not null check (closes_at > opens_at)
);

-- ---------- Patient ↔ doctor linking ----------
create table public.join_requests (
  id            uuid primary key default gen_random_uuid(),
  patient_id    uuid not null references public.patients(id) on delete cascade,
  doctor_id     uuid not null references public.doctors(id) on delete cascade,
  clinic_id     uuid references public.clinics(id) on delete set null,
  message       text check (message is null or length(message) <= 500),
  share_scope   public.share_scope not null default 'full',
  status        public.request_status not null default 'pending',
  reject_reason text,
  created_at    timestamptz not null default now(),
  responded_at  timestamptz
);
create unique index join_requests_one_pending
  on public.join_requests (patient_id, doctor_id) where status = 'pending';

create table public.care_links (
  id         uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  doctor_id  uuid not null references public.doctors(id) on delete cascade,
  request_id uuid references public.join_requests(id),
  status     public.link_status not null default 'active',
  started_at timestamptz not null default now(),
  ended_at   timestamptz,
  ended_by   uuid references public.profiles(id)
);
create unique index care_links_one_active
  on public.care_links (patient_id, doctor_id) where status = 'active';

create table public.consents (
  id           uuid primary key default gen_random_uuid(),
  care_link_id uuid not null references public.care_links(id) on delete cascade,
  patient_id   uuid not null references public.patients(id) on delete cascade,
  doctor_id    uuid not null references public.doctors(id) on delete cascade,
  scope        public.share_scope not null,
  granted_at   timestamptz not null default now(),
  revoked_at   timestamptz
);
create unique index consents_one_live on public.consents (care_link_id) where revoked_at is null;

-- ---------- Audit log (append-only) ----------
create table public.audit_log (
  id         bigserial primary key,
  actor_id   uuid,
  action     text not null,
  entity     text not null,
  entity_id  text,
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index on public.clinics (doctor_id);
create index on public.clinics (governorate_id, city_id);
create index on public.doctors (status, specialty_id);
create index on public.join_requests (doctor_id, status);
create index on public.care_links (doctor_id, status);
create index on public.care_links (patient_id, status);

-- =====================================================================
-- Helper functions (SECURITY DEFINER so they can be used inside policies
-- without recursive RLS checks). search_path pinned against hijacking.
-- =====================================================================
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and role = 'admin' and not is_suspended);
$$;

create or replace function public.is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and not is_suspended);
$$;

create or replace function public.has_active_link(p_patient uuid, p_doctor uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from care_links
                 where patient_id = p_patient and doctor_id = p_doctor and status = 'active');
$$;

-- Used by phase-2 policies: may the calling doctor read this patient's medical data?
-- Returns the live consent scope, or null when there is no access.
create or replace function public.doctor_access_scope(p_patient uuid) returns public.share_scope
language sql stable security definer set search_path = public as $$
  select c.scope
  from consents c
  join care_links l on l.id = c.care_link_id and l.status = 'active'
  join doctors d on d.id = l.doctor_id and d.status = 'verified'
  join profiles p on p.id = d.id and not p.is_suspended
  where c.patient_id = p_patient and c.doctor_id = auth.uid() and c.revoked_at is null
  limit 1;
$$;

create or replace function public.write_audit(p_action text, p_entity text, p_entity_id text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into audit_log (actor_id, action, entity, entity_id, details)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function public.write_audit(text, text, text, jsonb) from public;

-- =====================================================================
-- Triggers
-- =====================================================================

-- New sign-up → profile + patient/doctor row. Role from sign-up metadata,
-- but only 'patient' or 'doctor': nobody can sign up as admin.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_role user_role := case when new.raw_user_meta_data->>'role' = 'doctor'
                           then 'doctor'::user_role else 'patient'::user_role end;
begin
  insert into profiles (id, role, full_name, phone, email, locale)
  values (new.id, v_role,
          coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), 'مستخدم'),
          new.phone, new.email,
          case when new.raw_user_meta_data->>'locale' = 'en' then 'en' else 'ar' end);
  if v_role = 'doctor' then
    insert into doctors (id) values (new.id);
  else
    insert into patients (id) values (new.id);
  end if;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- Users may edit their own profile, but never their role / suspension.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- auth.uid() is null for the SQL editor / service role (owner maintenance).
  if not public.is_admin() and auth.uid() is not null then
    if new.role is distinct from old.role or new.is_suspended is distinct from old.is_suspended
       or new.id is distinct from old.id then
      raise exception 'not allowed to change role or suspension' using errcode = '42501';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Doctors may edit their profile, but not verification or rating fields.
create or replace function public.guard_doctor_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() and auth.uid() is not null then
    if new.status is distinct from old.status
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by
       or new.rating_avg is distinct from old.rating_avg
       or new.rating_count is distinct from old.rating_count then
      raise exception 'verification and rating fields are managed by the platform' using errcode = '42501';
    end if;
    -- Changing the licence number of a verified doctor sends them back to review.
    if old.status = 'verified' and new.license_number is distinct from old.license_number then
      new.status := 'pending';
      new.verified_at := null;
      new.verified_by := null;
    end if;
  end if;
  return new;
end $$;
create trigger doctors_guard before update on public.doctors
  for each row execute function public.guard_doctor_update();

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger clinics_touch before update on public.clinics
  for each row execute function public.touch_updated_at();

-- Audit log is append-only even for the table owner's API roles.
create or replace function public.block_audit_change() returns trigger language plpgsql as $$
begin raise exception 'audit_log is append-only' using errcode = '42501'; end $$;
create trigger audit_no_update before update or delete on public.audit_log
  for each row execute function public.block_audit_change();

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.specialties          enable row level security;
alter table public.governorates         enable row level security;
alter table public.cities               enable row level security;
alter table public.app_settings         enable row level security;
alter table public.profiles             enable row level security;
alter table public.patients             enable row level security;
alter table public.doctors              enable row level security;
alter table public.doctor_verifications enable row level security;
alter table public.clinics              enable row level security;
alter table public.clinic_hours         enable row level security;
alter table public.join_requests        enable row level security;
alter table public.care_links           enable row level security;
alter table public.consents             enable row level security;
alter table public.audit_log            enable row level security;

-- Lookups: everyone reads, admin writes.
create policy lookup_read on public.specialties  for select using (true);
create policy lookup_read on public.governorates for select using (true);
create policy lookup_read on public.cities       for select using (true);
create policy lookup_read on public.app_settings for select using (true);
create policy admin_write on public.specialties  for all using (public.is_admin()) with check (public.is_admin());
create policy admin_write on public.governorates for all using (public.is_admin()) with check (public.is_admin());
create policy admin_write on public.cities       for all using (public.is_admin()) with check (public.is_admin());
create policy admin_write on public.app_settings for all using (public.is_admin()) with check (public.is_admin());

-- Profiles: self, admin, and the two sides of an ACTIVE care link.
create policy profiles_read on public.profiles for select using (
  id = auth.uid() or public.is_admin()
  or public.has_active_link(id, auth.uid())       -- doctor reading own patient
  or public.has_active_link(auth.uid(), id)       -- patient reading own doctor
);
create policy profiles_update_self on public.profiles for update
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- Patients: self, admin, linked doctor.
create policy patients_read on public.patients for select using (
  id = auth.uid() or public.is_admin() or public.has_active_link(id, auth.uid()));
create policy patients_update_self on public.patients for update
  using (id = auth.uid()) with check (id = auth.uid());

-- Doctors: verified doctors are public to signed-in users; self and admin see all.
create policy doctors_read on public.doctors for select using (
  (status = 'verified' and auth.uid() is not null) or id = auth.uid() or public.is_admin());
create policy doctors_update_self on public.doctors for update
  using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

-- Verification submissions: doctor submits/reads own, admin reviews via RPC.
create policy verif_read on public.doctor_verifications for select using (
  doctor_id = auth.uid() or public.is_admin());
create policy verif_insert on public.doctor_verifications for insert with check (
  doctor_id = auth.uid() and decision is null and reviewed_by is null);

-- Clinics + hours: public when the doctor is verified; doctor manages own.
create policy clinics_read on public.clinics for select using (
  doctor_id = auth.uid() or public.is_admin()
  or (is_active and exists (select 1 from public.doctors d
                            where d.id = clinics.doctor_id and d.status = 'verified')));
create policy clinics_write on public.clinics for all
  using (doctor_id = auth.uid() and public.is_active_user())
  with check (doctor_id = auth.uid() and public.is_active_user());

create policy hours_read on public.clinic_hours for select using (
  exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id));  -- inherits clinics RLS
create policy hours_write on public.clinic_hours for all
  using (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.doctor_id = auth.uid()))
  with check (exists (select 1 from public.clinics c where c.id = clinic_hours.clinic_id and c.doctor_id = auth.uid()));

-- Linking tables: read by the two parties and admin; writes ONLY via functions below.
create policy jr_read on public.join_requests for select using (
  patient_id = auth.uid() or doctor_id = auth.uid() or public.is_admin());
create policy cl_read on public.care_links for select using (
  patient_id = auth.uid() or doctor_id = auth.uid() or public.is_admin());
create policy consent_read on public.consents for select using (
  patient_id = auth.uid() or doctor_id = auth.uid() or public.is_admin());

-- Audit: admin reads; a patient sees entries about their own links/consents.
create policy audit_read on public.audit_log for select using (
  public.is_admin() or (details->>'patient_id') = auth.uid()::text);

-- =====================================================================
-- Business functions (the only way to change linking / verification state)
-- =====================================================================

-- Patient asks to join a doctor's clinic. Free; independent of subscription.
create or replace function public.request_join(
  p_doctor uuid, p_clinic uuid default null, p_message text default null,
  p_scope public.share_scope default 'full')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if not exists (select 1 from patients pa join profiles p on p.id = pa.id
                 where pa.id = v_uid and not p.is_suspended) then
    raise exception 'only active patients can send join requests' using errcode = '42501';
  end if;
  if not exists (select 1 from doctors d join profiles p on p.id = d.id
                 where d.id = p_doctor and d.status = 'verified' and d.accepting_new and not p.is_suspended) then
    raise exception 'doctor is not available for new patients' using errcode = 'P0001';
  end if;
  if p_clinic is not null and not exists (select 1 from clinics where id = p_clinic and doctor_id = p_doctor) then
    raise exception 'clinic does not belong to this doctor' using errcode = 'P0001';
  end if;
  if has_active_link(v_uid, p_doctor) then
    raise exception 'already linked to this doctor' using errcode = 'P0001';
  end if;
  -- Anti-abuse limits
  if (select count(*) from join_requests where patient_id = v_uid and status = 'pending') >= 10 then
    raise exception 'too many pending requests' using errcode = 'P0001';
  end if;
  if (select count(*) from join_requests where patient_id = v_uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'daily request limit reached' using errcode = 'P0001';
  end if;

  insert into join_requests (patient_id, doctor_id, clinic_id, message, share_scope)
  values (v_uid, p_doctor, p_clinic, nullif(trim(p_message), ''), p_scope)
  returning id into v_id;

  perform write_audit('join_request.created', 'join_requests', v_id::text,
                      jsonb_build_object('patient_id', v_uid, 'doctor_id', p_doctor));
  return v_id;
exception when unique_violation then
  raise exception 'a pending request already exists' using errcode = 'P0001';
end $$;

-- Doctor accepts or rejects. Accept → care link + consent at the patient's chosen scope.
create or replace function public.respond_join(p_request uuid, p_accept boolean, p_reason text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare r join_requests; v_link uuid;
begin
  select * into r from join_requests where id = p_request for update;
  if not found or r.doctor_id <> auth.uid() then
    raise exception 'request not found' using errcode = '42501';
  end if;
  if not exists (select 1 from doctors d join profiles p on p.id = d.id
                 where d.id = auth.uid() and d.status = 'verified' and not p.is_suspended) then
    raise exception 'doctor account is not active' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    raise exception 'request already handled' using errcode = 'P0001';
  end if;

  if p_accept then
    update join_requests set status = 'accepted', responded_at = now() where id = r.id;
    insert into care_links (patient_id, doctor_id, request_id)
    values (r.patient_id, r.doctor_id, r.id) returning id into v_link;
    insert into consents (care_link_id, patient_id, doctor_id, scope)
    values (v_link, r.patient_id, r.doctor_id, r.share_scope);
  else
    update join_requests set status = 'rejected', responded_at = now(),
           reject_reason = nullif(trim(p_reason), '') where id = r.id;
  end if;

  perform write_audit(case when p_accept then 'join_request.accepted' else 'join_request.rejected' end,
                      'join_requests', r.id::text,
                      jsonb_build_object('patient_id', r.patient_id, 'doctor_id', r.doctor_id, 'care_link_id', v_link));
  return v_link;
end $$;

-- Patient withdraws a pending request.
create or replace function public.cancel_join_request(p_request uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r join_requests;
begin
  select * into r from join_requests where id = p_request for update;
  if not found or r.patient_id <> auth.uid() then
    raise exception 'request not found' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    raise exception 'request already handled' using errcode = 'P0001';
  end if;
  update join_requests set status = 'cancelled', responded_at = now() where id = r.id;
  perform write_audit('join_request.cancelled', 'join_requests', r.id::text,
                      jsonb_build_object('patient_id', r.patient_id, 'doctor_id', r.doctor_id));
end $$;

-- Either side ends the link; consent is revoked at the same moment.
create or replace function public.end_care_link(p_link uuid)
returns void language plpgsql security definer set search_path = public as $$
declare l care_links;
begin
  select * into l from care_links where id = p_link for update;
  if not found or auth.uid() not in (l.patient_id, l.doctor_id) then
    raise exception 'link not found' using errcode = '42501';
  end if;
  if l.status <> 'active' then
    raise exception 'link already ended' using errcode = 'P0001';
  end if;
  update care_links set status = 'ended', ended_at = now(), ended_by = auth.uid() where id = l.id;
  update consents set revoked_at = now() where care_link_id = l.id and revoked_at is null;
  perform write_audit('care_link.ended', 'care_links', l.id::text,
                      jsonb_build_object('patient_id', l.patient_id, 'doctor_id', l.doctor_id));
end $$;

-- Patient changes what a linked doctor may see (keeps history: old row revoked, new row granted).
create or replace function public.set_consent_scope(p_link uuid, p_scope public.share_scope)
returns void language plpgsql security definer set search_path = public as $$
declare l care_links;
begin
  select * into l from care_links where id = p_link for update;
  if not found or l.patient_id <> auth.uid() or l.status <> 'active' then
    raise exception 'link not found' using errcode = '42501';
  end if;
  update consents set revoked_at = now() where care_link_id = l.id and revoked_at is null;
  insert into consents (care_link_id, patient_id, doctor_id, scope)
  values (l.id, l.patient_id, l.doctor_id, p_scope);
  perform write_audit('consent.changed', 'consents', l.id::text,
                      jsonb_build_object('patient_id', l.patient_id, 'doctor_id', l.doctor_id, 'scope', p_scope));
end $$;

-- Admin: verify / reject / suspend a doctor.
create or replace function public.admin_review_doctor(p_doctor uuid, p_decision public.doctor_status, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_decision = 'pending' then raise exception 'invalid decision' using errcode = 'P0001'; end if;
  update doctors set status = p_decision,
         verified_at = case when p_decision = 'verified' then now() end,
         verified_by = case when p_decision = 'verified' then auth.uid() end
   where id = p_doctor;
  if not found then raise exception 'doctor not found' using errcode = 'P0001'; end if;
  update doctor_verifications set decision = p_decision, reviewed_by = auth.uid(),
         reviewed_at = now(), review_notes = p_notes
   where doctor_id = p_doctor and decision is null;
  perform write_audit('doctor.reviewed', 'doctors', p_doctor::text,
                      jsonb_build_object('decision', p_decision, 'notes', p_notes));
end $$;

-- Admin: suspend / reactivate any account.
create or replace function public.admin_set_suspended(p_user uuid, p_suspended boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only' using errcode = '42501'; end if;
  if p_user = auth.uid() then raise exception 'cannot suspend yourself' using errcode = 'P0001'; end if;
  update profiles set is_suspended = p_suspended where id = p_user;
  if not found then raise exception 'user not found' using errcode = 'P0001'; end if;
  perform write_audit(case when p_suspended then 'user.suspended' else 'user.reactivated' end,
                      'profiles', p_user::text, jsonb_build_object('reason', p_reason));
end $$;

-- Doctor search: verified, not suspended; filters + optional nearest-first (haversine, km).
-- Returns only public fields (no email / private phone).
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
  join best b on b.doctor_id = d.id
  left join specialties s on s.id = d.specialty_id
  left join cities ci on ci.id = b.city_id
  left join governorates g on g.id = b.governorate_id
  where auth.uid() is not null
    and d.status = 'verified'
    and (p_specialty is null or d.specialty_id = p_specialty or d.sub_specialty_id = p_specialty)
    and (not p_accepting_only or d.accepting_new)
    and (p_min_rating is null or d.rating_avg >= p_min_rating)
    and (p_query is null or p.full_name ilike '%' || p_query || '%'
         or s.name_ar ilike '%' || p_query || '%' or s.name_en ilike '%' || p_query || '%')
  order by b.dist nulls last, d.rating_avg desc, p.full_name
  limit least(greatest(p_limit, 1), 50) offset greatest(p_offset, 0);
$$;

-- Public card for one doctor (what a patient sees before joining).
create or replace function public.get_doctor_public(p_doctor uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', d.id, 'full_name', p.full_name, 'title', d.title, 'bio', d.bio,
    'qualifications', d.qualifications, 'years_experience', d.years_experience,
    'specialty', s.name_ar, 'specialty_en', s.name_en, 'photo_path', d.photo_path,
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

-- =====================================================================
-- Grants: API roles reach tables only through RLS; anon gets lookups only.
-- =====================================================================
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated, public;

grant select on public.specialties, public.governorates, public.cities, public.app_settings to anon, authenticated;
grant insert, update, delete on public.specialties, public.governorates, public.cities, public.app_settings to authenticated;
grant select, update on public.profiles, public.patients, public.doctors to authenticated;
grant select, insert on public.doctor_verifications to authenticated;
grant select, insert, update, delete on public.clinics, public.clinic_hours to authenticated;
grant select on public.join_requests, public.care_links, public.consents, public.audit_log to authenticated;
grant usage, select on all sequences in schema public to authenticated;

grant execute on function
  public.is_admin(), public.is_active_user(), public.has_active_link(uuid, uuid),
  public.doctor_access_scope(uuid),
  public.request_join(uuid, uuid, text, public.share_scope),
  public.respond_join(uuid, boolean, text),
  public.cancel_join_request(uuid),
  public.end_care_link(uuid),
  public.set_consent_scope(uuid, public.share_scope),
  public.admin_review_doctor(uuid, public.doctor_status, text),
  public.admin_set_suspended(uuid, boolean, text),
  public.search_doctors(text, int, int, int, double precision, double precision, boolean, numeric, smallint, int, int),
  public.get_doctor_public(uuid)
to authenticated;

-- =====================================================================
-- Seed: app settings + specialties + governorates (real reference data, not fake users)
-- =====================================================================
insert into public.app_settings (key, value) values
  ('app_name',          '{"ar": "دكتوري", "en": "Doctori"}'),
  ('default_locale',    '"ar"'),
  ('currency',          '"EGP"'),
  ('max_upload_mb',     '10'),
  ('allowed_mime',      '["image/jpeg", "image/png", "application/pdf"]'),
  ('emergency_notice',  '{"ar": "المحادثة ليست بديلاً عن الطوارئ. في الحالات الطارئة اتصل بالإسعاف 123.", "en": "Chat is not for emergencies. In an emergency call 123."}');

insert into public.specialties (name_ar, name_en, sort_order) values
  ('باطنة', 'Internal Medicine', 1), ('قلب وأوعية دموية', 'Cardiology', 2),
  ('جلدية', 'Dermatology', 3), ('أطفال', 'Pediatrics', 4),
  ('نساء وتوليد', 'Obstetrics & Gynecology', 5), ('عظام', 'Orthopedics', 6),
  ('أنف وأذن وحنجرة', 'ENT', 7), ('عيون', 'Ophthalmology', 8),
  ('مخ وأعصاب', 'Neurology', 9), ('نفسية', 'Psychiatry', 10),
  ('مسالك بولية', 'Urology', 11), ('أسنان', 'Dentistry', 12),
  ('جراحة عامة', 'General Surgery', 13), ('صدر', 'Pulmonology', 14),
  ('غدد صماء وسكر', 'Endocrinology & Diabetes', 15), ('كلى', 'Nephrology', 16),
  ('جهاز هضمي وكبد', 'Gastroenterology & Hepatology', 17), ('أورام', 'Oncology', 18),
  ('روماتيزم', 'Rheumatology', 19), ('علاج طبيعي', 'Physical Therapy', 20),
  ('تغذية', 'Nutrition', 21), ('طب الأسرة', 'Family Medicine', 22);

insert into public.governorates (name_ar, name_en) values
  ('القاهرة','Cairo'), ('الجيزة','Giza'), ('الإسكندرية','Alexandria'), ('القليوبية','Qalyubia'),
  ('الدقهلية','Dakahlia'), ('الشرقية','Sharqia'), ('الغربية','Gharbia'), ('المنوفية','Monufia'),
  ('البحيرة','Beheira'), ('كفر الشيخ','Kafr El Sheikh'), ('دمياط','Damietta'), ('بورسعيد','Port Said'),
  ('الإسماعيلية','Ismailia'), ('السويس','Suez'), ('الفيوم','Faiyum'), ('بني سويف','Beni Suef'),
  ('المنيا','Minya'), ('أسيوط','Asyut'), ('سوهاج','Sohag'), ('قنا','Qena'),
  ('الأقصر','Luxor'), ('أسوان','Aswan'), ('البحر الأحمر','Red Sea'), ('الوادي الجديد','New Valley'),
  ('مطروح','Matrouh'), ('شمال سيناء','North Sinai'), ('جنوب سيناء','South Sinai');

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
create policy clinics_admin on public.clinics for all using (public.is_admin()) with check (public.is_admin());
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

-- Ask the API to reload its schema cache so the app sees the new functions immediately
notify pgrst, 'reload schema';
select full_name as "الاسم", role as "الصلاحية" from public.profiles
 where lower(email) = 'rafatsaeed719@gmail.com';
