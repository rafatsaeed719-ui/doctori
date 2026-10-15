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
create table public.doctor_assistants (
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

create table public.medical_entries (
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
create policy med_entries_read on public.medical_entries for select using (public.can_view_medical(patient_id, shared_with));
create policy med_entries_insert on public.medical_entries for insert with check (
  patient_id = auth.uid() and created_by = auth.uid()
  and (shared_with is null or public.has_active_link(auth.uid(), shared_with)));
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
create table public.medications (
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
create policy meds_read on public.medications for select using (public.can_view_medical(patient_id, prescribed_by));
-- The patient fully manages medicines they added themselves; prescribed ones change through functions.
create policy meds_insert_own on public.medications for insert with check (patient_id = auth.uid() and prescribed_by is null);
create policy meds_update_own on public.medications for update
  using (patient_id = auth.uid() and prescribed_by is null)
  with check (patient_id = auth.uid() and prescribed_by is null);
create policy meds_delete_own on public.medications for delete using (patient_id = auth.uid() and prescribed_by is null);
revoke all on public.medications from anon;
grant select, insert, update, delete on public.medications to authenticated;
drop trigger if exists medications_touch on public.medications;
create trigger medications_touch before update on public.medications for each row execute function public.touch_updated_at();

create table public.medication_doses (
  id            bigserial primary key,
  medication_id uuid not null references public.medications(id) on delete cascade,
  patient_id    uuid not null references public.patients(id) on delete cascade,
  taken_at      timestamptz not null default now()
);
create index if not exists idx_doses_med on public.medication_doses (medication_id, taken_at desc);
alter table public.medication_doses enable row level security;
create policy doses_read on public.medication_doses for select using (public.can_view_medical(patient_id, null)
  or exists (select 1 from public.medications m where m.id = medication_id
             and public.can_view_medical(m.patient_id, m.prescribed_by)));
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

create table public.appointments (
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
create policy appts_read on public.appointments for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings') or public.is_admin());
revoke all on public.appointments from anon;
grant select on public.appointments to authenticated;
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
