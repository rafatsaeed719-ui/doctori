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
create policy meds_read on public.medications for select
  using (public.can_view_medical(patient_id, coalesce(prescribed_by, review_doctor)));
drop policy if exists meds_insert_own on public.medications;
create policy meds_insert_own on public.medications for insert with check (
  patient_id = auth.uid() and prescribed_by is null
  and (review_doctor is null or public.has_active_link(auth.uid(), review_doctor)));
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
create table public.case_plans (
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
create policy plans_read on public.case_plans for select using (public.can_view_medical(patient_id, doctor_id));
revoke all on public.case_plans from anon;
grant select on public.case_plans to authenticated;
drop trigger if exists case_plans_touch on public.case_plans;
create trigger case_plans_touch before update on public.case_plans for each row execute function public.touch_updated_at();

create table public.case_plan_history (
  id            bigserial primary key,
  plan_id       uuid not null references public.case_plans(id) on delete cascade,
  data          jsonb not null,
  sessions_done int,
  status        text,
  changed_by    uuid references public.profiles(id) on delete set null,
  changed_at    timestamptz not null default now()
);
alter table public.case_plan_history enable row level security;
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
create table public.followups (
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
create policy followups_read on public.followups for select using (
  patient_id = auth.uid() or public.acts_for(doctor_id, 'bookings') or public.acts_for(doctor_id, 'medical') or public.is_admin());
revoke all on public.followups from anon;
grant select on public.followups to authenticated;
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
